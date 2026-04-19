import { Hono, type Context, type MiddlewareHandler } from 'hono';
import { eq } from 'drizzle-orm';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { asset } from '~/db/schema';
import { findByToken, incrementAccess, markExpiredByToken } from '~/services/shareLinks';
import { presignGet } from '~/services/r2';
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

redirectRoutes.get('/:token', async (c) => {
  const token = c.req.param('token');
  const db = createDb(c.env.DATABASE_URL);

  const link = await findByToken(db, token);
  if (!link) return goneOrNotFound(c, 404, 'not_found', 'unknown token');

  if (link.linkStatus === 'revoked') {
    return goneOrNotFound(c, 410, 'gone', 'revoked');
  }

  const now = Date.now();
  if (link.expiresAt.getTime() <= now) {
    // Lazy flip so the state matches reality for observers.
    c.executionCtx.waitUntil(
      markExpiredByToken(db, token).catch((err) => {
        log.warn({
          msg: 'lazy_expire_failed',
          token,
          error: err instanceof Error ? err.message : String(err),
        });
      }),
    );
    return goneOrNotFound(c, 410, 'gone', 'expired');
  }

  const [a] = await db.select().from(asset).where(eq(asset.id, link.assetId)).limit(1);
  if (!a || a.deletedAt !== null || a.status === 'deleted') {
    return goneOrNotFound(c, 410, 'gone', 'deleted');
  }

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

  if (link.visibility === 'password') {
    return problem(
      c,
      501,
      'not_implemented',
      'Not Implemented',
      'password-protected share links are post-MVP',
    );
  }

  // 60s signed URL — short enough that a leaked Location header decays quickly.
  const signedUrl = await presignGet({ env: c.env, key: a.storageKey, expiresIn: 60 });
  return redirectResponse(signedUrl);
});

redirectRoutes.post('/:token/verify', (c) => {
  return problem(
    c,
    501,
    'not_implemented',
    'Not Implemented',
    'password-protected share links are post-MVP',
  );
});

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

function securityHeaders(): Record<string, string> {
  return {
    'Cache-Control': 'no-store',
    'X-Robots-Tag': 'noindex, nofollow',
    'Referrer-Policy': 'no-referrer',
  };
}

function redirectResponse(location: string): Response {
  return new Response(null, {
    status: 302,
    headers: { Location: location, ...securityHeaders() },
  });
}

function goneOrNotFound(
  c: Context<AppBindings>,
  status: 404 | 410,
  code: 'not_found' | 'gone',
  reason: string,
): Response {
  const accept = c.req.header('accept') ?? '';
  const wantsJson = accept.includes('application/json');
  if (wantsJson) {
    return new Response(JSON.stringify({ error: code, reason }), {
      status,
      headers: { 'content-type': 'application/json', ...securityHeaders() },
    });
  }
  return new Response(goneHtml(status, reason), {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8', ...securityHeaders() },
  });
}

function goneHtml(status: number, reason: string): string {
  const title = status === 404 ? 'Link not found' : 'Link no longer available';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="referrer" content="no-referrer" />
<meta name="robots" content="noindex,nofollow" />
<title>FastShared</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0b0b0f; color: #eee; display: grid; place-items: center; min-height: 100vh; margin: 0; }
  main { text-align: center; padding: 32px; }
  h1 { font-size: 20px; margin: 0 0 8px; }
  p { color: #aaa; margin: 0; }
</style>
</head>
<body>
<main>
  <h1>${title}</h1>
  <p>${escapeHtml(reason)}</p>
</main>
</body>
</html>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
