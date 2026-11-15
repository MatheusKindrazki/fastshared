import { Hono, type Context, type MiddlewareHandler } from 'hono';
import { and, eq } from 'drizzle-orm';
import type { AppBindings } from '~/env';
import { createDb, type Db } from '~/db/client';
import { asset, bundleAsset, type Asset, type ShareLink } from '~/db/schema';
import { findByToken, incrementAccess, markExpiredByToken } from '~/services/shareLinks';
import { sendLinkOpenedNotification } from '~/services/apns';
import { getObjectStream, type R2GetRange } from '~/services/r2';
import { parseRangeHeader } from '~/lib/httpRange';
import { contentDispositionAttachment, contentDispositionInline } from '~/lib/contentDisposition';
import {
  renderBundlePreviewPage,
  renderGonePage,
  renderPendingPage,
  renderPreviewPage,
} from '~/lib/previewPage';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { log } from '~/lib/logger';
import { hmacSha256Hex } from '~/lib/hash';
import { isActiveContentType } from '~/lib/activeContentType';

export const redirectRoutes = new Hono<AppBindings>();
export const bundleRedirectRoutes = new Hono<AppBindings>();

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

redirectRoutes.get('/:token/download', (c) => binaryHandler(c, 'attachment'));
redirectRoutes.get('/:token/raw', (c) => binaryHandler(c, 'inline'));
// Hono doesn't expose a dedicated .head() — register via the generic `.on()`.
// Resumable-download clients probe with HEAD before issuing ranged GETs.
redirectRoutes.on('HEAD', '/:token', (c) => binaryHandler(c, 'attachment'));
redirectRoutes.get('/:token', (c) => dispatchHandler(c));
redirectRoutes.post('/:token/opened', (c) => openedHandler(c));

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
  | { status: 'gone'; reason: 'expired' | 'revoked' | 'deleted' }
  | { status: 'pending'; link: ShareLink };

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
  // Pending: asset hasn't landed yet. Recipient sees the "Uploading…" page.
  if (link.linkStatus === 'pending') return { status: 'pending', link };
  // assetId is nullable on the schema (pending rows), but any non-pending
  // state must have an asset — if it's missing the link is effectively gone.
  if (!link.assetId) return { status: 'gone', reason: 'deleted' };
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
  if (loaded.status === 'pending') {
    // Tier 1: bytes not in R2 yet. upload_job doesn't carry filename/size
    // today (the presign payload is request-only), so the page renders with
    // neutral copy. It's a progress shell, not a preview of the final asset.
    return renderPendingPage({
      filename: 'upload',
      sizeBytes: 0,
      expiresAt: loaded.link.expiresAt,
      canonicalUrl: `${c.env.SHORT_LINK_HOST}/s/${token}`,
    });
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

  const wantsDownload =
    c.req.query('dl') === '1' ||
    !acceptsHtml(c.req.header('accept')) ||
    isAutomatedClient(c.req.header('user-agent'));
  if (wantsDownload) {
    return binaryHandler(c, 'attachment');
  }

  const a = loaded.assetRow;
  // Preview HTML is served to browsers and to unfurlers. Count the fetch,
  // but do not alert: an alert requires the rendered page to call /opened.
  scheduleAccessCount(c, db, token);

  let textPreview: string | undefined;
  let textTruncated = false;
  if (isTextLikeContentType(a.contentType) && a.sizeBytes > 0) {
    const cap = Math.min(TEXT_PREVIEW_CAP_BYTES, a.sizeBytes);
    try {
      const got = await getObjectStream(c.env, a.storageKey, { offset: 0, length: cap });
      if (got) {
        const buf = new Uint8Array(await new Response(got.body).arrayBuffer());
        const decoded = new TextDecoder('utf-8', { fatal: false }).decode(buf);
        // The decoder already replaces malformed UTF-8 with U+FFFD, so a
        // straight slice is safe even if the byte cap landed mid-codepoint.
        textPreview = decoded;
        textTruncated = a.sizeBytes > cap;
      }
    } catch {
      // Fall through — renderer drops to the glyph card on undefined preview.
    }
  }

  return renderPreviewPage({
    filename: a.originalFilename ?? 'download',
    sizeBytes: a.sizeBytes,
    contentType: a.contentType,
    expiresAt: loaded.link.expiresAt,
    downloadUrl: `${c.env.SHORT_LINK_HOST}/s/${token}/download`,
    previewUrl: `${c.env.SHORT_LINK_HOST}/s/${token}/raw`,
    canonicalUrl: `${c.env.SHORT_LINK_HOST}/s/${token}`,
    ogImageUrl: `${c.env.SHORT_LINK_HOST}/og-image.png`,
    openedUrl: `${c.env.SHORT_LINK_HOST}/s/${token}/opened`,
    ...(textPreview !== undefined ? { textPreview, textTruncated } : {}),
  });
}

const TEXT_PREVIEW_CAP_BYTES = 16 * 1024;

function scheduleAccessCount(c: Context<AppBindings>, db: Db, token: string): void {
  c.executionCtx.waitUntil(
    incrementAccess(db, token).catch((err) => {
      log.warn({
        msg: 'access_count_failed',
        requestId: c.get('requestId'),
        token,
        error: err instanceof Error ? err.message : String(err),
      });
    }),
  );
}

function isTextLikeContentType(ct: string): boolean {
  const lower = ct.toLowerCase();
  return (
    lower.startsWith('text/') ||
    lower === 'application/json' ||
    lower === 'application/xml' ||
    lower === 'application/javascript' ||
    lower === 'application/yaml'
  );
}

async function binaryHandler(
  c: Context<AppBindings>,
  mode: 'attachment' | 'inline' = 'attachment',
): Promise<Response> {
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
  if (loaded.status === 'pending') {
    // Pending link has no bytes yet. 404 (not 410) so the pending page's
    // HEAD poll treats it as "keep waiting" rather than "gave up".
    return goneOrNotFoundJson(c, 404, 'not_found', 'upload in progress');
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

  const onLeadingHit = (offset: number) => {
    if (offset !== 0) return;
    scheduleAccessCount(c, db, token);
  };
  return streamAssetBytes(c, loaded.assetRow, mode, onLeadingHit);
}

// Shared R2 streaming for /s/:token and /b/:token/d/:assetId. Centralises
// range parsing, security headers, content-disposition, and HEAD handling so
// both code paths stay byte-for-byte identical.
async function streamAssetBytes(
  c: Context<AppBindings>,
  a: Asset,
  mode: 'attachment' | 'inline',
  onLeadingHit?: (offset: number) => void,
): Promise<Response> {
  const isHead = c.req.method === 'HEAD';
  const active = isActiveContentType(a.contentType);
  const isolatedOrigin = c.env.USER_CONTENT_HOST?.trim();
  if (
    mode === 'inline' &&
    active &&
    isolatedOrigin &&
    new URL(c.req.url).host !== new URL(isolatedOrigin).host
  ) {
    const target = new URL(c.req.path + new URL(c.req.url).search, isolatedOrigin);
    const headers = new Headers({ Location: target.toString() });
    applySecurityHeaders(headers);
    return new Response(null, { status: 302, headers });
  }
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
  const dispositionFilename = a.originalFilename ?? 'download';
  headers.set(
    'Content-Disposition',
    mode === 'inline'
      ? contentDispositionInline(dispositionFilename)
      : contentDispositionAttachment(dispositionFilename),
  );
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Content-Length', String(contentLength));
  if (contentRange) headers.set('Content-Range', contentRange);
  applySecurityHeaders(headers);
  if (active) {
    headers.set(
      'Content-Security-Policy',
      "sandbox; default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'",
    );
  }

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
  if (onLeadingHit) onLeadingHit(effectiveOffset);

  return new Response(result.body, { status, headers });
}

function acceptsHtml(accept: string | undefined | null): boolean {
  if (!accept) return false;
  // Treat `text/html` or `application/xhtml+xml` as HTML-preferring. `*/*` or
  // `application/octet-stream` → no preview, give them the bytes.
  const lower = accept.toLowerCase();
  return lower.includes('text/html') || lower.includes('application/xhtml+xml');
}

// Known link-unfurl bots that need HTML (OG tags). They are not a real open.
const UNFURLER_MARKERS = [
  'slackbot',
  'discordbot',
  'telegrambot',
  'whatsapp',
  'linkedinbot',
  'facebookexternalhit',
  'twitterbot',
  'skypeuripreview',
  'redditbot',
  'embedly',
  'iframely',
  'pinterest',
] as const;

function isUnfurler(ua: string): boolean {
  const lower = ua.toLowerCase();
  return UNFURLER_MARKERS.some((marker) => lower.includes(marker));
}

// Serve the raw file (not the HTML preview) to automated clients even when
// they advertise `Accept: text/html`. Browsers get the preview; everything
// programmatic (curl, wget, HTTP libraries, MCP servers, LLM fetchers,
// scrapers, AI agents) gets the file directly. Link-unfurl bots from social
// apps keep getting HTML so OG previews still render in WhatsApp/Slack/etc.
function isAutomatedClient(ua: string | undefined | null): boolean {
  if (!ua) return true;
  const lower = ua.toLowerCase();

  if (isUnfurler(lower)) return false;

  // Real browsers. `mozilla/` prefix covers Chrome, Safari, Firefox, Edge.
  // Filter OUT "headless" which is usually a scraper pretending to be Chrome.
  if (lower.includes('mozilla/') && !lower.includes('headlesschrome')) {
    return false;
  }

  // Everything else → treat as automation (curl, wget, python-requests,
  // go-http-client, node-fetch, axios, undici, okhttp, java, libwww,
  // ruby, perl, postmanruntime, insomnia, mcp, claude, gpt, openai,
  // anthropic, bot, crawler, spider, scraper).
  return true;
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
    const tokenKey = (await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, token)).slice(0, 32);
    const key = `rl:tok:${tokenKey}:${opts.bucket}:${windowStart}`;
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
  const res = problem(c, status, code, status === 404 ? 'Not Found' : 'Gone', reason);
  applySecurityHeaders(res.headers);
  return res;
}

// One confirmed render per visitor per link. KV TTL is the dedupe window.
const OPENED_VISITOR_TTL_SECONDS = 24 * 60 * 60;
const OPENED_RATE_LIMIT = 30;
const OPENED_RATE_WINDOW_SECONDS = 60;
const VISITOR_ID_PATTERN = /^[A-Za-z0-9_-]{8,80}$/;

function shouldIgnoreOpenBeacon(ua: string | undefined | null): boolean {
  if (!ua) return true;
  if (isUnfurler(ua)) return true;
  return isAutomatedClient(ua);
}

function noContent(): Response {
  const headers = new Headers();
  applySecurityHeaders(headers);
  return new Response(null, { status: 204, headers });
}

async function openedHandler(c: Context<AppBindings>): Promise<Response> {
  const token = c.req.param('token') ?? '';
  if (!token) return goneOrNotFoundJson(c, 404, 'not_found', 'missing token');

  const limited = await consumeOpenedRateLimit(c, token);
  if (limited) return limited;

  const db = createDb(c.env.DATABASE_URL);
  const resolved = await resolveOpenTarget(c, db, token);
  if (resolved.status === 'not_found') {
    return goneOrNotFoundJson(c, 404, 'not_found', 'unknown token');
  }
  if (resolved.status === 'gone') {
    return goneOrNotFoundJson(c, 410, 'gone', resolved.reason);
  }
  if (resolved.status === 'pending') {
    return goneOrNotFoundJson(c, 404, 'not_found', 'upload in progress');
  }
  if (resolved.status === 'password') {
    return problem(
      c,
      501,
      'not_implemented',
      'Not Implemented',
      'password-protected share links are post-MVP',
    );
  }

  // Unfurlers and automated clients can still POST. That is not an open.
  if (shouldIgnoreOpenBeacon(c.req.header('user-agent'))) return noContent();

  const visitor = await readVisitorId(c);
  if (!visitor) {
    return problem(c, 400, 'invalid_visitor', 'Bad Request', 'visitor id is required');
  }

  const target = resolved.target;
  if (!target.link.notifyOnOpen || !target.ownerDeviceId) return noContent();

  const claimed = await claimOpenVisitor(c, token, visitor);
  if (!claimed) return noContent();

  c.executionCtx.waitUntil(
    sendLinkOpenedNotification({
      env: c.env,
      db,
      deviceId: target.ownerDeviceId,
      token,
      filename: target.filename,
      shortUrl: target.shortUrl,
    }).catch((err) => {
      log.warn({
        msg: 'open_alert_failed',
        requestId: c.get('requestId'),
        token,
        error: err instanceof Error ? err.message : String(err),
      });
    }),
  );
  return noContent();
}

interface OpenTarget {
  link: ShareLink;
  ownerDeviceId: string | null;
  filename: string;
  shortUrl: string;
}

async function resolveOpenTarget(
  c: Context<AppBindings>,
  db: Db,
  token: string,
): Promise<
  | { status: 'ok'; target: OpenTarget }
  | { status: 'not_found' }
  | { status: 'gone'; reason: 'expired' | 'revoked' | 'deleted' }
  | { status: 'pending' }
  | { status: 'password' }
> {
  const peek = await findByToken(db, token);
  if (!peek) return { status: 'not_found' };

  if (peek.isBundle) {
    const loaded = await loadActiveBundle(c, db, token);
    if ('status' in loaded) {
      if (loaded.status === 'not_found') return { status: 'not_found' };
      if (loaded.status === 'pending') return { status: 'pending' };
      return { status: 'gone', reason: loaded.reason };
    }
    if (loaded.link.visibility === 'password') return { status: 'password' };
    const first = loaded.assets[0]?.asset;
    const filename =
      loaded.assets.length === 1
        ? (first?.originalFilename ?? 'download')
        : `${loaded.assets.length} files`;
    return {
      status: 'ok',
      target: {
        link: loaded.link,
        ownerDeviceId: first?.ownerDeviceId ?? null,
        filename,
        shortUrl: `${c.env.SHORT_LINK_HOST}/b/${token}`,
      },
    };
  }

  const loaded = await loadActiveLinkAndAsset(c, db, token);
  if (loaded.status === 'not_found') return { status: 'not_found' };
  if (loaded.status === 'gone') return { status: 'gone', reason: loaded.reason };
  if (loaded.status === 'pending') return { status: 'pending' };
  if (loaded.link.visibility === 'password') return { status: 'password' };
  return {
    status: 'ok',
    target: {
      link: loaded.link,
      ownerDeviceId: loaded.assetRow.ownerDeviceId,
      filename: loaded.assetRow.originalFilename ?? 'download',
      shortUrl: `${c.env.SHORT_LINK_HOST}/s/${token}`,
    },
  };
}

async function readVisitorId(c: Context<AppBindings>): Promise<string | null> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return null;
  }
  if (!body || typeof body !== 'object') return null;
  const visitor = (body as { visitor?: unknown }).visitor;
  if (typeof visitor !== 'string' || !VISITOR_ID_PATTERN.test(visitor)) return null;
  return visitor;
}

async function consumeOpenedRateLimit(
  c: Context<AppBindings>,
  token: string,
): Promise<Response | null> {
  const ip = c.req.header('cf-connecting-ip') ?? 'unknown';
  const now = Math.floor(Date.now() / 1000);
  const windowStart = now - (now % OPENED_RATE_WINDOW_SECONDS);
  const identity = (
    await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, `${ip}:${token}`)
  ).slice(0, 32);
  const key = `rl:open:${identity}:${windowStart}`;
  const ttl = OPENED_RATE_WINDOW_SECONDS + 60;
  const existing = await c.env.RATE_LIMIT.get(key);
  const current = existing ? Number(existing) : 0;
  if (!Number.isFinite(current)) {
    await c.env.RATE_LIMIT.put(key, '1', { expirationTtl: ttl });
    return null;
  }
  if (current >= OPENED_RATE_LIMIT) {
    const retryAfter = windowStart + OPENED_RATE_WINDOW_SECONDS - now;
    const res = problem(
      c,
      429,
      'rate_limited',
      'Too Many Requests',
      `Limit of ${OPENED_RATE_LIMIT} per ${OPENED_RATE_WINDOW_SECONDS}s exceeded for bucket 'opened_ip_token'`,
    );
    res.headers.set('Retry-After', String(Math.max(retryAfter, 1)));
    applySecurityHeaders(res.headers);
    return res;
  }
  await c.env.RATE_LIMIT.put(key, String(current + 1), { expirationTtl: ttl });
  return null;
}

async function claimOpenVisitor(
  c: Context<AppBindings>,
  token: string,
  visitor: string,
): Promise<boolean> {
  const tokenKey = (await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, token)).slice(0, 32);
  const visitorKey = (await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, visitor)).slice(0, 32);
  const key = `open:${tokenKey}:${visitorKey}`;
  const existing = await c.env.RATE_LIMIT.get(key);
  if (existing) return false;
  await c.env.RATE_LIMIT.put(key, '1', { expirationTtl: OPENED_VISITOR_TTL_SECONDS });
  return true;
}

// ---------------------------------------------------------------------------
// Bundle path: /b/:token (preview HTML) + /b/:token/d/:assetId (per-asset
// download). Mounted at /b in the worker root. Mirrors the rate-limit
// posture of /s — IP bucket + per-token bucket — so a hot bundle can't
// drown out everyone else.
// ---------------------------------------------------------------------------

bundleRedirectRoutes.use(
  '*',
  ratelimit({ bucket: 'redirect_ip', limit: 60, windowSeconds: 60, keyFrom: 'ip' }),
);
bundleRedirectRoutes.use(
  '*',
  tokenRateLimit({ bucket: 'redirect_token', limit: 300, windowSeconds: 60 }),
);

bundleRedirectRoutes.get('/:token', (c) => bundlePreviewHandler(c));
bundleRedirectRoutes.get('/:token/p/:assetId', (c) => bundleAssetPreviewHandler(c));
bundleRedirectRoutes.get('/:token/d/:assetId', (c) => bundleAssetDownloadHandler(c));

interface LoadedBundle {
  link: ShareLink;
  assets: Array<{ asset: Asset; displayOrder: number }>;
}

async function loadActiveBundle(
  c: Context<AppBindings>,
  db: Db,
  token: string,
): Promise<
  | LoadedBundle
  | { status: 'not_found' }
  | { status: 'gone'; reason: 'expired' | 'revoked' | 'deleted' }
  | { status: 'pending'; link: ShareLink }
> {
  const link = await findByToken(db, token);
  if (!link || !link.isBundle) return { status: 'not_found' };
  if (link.linkStatus === 'revoked') return { status: 'gone', reason: 'revoked' };
  if (link.expiresAt.getTime() <= Date.now()) {
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
  if (link.linkStatus === 'pending') return { status: 'pending', link };
  // Two queries (junction + assets) instead of a JOIN — keeps the route
  // simple and lets the test fake stay dumb. Assets in displayOrder.
  const junctions = await db
    .select()
    .from(bundleAsset)
    .where(eq(bundleAsset.shareLinkId, link.id))
    .orderBy(bundleAsset.displayOrder);
  const collected: Array<{ asset: Asset; displayOrder: number }> = [];
  for (const j of junctions) {
    const [a] = await db.select().from(asset).where(eq(asset.id, j.assetId)).limit(1);
    if (!a) continue;
    if (a.deletedAt !== null || a.status === 'deleted') continue;
    collected.push({ asset: a, displayOrder: j.displayOrder });
  }
  collected.sort((x, y) => x.displayOrder - y.displayOrder);
  if (collected.length === 0) return { status: 'gone', reason: 'deleted' };
  return { link, assets: collected };
}

async function bundlePreviewHandler(c: Context<AppBindings>): Promise<Response> {
  const token = c.req.param('token') ?? '';
  if (!token) return goneOrNotFoundHtml(c, 404, 'not_found', 'missing token');
  const db = createDb(c.env.DATABASE_URL);
  const loaded = await loadActiveBundle(c, db, token);
  if ('status' in loaded) {
    if (loaded.status === 'not_found')
      return goneOrNotFoundHtml(c, 404, 'not_found', 'unknown bundle');
    if (loaded.status === 'pending') {
      return renderPendingPage({
        filename: 'Bundle upload',
        sizeBytes: 0,
        expiresAt: loaded.link.expiresAt,
        canonicalUrl: `${c.env.SHORT_LINK_HOST}/b/${token}`,
        disableProbe: true,
      });
    }
    return goneOrNotFoundHtml(c, 410, 'gone', loaded.reason);
  }

  scheduleAccessCount(c, db, token);

  return renderBundlePreviewPage({
    token,
    expiresAt: loaded.link.expiresAt,
    canonicalUrl: `${c.env.SHORT_LINK_HOST}/b/${token}`,
    ogImageUrl: `${c.env.SHORT_LINK_HOST}/og-image.png`,
    openedUrl: `${c.env.SHORT_LINK_HOST}/s/${token}/opened`,
    items: loaded.assets.map((row) => ({
      assetId: row.asset.id,
      filename: row.asset.originalFilename ?? 'download',
      sizeBytes: row.asset.sizeBytes,
      contentType: row.asset.contentType,
      previewUrl: `${c.env.SHORT_LINK_HOST}/b/${token}/p/${row.asset.id}`,
      downloadUrl: `${c.env.SHORT_LINK_HOST}/b/${token}/d/${row.asset.id}`,
    })),
  });
}

async function bundleAssetPreviewHandler(c: Context<AppBindings>): Promise<Response> {
  const token = c.req.param('token') ?? '';
  const assetId = c.req.param('assetId') ?? '';
  if (!token || !assetId) return goneOrNotFoundJson(c, 404, 'not_found', 'missing token or asset');
  const db = createDb(c.env.DATABASE_URL);

  const link = await findByToken(db, token);
  if (!link || !link.isBundle) return goneOrNotFoundJson(c, 404, 'not_found', 'unknown bundle');
  if (link.linkStatus === 'revoked') return goneOrNotFoundJson(c, 410, 'gone', 'revoked');
  if (link.linkStatus === 'pending')
    return goneOrNotFoundJson(c, 404, 'not_found', 'bundle still uploading');
  if (link.expiresAt.getTime() <= Date.now()) {
    return goneOrNotFoundJson(c, 410, 'gone', 'expired');
  }

  const junctionRows = await db
    .select()
    .from(bundleAsset)
    .where(and(eq(bundleAsset.shareLinkId, link.id), eq(bundleAsset.assetId, assetId)))
    .limit(1);
  if (junctionRows.length === 0) {
    return goneOrNotFoundJson(c, 404, 'not_found', 'asset not in bundle');
  }

  const [a] = await db.select().from(asset).where(eq(asset.id, assetId)).limit(1);
  if (!a || a.deletedAt !== null || a.status === 'deleted') {
    return goneOrNotFoundJson(c, 410, 'gone', 'deleted');
  }

  return streamAssetBytes(c, a, 'inline');
}

async function bundleAssetDownloadHandler(c: Context<AppBindings>): Promise<Response> {
  const token = c.req.param('token') ?? '';
  const assetId = c.req.param('assetId') ?? '';
  if (!token || !assetId) return goneOrNotFoundJson(c, 404, 'not_found', 'missing token or asset');
  const db = createDb(c.env.DATABASE_URL);

  const link = await findByToken(db, token);
  if (!link || !link.isBundle) return goneOrNotFoundJson(c, 404, 'not_found', 'unknown bundle');
  if (link.linkStatus === 'revoked') return goneOrNotFoundJson(c, 410, 'gone', 'revoked');
  if (link.linkStatus === 'pending')
    return goneOrNotFoundJson(c, 404, 'not_found', 'bundle still uploading');
  if (link.expiresAt.getTime() <= Date.now()) {
    return goneOrNotFoundJson(c, 410, 'gone', 'expired');
  }

  // Authorize: the asset must belong to this bundle. Without this check, any
  // asset_id leak would let a caller pivot from one share's token to bytes of
  // another share owned by the same device.
  const junctionRows = await db
    .select()
    .from(bundleAsset)
    .where(and(eq(bundleAsset.shareLinkId, link.id), eq(bundleAsset.assetId, assetId)))
    .limit(1);
  if (junctionRows.length === 0) {
    return goneOrNotFoundJson(c, 404, 'not_found', 'asset not in bundle');
  }

  const [a] = await db.select().from(asset).where(eq(asset.id, assetId)).limit(1);
  if (!a || a.deletedAt !== null || a.status === 'deleted') {
    return goneOrNotFoundJson(c, 410, 'gone', 'deleted');
  }

  const onLeadingHit = (offset: number) => {
    if (offset !== 0) return;
    scheduleAccessCount(c, db, token);
  };
  return streamAssetBytes(c, a, 'attachment', onLeadingHit);
}
