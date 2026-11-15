import { Hono } from 'hono';
import { and, eq, gte } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { abuseReport, shareLink, publication, publicationAbuseReport } from '~/db/schema';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { findByToken, revokeByTokenAsAdmin } from '~/services/shareLinks';
import { hmacSha256Hex } from '~/lib/hash';
import { log } from '~/lib/logger';

export const abuseRoutes = new Hono<AppBindings>();

abuseRoutes.get('/', (c) => {
  const slug = c.req.query('publication');
  if (!slug || !/^[a-z2-7]{10}$/.test(slug))
    return problem(c, 400, 'invalid_report', 'Bad Request');
  return c.html(
    `<!doctype html><html><head><meta name="robots" content="noindex"><title>Report publication</title></head><body><h1>Report publication</h1><form method="post" action="/v1/abuse-reports"><input type="hidden" name="publicationSlug" value="${slug}"><label>Reason <select name="reason"><option value="phishing">Phishing</option><option value="malware">Malware</option><option value="spam">Spam</option><option value="other">Other</option></select></label><button type="submit">Report</button></form></body></html>`,
    200,
    {
      'Content-Security-Policy':
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
      'X-Robots-Tag': 'noindex',
    },
  );
});

const reportSchema = z.object({
  token: z.string().min(1).max(64),
  reason: z.enum(['phishing', 'malware', 'spam', 'other']),
});

abuseRoutes.post(
  '/',
  ratelimit({ bucket: 'abuse_report', limit: 5, windowSeconds: 3600, keyFrom: 'ip' }),
  async (c) => {
    const body = c.req.header('content-type')?.includes('application/x-www-form-urlencoded')
      ? await c.req.parseBody()
      : await c.req.json().catch(() => null);
    if (body && typeof body === 'object' && 'publicationSlug' in body) {
      const input = z
        .object({
          publicationSlug: z.string().regex(/^[a-z2-7]{10}$/),
          reason: z.enum(['phishing', 'malware', 'spam', 'other']),
        })
        .safeParse(body);
      if (!input.success) return problem(c, 400, 'invalid_report', 'Bad Request');
      const db = createDb(c.env.DATABASE_URL);
      const [pub] = await db
        .select()
        .from(publication)
        .where(eq(publication.slug, input.data.publicationSlug))
        .limit(1);
      if (!pub) return problem(c, 404, 'not_found', 'Not Found');
      const ip = c.req.header('cf-connecting-ip');
      const ipHash = ip
        ? await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, `abuse-report-ip:${ip}`)
        : null;
      const [report] = await db
        .insert(publicationAbuseReport)
        .values({ publicationId: pub.id, reason: input.data.reason, ipHash })
        .returning();
      if (ipHash && pub.status === 'active') {
        const cutoff = new Date(Date.now() - 86400_000);
        const recent = await db
          .select()
          .from(publicationAbuseReport)
          .where(
            and(
              eq(publicationAbuseReport.publicationId, pub.id),
              gte(publicationAbuseReport.createdAt, cutoff),
            ),
          );
        if (
          new Set(recent.filter((r) => r.ipHash && r.createdAt >= cutoff).map((r) => r.ipHash))
            .size >= 3
        ) {
          await db
            .update(publication)
            .set({ status: 'suspended', updatedAt: new Date() })
            .where(eq(publication.id, pub.id));
          await c.env.RATE_LIMIT.delete(`pub:cache:${pub.slug}`);
        }
      }
      return c.json({ id: report?.id, status: 'received' }, 201);
    }
    const parsed = reportSchema.safeParse(body);
    if (!parsed.success) return problem(c, 400, 'invalid_report', 'Bad Request', 'invalid report');

    const db = createDb(c.env.DATABASE_URL);
    const link = await findByToken(db, parsed.data.token);
    if (!link) return problem(c, 404, 'not_found', 'Not Found', 'share link not found');
    const ip = c.req.header('cf-connecting-ip');
    const ipHash = ip
      ? await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, `abuse-report-ip:${ip}`)
      : null;
    const [report] = await db
      .insert(abuseReport)
      .values({ shareLinkId: link.id, reason: parsed.data.reason, ipHash })
      .returning({ id: abuseReport.id });
    if (!report) throw new Error('abuse report insert returned no row');
    log.info({
      msg: 'abuse_report_received',
      token: parsed.data.token,
      reason: parsed.data.reason,
    });

    if (ipHash && (link.linkStatus === 'active' || link.linkStatus === 'pending')) {
      const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
      const recent = await db
        .select({ ipHash: abuseReport.ipHash, createdAt: abuseReport.createdAt })
        .from(abuseReport)
        .where(and(eq(abuseReport.shareLinkId, link.id), gte(abuseReport.createdAt, cutoff)));
      const distinctIps = new Set(
        recent.filter((row) => row.createdAt >= cutoff && row.ipHash).map((row) => row.ipHash),
      );
      if (distinctIps.size >= 3) await revokeByTokenAsAdmin(db, parsed.data.token);
    }
    return c.json({ id: report.id, status: 'received' }, 201);
  },
);

abuseRoutes.post('/:id/revoke', async (c) => {
  const configuredToken = c.env.ADMIN_TOKEN;
  if (!configuredToken) {
    return problem(
      c,
      503,
      'admin_unavailable',
      'Service Unavailable',
      'admin access is not configured',
    );
  }
  const bearer = c.req.header('authorization')?.match(/^Bearer (.{1,4096})$/)?.[1];
  if (!bearer || !(await sameSecret(bearer, configuredToken))) {
    return problem(c, 401, 'unauthorized', 'Unauthorized', 'admin token required');
  }
  const parsedId = z.string().uuid().safeParse(c.req.param('id'));
  if (!parsedId.success) return problem(c, 400, 'invalid_id', 'Bad Request', 'invalid report id');

  const db = createDb(c.env.DATABASE_URL);
  const [report] = await db
    .select()
    .from(abuseReport)
    .where(eq(abuseReport.id, parsedId.data))
    .limit(1);
  if (!report) return problem(c, 404, 'not_found', 'Not Found', 'report not found');
  const [link] = await db
    .select()
    .from(shareLink)
    .where(eq(shareLink.id, report.shareLinkId))
    .limit(1);
  if (!link) return problem(c, 404, 'not_found', 'Not Found', 'share link not found');
  const revoked = await revokeByTokenAsAdmin(db, link.token);
  await db.update(abuseReport).set({ resolvedAt: new Date() }).where(eq(abuseReport.id, report.id));
  return c.json({ ok: true, linkStatus: revoked?.linkStatus ?? link.linkStatus });
});

async function sameSecret(a: string, b: string): Promise<boolean> {
  const [aHash, bHash] = await Promise.all([
    crypto.subtle.digest('SHA-256', new TextEncoder().encode(a)),
    crypto.subtle.digest('SHA-256', new TextEncoder().encode(b)),
  ]);
  const aa = new Uint8Array(aHash);
  const bb = new Uint8Array(bHash);
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i]! ^ bb[i]!;
  return diff === 0;
}
