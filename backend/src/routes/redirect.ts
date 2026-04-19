import { Hono, type Context, type MiddlewareHandler } from 'hono';
import { eq } from 'drizzle-orm';
import type { AppBindings } from '~/env';
import { createDb, type Db } from '~/db/client';
import { asset, type Asset, type ShareLink } from '~/db/schema';
import { findByToken, incrementAccess, markExpiredByToken } from '~/services/shareLinks';
import { getObjectStream, type R2GetRange } from '~/services/r2';
import { parseRangeHeader } from '~/lib/httpRange';
import { contentDispositionAttachment } from '~/lib/contentDisposition';
import { renderGonePage, renderPreviewPage } from '~/lib/previewPage';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { log } from '~/lib/logger';

export const redirectRoutes = new Hono<AppBindings>();

// Public, unauthenticated endpoint. Two independent rate-limit buckets:
//  - per client IP (blunt abuse floor),
//  - per token (single-link hotlink / scraping blast).
redirectRoutes.use(
  '*',
  ratelimit({ bucket: 'redirect_ip', limit: 60, windowSeconds: 60, keyFrom: 'ip' }),
);
redirectRoutes.use(
  '*',
  tokenRateLimit({ bucket: 'redirect_token', limit: 300, windowSeconds: 60 }),
);

redirectRoutes.get('/:token/download', (c) => binaryHandler(c));
// Hono doesn't expose a dedicated .head() — register via the generic `.on()`.
// Resumable-download clients probe with HEAD before issuing ranged GETs.
redirectRoutes.on('HEAD', '/:token', (c) => binaryHandler(c));
redirectRoutes.get('/:token', (c) => dispatchHandler(c));

redirectRoutes.post('/:token/verify', (c) => {
  return problem(
    c,
    501,
    'not_implemented',
    'Not Implemented',
    'password-protected share links are post-MVP',
  );
});

interface LoadedLinkAndAsset {
  status: 'ok';
  link: ShareLink;
  assetRow: Asset;
}
type LoadResult =
  | LoadedLinkAndAsset
  | { status: 'not_found' }
  | { status: 'gone'; reason: 'expired' | 'revoked' | 'deleted' };

async function loadActiveLinkAndAsset(
  c: Context<AppBindings>,
  db: Db,
  token: string,
): Promise<LoadResult> {
  const link = await findByToken(db, token);
  if (!link) return { status: 'not_found' };
  if (link.linkStatus === 'revoked') return { status: 'gone', reason: 'revoked' };
  const now = Date.now();
  if (link.expiresAt.getTime() <= now) {
    // Lazy flip so the stored state matches reality for observers.
    c.executionCtx.waitUntil(
      markExpiredByToken(db, token).catch((err) => {
        log.warn({
          msg: 'lazy_expire_failed',
          token,
          error: err instanceof Error ? err.message : String(err),
        });
      }),
    );
    return { status: 'gone', reason: 'expired' };
  }
  const [a] = await db.select().from(asset).where(eq(asset.id, link.assetId)).limit(1);
  if (!a || a.deletedAt !== null || a.status === 'deleted') {
    return { status: 'gone', reason: 'deleted' };
  }
  return { status: 'ok', link, assetRow: a };
}

async function dispatchHandler(c: Context<AppBindings>): Promise<Response> {
  const token = c.req.param('token') ?? '';
  if (!token) return goneOrNotFoundJson(c, 404, 'not_found', 'missing token');
  const db = createDb(c.env.DATABASE_URL);
  const loaded = await loadActiveLinkAndAsset(c, db, token);
  if (loaded.status === 'not_found') {
    return goneOrNotFoundHtml(c, 404, 'not_found', 'unknown token');
  }
  if (loaded.status === 'gone') {
    return goneOrNotFoundHtml(c, 410, 'gone', loaded.reason);
  }

  if (loaded.link.visibility === 'password') {
    return problem(
      c,
      501,
      'not_implemented',
      'Not Implemented',
      'password-protected share links are post-MVP',
    );
  }

  const wantsDownload = c.req.query('dl') === '1' || !acceptsHtml(c.req.header('accept'));
  if (wantsDownload) {
    return binaryHandler(c);
  }

  // Preview page (HTML).
  c.executionCtx.waitUntil(
    incrementAccess(db, token).catch((err) => {
      log.warn({
        msg: 'access_increment_failed',
        requestId: c.get('requestId'),
        token,
        error: err instanceof Error ? err.message : String(err),
      });
    }),
  );

  return renderPreviewPage({
    filename: loaded.assetRow.originalFilename ?? 'download',
    sizeBytes: loaded.assetRow.sizeBytes,
    contentType: loaded.assetRow.contentType,
    expiresAt: loaded.link.expiresAt,
    downloadUrl: `${c.env.SHORT_LINK_HOST}/s/${token}/download`,
    canonicalUrl: `${c.env.SHORT_LINK_HOST}/s/${token}`,
    ogImageUrl: `${c.env.SHORT_LINK_HOST}/og-image.png`,
  });
}

async function binaryHandler(c: Context<AppBindings>): Promise<Response> {
  const token = c.req.param('token') ?? '';
  if (!token) return goneOrNotFoundJson(c, 404, 'not_found', 'missing token');
  const db = createDb(c.env.DATABASE_URL);
  const loaded = await loadActiveLinkAndAsset(c, db, token);
  if (loaded.status === 'not_found') {
    return goneOrNotFoundJson(c, 404, 'not_found', 'unknown token');
  }
  if (loaded.status === 'gone') {
    return goneOrNotFoundJson(c, 410, 'gone', loaded.reason);
  }
  if (loaded.link.visibility === 'password') {
    return problem(
      c,
      501,
      'not_implemented',
      'Not Implemented',
      'password-protected share links are post-MVP',
    );
  }

  const isHead = c.req.method === 'HEAD';
  const a = loaded.assetRow;
  const totalSize = a.sizeBytes;

  const parsed = parseRangeHeader(c.req.header('range') ?? null, totalSize);
  if (parsed.kind === 'unsatisfiable') {
    const h = new Headers();
    h.set('Content-Range', `bytes */${totalSize}`);
    h.set('Content-Type', 'text/plain; charset=utf-8');
    applySecurityHeaders(h);
    return new Response(isHead ? null : 'Range Not Satisfiable', { status: 416, headers: h });
  }

  let r2Range: R2GetRange | undefined;
  let status = 200;
  let contentLength = totalSize;
  let contentRange: string | null = null;
  let effectiveOffset = 0;

  if (parsed.kind === 'range') {
    r2Range = { offset: parsed.offset, length: parsed.length };
    status = 206;
    contentLength = parsed.length;
    contentRange = `bytes ${parsed.offset}-${parsed.offset + parsed.length - 1}/${totalSize}`;
    effectiveOffset = parsed.offset;
  } else if (parsed.kind === 'suffix') {
    r2Range = { suffix: parsed.suffix };
    status = 206;
    contentLength = parsed.suffix;
    const startOffset = Math.max(0, totalSize - parsed.suffix);
    contentRange = `bytes ${startOffset}-${totalSize - 1}/${totalSize}`;
    effectiveOffset = startOffset;
  }

  const headers = new Headers();
  headers.set('Content-Type', a.contentType);
  headers.set(
    'Content-Disposition',
    contentDispositionAttachment(a.originalFilename ?? 'download'),
  );
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Content-Length', String(contentLength));
  if (contentRange) headers.set('Content-Range', contentRange);
  applySecurityHeaders(headers);

  if (isHead) {
    return new Response(null, { status, headers });
  }

  const result = await getObjectStream(c.env, a.storageKey, r2Range);
  if (!result) {
    // Row exists but object doesn't — treat as deleted.
    return goneOrNotFoundJson(c, 410, 'gone', 'deleted');
  }

  // Only count an access on the leading (or non-ranged) request. Media
  // clients often issue a HEAD + several byte-range GETs per playback —
  // we don't want one view to multiply the access counter.
  if (effectiveOffset === 0) {
    c.executionCtx.waitUntil(
      incrementAccess(db, token).catch((err) => {
        log.warn({
          msg: 'access_increment_failed',
          requestId: c.get('requestId'),
          token,
          error: err instanceof Error ? err.message : String(err),
        });
      }),
    );
  }

  return new Response(result.body, { status, headers });
}

function acceptsHtml(accept: string | undefined | null): boolean {
  if (!accept) return false;
  // Treat `text/html` or `application/xhtml+xml` as HTML-preferring. `*/*` or
  // `application/octet-stream` → no preview, give them the bytes.
  const lower = accept.toLowerCase();
  return lower.includes('text/html') || lower.includes('application/xhtml+xml');
}

interface TokenRateLimitOpts {
  bucket: string;
  limit: number;
  windowSeconds: number;
}

// Per-token fixed-window limiter. Mirrors the middleware's shape but keys on
// the URL param so one hot link can't exhaust the IP bucket for everyone else.
function tokenRateLimit(opts: TokenRateLimitOpts): MiddlewareHandler<AppBindings> {
  return async (c, next) => {
    const token = c.req.param('token');
    if (!token) {
      await next();
      return;
    }
    const now = Math.floor(Date.now() / 1000);
    const windowStart = now - (now % opts.windowSeconds);
    const key = `rl:tok:${token}:${opts.bucket}:${windowStart}`;
    const ttl = opts.windowSeconds + 60;
    const existing = await c.env.RATE_LIMIT.get(key);
    const current = existing ? Number(existing) : 0;
    if (!Number.isFinite(current)) {
      await c.env.RATE_LIMIT.put(key, '1', { expirationTtl: ttl });
    } else if (current >= opts.limit) {
      const retryAfter = windowStart + opts.windowSeconds - now;
      const res = problem(
        c,
        429,
        'rate_limited',
        'Too Many Requests',
        `Limit of ${opts.limit} per ${opts.windowSeconds}s exceeded for bucket '${opts.bucket}'`,
      );
      res.headers.set('Retry-After', String(Math.max(retryAfter, 1)));
      return res;
    } else {
      await c.env.RATE_LIMIT.put(key, String(current + 1), { expirationTtl: ttl });
    }
    await next();
  };
}

function applySecurityHeaders(h: Headers): void {
  h.set('Cache-Control', 'private, no-store');
  h.set('X-Robots-Tag', 'noindex, nofollow');
  h.set('Referrer-Policy', 'no-referrer');
  h.set('X-Content-Type-Options', 'nosniff');
}

function goneOrNotFoundHtml(
  c: Context<AppBindings>,
  status: 404 | 410,
  code: 'not_found' | 'gone',
  reason: string,
): Response {
  if (!acceptsHtml(c.req.header('accept'))) {
    return goneOrNotFoundJson(c, status, code, reason);
  }
  if (status === 410) {
    const normalized: 'expired' | 'revoked' | 'deleted' =
      reason === 'expired' || reason === 'revoked' || reason === 'deleted' ? reason : 'deleted';
    return renderGonePage(normalized);
  }
  // 404 HTML — mimic the gone page styling via a synthetic reason.
  const res = renderGonePage('deleted');
  // Swap the status code; body copy is close enough for the unknown-token case.
  return new Response(res.body, { status: 404, headers: res.headers });
}

function goneOrNotFoundJson(
  c: Context<AppBindings>,
  status: 404 | 410,
  code: 'not_found' | 'gone',
  reason: string,
): Response {
  const res = problem(
    c,
    status,
    code,
    status === 404 ? 'Not Found' : 'Gone',
    reason,
  );
  applySecurityHeaders(res.headers);
  return res;
}

