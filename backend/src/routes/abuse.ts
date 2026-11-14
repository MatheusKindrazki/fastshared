import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { abuseReport, shareLink } from '~/db/schema';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { findByToken, revokeByTokenAsAdmin } from '~/services/shareLinks';

export const abuseRoutes = new Hono<AppBindings>();

const reportSchema = z.object({
  token: z.string().min(1).max(64),
  reason: z.enum(['phishing', 'malware', 'spam', 'other']),
});

abuseRoutes.post(
  '/',
  ratelimit({ bucket: 'abuse_report', limit: 5, windowSeconds: 3600, keyFrom: 'ip' }),
  async (c) => {
    const body = await c.req.json().catch(() => null);
    const parsed = reportSchema.safeParse(body);
    if (!parsed.success) return problem(c, 400, 'invalid_report', 'Bad Request', 'invalid report');

    const db = createDb(c.env.DATABASE_URL);
    const link = await findByToken(db, parsed.data.token);
    if (!link) return problem(c, 404, 'not_found', 'Not Found', 'share link not found');
    const [report] = await db
      .insert(abuseReport)
      .values({ shareLinkId: link.id, reason: parsed.data.reason })
      .returning({ id: abuseReport.id });
    if (!report) throw new Error('abuse report insert returned no row');
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
