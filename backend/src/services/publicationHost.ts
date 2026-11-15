import { and, eq, lt } from 'drizzle-orm';
import { createDb } from '~/db/client';
import {
  publication,
  publicationFile,
  publicationOpen,
  publicationOpenClaim,
  publicationVersion,
} from '~/db/schema';
import type { Publication } from '~/db/schema';
import type { Env } from '~/env';
import { hmacSha256Hex } from '~/lib/hash';
import { sendLinkOpenedNotification } from '~/services/apns';

const HEADERS = {
  'Content-Security-Policy':
    "sandbox allow-scripts allow-same-origin allow-popups allow-downloads; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Robots-Tag': 'noindex',
  'Cache-Control': 'private, max-age=0',
};

export function publicationSlugFromHost(host: string, suffix: string | undefined): string | null {
  if (!suffix || !host.endsWith(`.${suffix}`)) return null;
  const prefix = host.slice(0, -suffix.length - 1);
  return /^p-[a-z2-7]{10}$/.test(prefix) ? prefix.slice(2) : null;
}

function neutral(status: number): Response {
  return new Response(
    '<!doctype html><title>Unavailable</title><p>This publication is unavailable.</p>',
    { status, headers: { ...HEADERS, 'Content-Type': 'text/html; charset=utf-8' } },
  );
}

function isBrowser(ua: string | null): boolean {
  if (!ua) return false;
  const s = ua.toLowerCase();
  return (
    s.includes('mozilla/') &&
    !/(bot|crawler|spider|headless|whatsapp|slack|telegram|linkedin|facebook|twitter|discord|preview)/.test(
      s,
    )
  );
}

async function openedRateLimited(req: Request, env: Env, slug: string): Promise<boolean> {
  const ip = req.headers.get('cf-connecting-ip') ?? 'unknown';
  const window = Math.floor(Date.now() / 60000);
  const identity = (await hmacSha256Hex(env.DEVICE_TOKEN_PEPPER, `${ip}:${slug}`)).slice(0, 32);
  const key = `rl:publication-open:${identity}:${window}`;
  const current = Number((await env.RATE_LIMIT.get(key)) ?? 0);
  if (current >= 30) return true;
  await env.RATE_LIMIT.put(key, String(Number.isFinite(current) ? current + 1 : 1), {
    expirationTtl: 120,
  });
  return false;
}

async function cachedPublication(
  env: Env,
  slug: string,
  db: ReturnType<typeof createDb>,
): Promise<Publication | null> {
  const key = `pub:cache:${slug}`;
  const cached = await env.RATE_LIMIT.get(key);
  if (cached) {
    const row = JSON.parse(cached) as Publication;
    return {
      ...row,
      expiresAt: row.expiresAt ? new Date(row.expiresAt) : null,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
      deletedAt: row.deletedAt ? new Date(row.deletedAt) : null,
    };
  }
  const [row] = await db.select().from(publication).where(eq(publication.slug, slug)).limit(1);
  if (row) await env.RATE_LIMIT.put(key, JSON.stringify(row), { expirationTtl: 60 });
  return row ?? null;
}

export function beaconScript(versionId: string): string {
  return `<script>(function(){try{if(document.visibilityState!=='visible')return;var key='fs:open:${versionId}',now=Date.now();if(now-Number(localStorage.getItem(key+':at')||0)<86400000)return;var id=localStorage.getItem('fs:visitor');if(!id){id=crypto.randomUUID();localStorage.setItem('fs:visitor',id)}setTimeout(function(){if(document.visibilityState!=='visible')return;fetch('/opened',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({visitor:id}),keepalive:true,credentials:'omit'}).then(function(r){if(r.ok)localStorage.setItem(key+':at',String(Date.now()))}).catch(function(){})},1500)}catch(e){}})();</script>`;
}

function badge(slug: string, apiHost: string): string {
  return `<footer style="position:fixed;bottom:0;right:0;z-index:2147483647;background:#fff;color:#111;padding:8px 12px;font:12px system-ui;box-shadow:0 1px 8px #777">Hosted with FastShared · <a href="${apiHost}/v1/abuse-reports?publication=${slug}" rel="nofollow noopener">Report</a></footer>`;
}

async function recordOpen(
  env: Env,
  slug: string,
  visitor: string,
  isPdf: boolean,
  ctx: ExecutionContext,
): Promise<Response> {
  if (!/^[a-zA-Z0-9-]{16,128}$/.test(visitor)) return neutral(400);
  const db = createDb(env.DATABASE_URL);
  const [pub] = await db.select().from(publication).where(eq(publication.slug, slug)).limit(1);
  if (
    !pub ||
    pub.status !== 'active' ||
    (pub.expiresAt && pub.expiresAt <= new Date()) ||
    !pub.currentVersionId
  )
    return neutral(410);
  const [current] = await db
    .select()
    .from(publicationVersion)
    .where(eq(publicationVersion.id, pub.currentVersionId))
    .limit(1);
  if (!current || (current.kind === 'pdf') !== isPdf)
    return new Response(null, { status: 204, headers: HEADERS });
  const visitorHash = await hmacSha256Hex(
    env.DEVICE_TOKEN_PEPPER,
    `publication:${pub.id}:${visitor}`,
  );
  const now = new Date();
  const cutoff = new Date(now.getTime() - 86400_000);
  const claimed = await db
    .insert(publicationOpenClaim)
    .values({
      publicationId: pub.id,
      versionId: pub.currentVersionId,
      visitorHash,
      lastOpenedAt: now,
    })
    .onConflictDoUpdate({
      target: [
        publicationOpenClaim.publicationId,
        publicationOpenClaim.versionId,
        publicationOpenClaim.visitorHash,
      ],
      set: { lastOpenedAt: now },
      setWhere: lt(publicationOpenClaim.lastOpenedAt, cutoff),
    })
    .returning();
  if (!claimed.length) return new Response(null, { status: 204, headers: HEADERS });
  await db
    .insert(publicationOpen)
    .values({ publicationId: pub.id, versionId: pub.currentVersionId, visitorHash })
    .returning();
  if (pub.notifyOnOpen) {
    const prior = await db
      .select()
      .from(publicationOpen)
      .where(eq(publicationOpen.publicationId, pub.id));
    if (pub.expiresAt === null || prior.length <= 3) {
      ctx.waitUntil(
        sendLinkOpenedNotification({
          env,
          db,
          deviceId: pub.ownerDeviceId,
          token: slug,
          filename: isPdf ? 'PDF opened' : pub.title,
          shortUrl: `https://p-${slug}.${env.PUBLICATION_HOST_SUFFIX}`,
        }).catch(() => undefined),
      );
    }
  }
  return new Response(null, { status: 204, headers: HEADERS });
}

export async function servePublication(
  req: Request,
  env: Env,
  ctx: ExecutionContext,
  slug: string,
): Promise<Response> {
  const url = new URL(req.url);
  if (url.pathname === '/opened') {
    if (req.method !== 'POST' || !isBrowser(req.headers.get('user-agent')))
      return new Response(null, { status: 204, headers: HEADERS });
    if (await openedRateLimited(req, env, slug))
      return new Response(null, { status: 429, headers: { ...HEADERS, 'Retry-After': '60' } });
    const body = (await req.json().catch(() => null)) as { visitor?: unknown } | null;
    return recordOpen(env, slug, typeof body?.visitor === 'string' ? body.visitor : '', false, ctx);
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') return neutral(404);
  const db = createDb(env.DATABASE_URL);
  const pub = await cachedPublication(env, slug, db);
  if (!pub) return neutral(404);
  if (
    pub.status !== 'active' ||
    (pub.expiresAt && pub.expiresAt <= new Date()) ||
    !pub.currentVersionId
  )
    return neutral(410);
  const [version] = await db
    .select()
    .from(publicationVersion)
    .where(eq(publicationVersion.id, pub.currentVersionId))
    .limit(1);
  if (!version || version.state !== 'ready' || !version.entryPath) return neutral(404);
  let wanted: string;
  try {
    wanted = url.pathname === '/' ? version.entryPath : decodeURIComponent(url.pathname.slice(1));
  } catch {
    return neutral(404);
  }
  if (
    wanted.startsWith('/') ||
    wanted.split('/').some((p) => p === '..' || p === '.') ||
    wanted.includes('\\')
  )
    return neutral(404);
  const [file] = await db
    .select()
    .from(publicationFile)
    .where(and(eq(publicationFile.versionId, version.id), eq(publicationFile.path, wanted)))
    .limit(1);
  if (!file) return neutral(404);
  const obj = await env.PUBLICATIONS.get(file.storageKey);
  if (!obj) return neutral(404);
  const headers = new Headers(HEADERS);
  headers.set('Content-Type', file.contentType);
  if (file.contentType === 'application/octet-stream')
    headers.set('Content-Disposition', 'attachment');
  if (
    version.kind === 'pdf' &&
    req.method === 'GET' &&
    url.pathname === '/' &&
    isBrowser(req.headers.get('user-agent')) &&
    req.headers.get('sec-fetch-dest') === 'document'
  ) {
    const ip = req.headers.get('cf-connecting-ip');
    if (ip)
      ctx.waitUntil(
        recordOpen(
          env,
          slug,
          `ip-${await hmacSha256Hex(env.DEVICE_TOKEN_PEPPER, ip)}`,
          true,
          ctx,
        ).then(() => undefined),
      );
  }
  if (req.method === 'HEAD') return new Response(null, { headers });
  const res = new Response(obj.body, { headers });
  if (!file.contentType.startsWith('text/html')) return res;
  const freeBadge = pub.expiresAt === null ? '' : badge(slug, env.PUBLIC_API_HOST);
  const base =
    url.pathname === '/' && version.entryPath.includes('/')
      ? `<base href="/${version.entryPath.slice(0, version.entryPath.lastIndexOf('/') + 1)}">`
      : '';
  return new HTMLRewriter()
    .on('head', {
      element(el) {
        if (base) el.prepend(base, { html: true });
      },
    })
    .on('body', {
      element(el) {
        el.append(beaconScript(version.id) + freeBadge, { html: true });
      },
    })
    .transform(res);
}
