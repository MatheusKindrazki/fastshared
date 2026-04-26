import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppBindings } from '~/env';
import { log } from '~/lib/logger';

// Public static assets served by the Worker so Slack/iMessage/Discord
// card-unfurlers and generated short-link pages can fetch brand files without
// a Pages origin round-trip on every scrape. We proxy the bytes from the Pages
// origin once and cache at the Worker edge for a day.
const PAGES_ORIGIN = 'https://fastshared-web.pages.dev';
const CACHE_MAX_AGE_SECONDS = 86_400;

export const assetsPublicRoutes = new Hono<AppBindings>();

const PUBLIC_ASSETS: Record<string, string> = {
  '/og-image.png': 'image/png',
  '/brand/appicon-1024.png': 'image/png',
  '/brand/logo-mark.png': 'image/png',
  '/brand/logo-horizontal.png': 'image/png',
  '/brand/wordmark-horizontal-dark.png': 'image/png',
  '/brand/wordmark-horizontal-light.png': 'image/png',
  '/brand/wordmark-mark.png': 'image/png',
  '/brand/og-image.png': 'image/png',
  '/brand/appicon.svg': 'image/svg+xml; charset=utf-8',
  '/brand/logo-mark.svg': 'image/svg+xml; charset=utf-8',
  '/brand/logo-horizontal.svg': 'image/svg+xml; charset=utf-8',
};

async function proxyPublicAsset(pathname: string, c: Context<AppBindings>) {
  // Cloudflare Workers exposes a per-colocated-edge cache as `caches.default`
  // (non-standard global). The `CacheStorage` lib type doesn't know about it,
  // so we widen to `any` at the call site only.
  const contentType = PUBLIC_ASSETS[pathname];
  if (!contentType) {
    return new Response('asset unavailable', {
      status: 404,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  }

  const cache = (caches as unknown as { default: Cache }).default;
  const cacheKey = new Request(`${c.env.SHORT_LINK_HOST}${pathname}`, { method: 'GET' });
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

  const origin = await fetch(`${PAGES_ORIGIN}${pathname}`);
  if (!origin.ok) {
    log.warn({
      msg: 'public_asset_origin_miss',
      pathname,
      status: origin.status,
      requestId: c.get('requestId'),
    });
    return new Response('asset unavailable', {
      status: 502,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  }

  const buf = await origin.arrayBuffer();
  const body = new Uint8Array(buf);
  const h = new Headers();
  h.set('Content-Type', contentType);
  h.set('Cache-Control', `public, max-age=${CACHE_MAX_AGE_SECONDS}, immutable`);
  h.set('Content-Length', String(body.byteLength));
  h.set('CF-Cache-Status', 'MISS');
  const res = new Response(body, { status: 200, headers: h });
  // Clone before returning so the cache can consume the body independently.
  c.executionCtx.waitUntil(cache.put(cacheKey, res.clone()));
  return res;
}

assetsPublicRoutes.get('/og-image.png', async (c) => {
  return proxyPublicAsset('/og-image.png', c);
});

assetsPublicRoutes.get('/brand/:asset', async (c) => {
  return proxyPublicAsset(`/brand/${c.req.param('asset')}`, c);
});
