import { Hono } from 'hono';
import type { AppBindings } from '~/env';
import { log } from '~/lib/logger';

// Public static assets served by the Worker so Slack/iMessage/Discord
// card-unfurlers hit this file without a Pages origin round-trip for every
// scrape. We proxy the bytes from the Pages origin once and cache at the
// Worker edge for a day. Plan C ships the actual PNG on the Pages origin.
const PAGES_ORIGIN = 'https://fastshared-web.pages.dev';
const CACHE_MAX_AGE_SECONDS = 86_400;

export const assetsPublicRoutes = new Hono<AppBindings>();

assetsPublicRoutes.get('/og-image.png', async (c) => {
  // Cloudflare Workers exposes a per-colocated-edge cache as `caches.default`
  // (non-standard global). The `CacheStorage` lib type doesn't know about it,
  // so we widen to `any` at the call site only.
  const cache = (caches as unknown as { default: Cache }).default;
  const cacheKey = new Request(`${c.env.SHORT_LINK_HOST}/og-image.png`, { method: 'GET' });
  const cached = await cache.match(cacheKey);
  if (cached) {
    // Copy so we can add a HIT marker without mutating the cached response.
    const h = new Headers(cached.headers);
    h.set('CF-Cache-Status', 'HIT');
    return new Response(cached.body, {
      status: cached.status,
      statusText: cached.statusText,
      headers: h,
    });
  }

  const origin = await fetch(`${PAGES_ORIGIN}/og-image.png`);
  if (!origin.ok) {
    log.warn({
      msg: 'og_image_origin_miss',
      status: origin.status,
      requestId: c.get('requestId'),
    });
    return new Response('og-image unavailable', {
      status: 502,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  }

  const buf = await origin.arrayBuffer();
  const body = new Uint8Array(buf);
  const h = new Headers();
  h.set('Content-Type', 'image/png');
  h.set('Cache-Control', `public, max-age=${CACHE_MAX_AGE_SECONDS}, immutable`);
  h.set('Content-Length', String(body.byteLength));
  h.set('CF-Cache-Status', 'MISS');
  const res = new Response(body, { status: 200, headers: h });
  // Clone before returning so the cache can consume the body independently.
  c.executionCtx.waitUntil(cache.put(cacheKey, res.clone()));
  return res;
});
