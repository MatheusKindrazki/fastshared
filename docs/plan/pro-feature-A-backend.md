# FastShared Pro — Backend Slice (Plan A)

> **For Agents:** REQUIRED SUB-SKILL: Use `ring-default:executing-plans` to work through this file task-by-task. This plan covers ONLY the backend. Apple client (Plan B) and launch prep (Plan C) are separate plans — do **NOT** touch Xcode project, StoreKit files, or `web/` from this plan.

**Goal:** Replace the 302-to-signed-R2 redirect with a Hono worker proxy serving an HTML preview page + streaming downloads with Range, and ship the backend half of Pro: subscriptions schema, Apple IAP verify + webhook, App Store Server API client, Free-tier middleware, and `/v1/me`.

**Architecture:** Everything lives in the existing Hono-on-Workers app (`backend/src/index.ts`). New modules: routes `iap.ts` + `me.ts`, service `subscriptions.ts`, lib `appStoreServerApi.ts`, middleware `rateLimitFreeTier.ts`; rewrite `routes/redirect.ts` into an HTML-or-stream proxy; add `0002_subscriptions.sql`. R2 bodies pipe through — never buffered — via `env.R2.get(key, { range })`.

**Tech Stack:** Hono 4.x, Drizzle ORM 0.36 + Neon HTTP driver, Cloudflare Workers (R2 + KV bindings), Zod, Vitest with `@cloudflare/vitest-pool-workers`, `jose` (new dep) for JWS verification.

**Global Prerequisites:**
- Node 20+, npm 10+, `wrangler` 3.80+
- `backend/.env` with a Neon URL you can migrate against
- Existing Wrangler secrets: `DATABASE_URL`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `DEVICE_TOKEN_PEPPER`
- New secrets (added in Part 4): `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_P8_KEY_BASE64`, `APPLE_BUNDLE_ID`
- Clean working tree on `main`

**Verification before starting:**
```bash
cd backend
node --version && npm --version && npx wrangler --version
git status              # Expected: clean
npm run typecheck       # Expected: exits 0
npm test -- --run       # Expected: existing suites pass (uploads, wellKnown)
```

**Codebase conventions (respect, do not re-decide):**
- Routes mount from `backend/src/index.ts` via `app.route(...)`. All errors flow through `lib/problem.ts` (`application/problem+json`). Auth middleware is `middleware/auth.ts`.
- KV rate limits use binding `RATE_LIMIT`, keys `rl:<identity>:<bucket>:<window>`. Free-tier uses a new namespace `ft:<deviceId>:<utcDate>`.
- `SHORT_LINK_HOST` = `https://fastsha.red` in prod; the preview page is served here at `/s/:token`.
- Neon HTTP driver — `createDb(env.DATABASE_URL)` per request.
- Tests use `@cloudflare/vitest-pool-workers` with the in-memory drizzle fake in `test/uploads.test.ts` (copy the pattern; do not reinvent).
- Conventional commits (`feat(backend): …`). One commit per task.

**Out of scope:** Apple StoreKit client, PaywallView, CloudKit (Plan B); landing copy, pricing page, ASC metadata (Plan C); upload compression (rejected); referral codes, team plans, custom domains, password-protected links (v1 non-goals); inline media preview; CDN-caching the preview page.

**Task IDs:** `A<part>.<task>`. Parts 1–6 implementation, 7 tests, 8 wire-up. `[parallel: …]` / `[depends: …]` mark ordering. Every task has a verification command and 1–3 acceptance bullets.

---

## Part 1 — Worker proxy for short links

Rewrites `backend/src/routes/redirect.ts`. Keep the file path (it's mounted at `/s` from `index.ts`). Preserve the `redirect_ip` / `redirect_token` KV limiters — they apply to both HTML and binary paths.

**URL shape after Part 1:**
- `GET /s/:token` + `Accept: text/html*` → 200 HTML preview
- `GET /s/:token` non-HTML, OR `GET /s/:token?dl=1`, OR `GET /s/:token/download` → binary stream
- `HEAD /s/:token` → binary headers only (resumable-download clients probe with HEAD)
- Expired / revoked → 410 (styled HTML on HTML Accept, `application/problem+json` otherwise)
- Unknown token → 404 (same content negotiation)

### A1.1 — Create HTML preview renderer module

**Files:** Create `backend/src/lib/previewPage.ts`.

**Intent:** Pure function `renderPreviewPage({ filename, sizeBytes, contentType, expiresAt, downloadUrl, requestNow })` returning a `Response` with an HTML body. Inline BrandPalette hex literals in one `<style>` block (hardcode `#12161d` ink, `#f5f8fb` nightshade, `#00a69c` amber, `#4ecf8f` ember, `#f0525f` coral, `#667085` dust, `#d7e1e8` line, `#fbfcff` paper; comment cites `apple/Packages/FastSharedCore/.../BrandPalette.swift` as source of truth). Renders: OG meta tags (`og:title` = filename, `og:description` = `"Shared via FastShared — expires in Xh Ym"`, `og:image` = `${SHORT_LINK_HOST}/og-image.png`, `og:type=website`, canonical `og:url`; Twitter summary_large_image variants); `<title>` = filename; header with filename + human size (`formatBytes` helper in same file) + MIME badge; server-rendered countdown block with a `data-expires-at` attribute and one inlined `<script>` that `setInterval`-ticks 1s via `Date.now()` diff; download `<a>` with `download` attribute; stub hidden `<!-- password-entry form for future release -->` comment (no UI); footer wordmark. Response headers: `Content-Type: text/html; charset=utf-8`, `Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: private, no-store`, `X-Robots-Tag: noindex, nofollow`. Also export `renderGonePage(reason: 'expired' | 'revoked' | 'deleted')` → 410 with the same palette, and `formatBytes`.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Exports `renderPreviewPage`, `renderGonePage`, `formatBytes` as named.
- No `hono` import — pure string construction returning `Response` with `Headers`.
- HTML-escapes filename + reason with a local `escapeHtml` helper (copy from current `redirect.ts`).

---

### A1.2 — Add R2 streaming helper

**Files:** Modify `backend/src/services/r2.ts` (append only).

**Intent:** New export `getObjectStream(env, key, range?)` that calls `env.R2.get(key, range ? { range } : undefined)` via the **R2 binding** (not the S3 SDK — direct binding avoids presign and yields `R2ObjectBody.body` as a `ReadableStream`). Returns `{ body, size, etag, httpMetadata, range } | null`. `range` arg mirrors the R2 binding shape: `{ offset: number, length?: number } | { suffix: number }`. Header parsing is the caller's job (A1.3).

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- New export `getObjectStream`; existing exports unchanged.
- Uses `env.R2`, not `S3Client`. S3 SDK remains for presign/head/list.

---

### A1.3 — Add Range header parser

**Files:** Create `backend/src/lib/httpRange.ts`.

**Intent:** Pure function `parseRangeHeader(header: string | null, totalSize: number)` → `{ kind: 'none' } | { kind: 'range', offset, length } | { kind: 'suffix', suffix } | { kind: 'unsatisfiable' }`. Single-range only (`bytes=0-499`, `bytes=500-`, `bytes=-500`); multi-range → `none` (RFC 7233 allows ignoring). `unsatisfiable` when `offset >= totalSize`. Caller maps `unsatisfiable` → 416 with `Content-Range: bytes */<size>`.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Pure function — no `hono`/`env` imports.
- Handles the three canonical forms + malformed input (returns `none`, never throws).

---

### A1.4 — Add RFC 5987 filename encoder

**Files:** Create `backend/src/lib/contentDisposition.ts`.

**Intent:** Export `contentDispositionAttachment(filename: string): string` returning `attachment; filename="<ascii-fallback>"; filename*=UTF-8''<percent-encoded>` (RFC 6266 §5 two-form). Percent-encode per RFC 5987 — `encodeURIComponent` + also escape `*'%`. Under 40 LOC.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Value passes `new Headers({ 'content-disposition': value })` without error.
- `relatório.pdf` → `...filename*=UTF-8''relat%C3%B3rio.pdf`.

---

### A1.5 — Rewrite redirect route into proxy + preview

**Files:** Modify `backend/src/routes/redirect.ts` (rewrite in place — keep filename so `app.route('/s', redirectRoutes)` still works).

**Intent:** Keep the two rate-limit middlewares. Delete the `presignGet`-and-302 handler. Register three handlers: `GET /:token/download` → `binaryHandler`, `GET /:token` → `dispatchHandler`, `HEAD /:token` → `binaryHandler`. Extract a private `loadActiveLinkAndAsset(db, token)` to share lookup logic.

`dispatchHandler`: loads link + asset. Revoked/expired/deleted → `renderGonePage(reason)` on `Accept: text/html`, else `problem(c, 410, 'gone', reason)`. Unknown token → 404 (same content negotiation). Live link: if `?dl=1` or Accept does NOT include `text/html`, delegate to `binaryHandler`; otherwise compute `msUntilExpiry`, fire-and-forget `incrementAccess` via `waitUntil`, return `renderPreviewPage({ filename: a.originalFilename ?? 'download', ..., downloadUrl: \`${env.SHORT_LINK_HOST}/s/${token}/download\` })`. Password visibility keeps its 501 stub.

`binaryHandler`: same lookup + gone-handling, but responses are `text/plain` (non-HTML). Parse `Range` via `parseRangeHeader(c.req.header('range') ?? null, a.sizeBytes)`; `unsatisfiable` → 416 with `Content-Range: bytes */<size>`. `getObjectStream(c.env, a.storageKey, rangeForBinding)` where `rangeForBinding` is derived from parser output. R2 miss (shouldn't happen unless the row/object drift briefly) → 410. On hit, headers: `Content-Type: a.contentType`, `Content-Disposition: contentDispositionAttachment(a.originalFilename ?? 'download')`, `Cache-Control: private, no-store`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Robots-Tag: noindex, nofollow`, `Accept-Ranges: bytes`. Ranged: 206 + `Content-Range` + correct `Content-Length`. Full: 200 + `Content-Length: a.sizeBytes`. Return `new Response(body, { status, headers })` — **pipe, do not buffer**. Gate `incrementAccess` to `offset === 0` so video-tag range probes don't N-multiply the counter.

**Verification:**
```bash
cd backend && npm run typecheck
cd backend && npm run dev &  # then in another shell:
curl -sI -H "Accept: text/html" http://127.0.0.1:8787/s/<seeded-token> | head -5
# Expected: 200 with Content-Type: text/html (or 404 if nothing seeded — fine)
```

**Acceptance:**
- `rg -n "presignGet\(" backend/src/routes/redirect.ts` → zero matches.
- Three handlers registered (`GET /:token/download`, `GET /:token`, `HEAD /:token`).
- `Accept: text/html` → 200 HTML containing `<meta property="og:title"`.
- `Accept: */*` → binary stream with `Accept-Ranges: bytes`.

---

### A1.6 — Audit upload/history responses for signed-URL leakage

**Files:** Modify `backend/src/routes/uploads.ts` and `backend/src/routes/history.ts`.

**Intent:** The current `completeResponse` already returns `shortUrl: \`${shortLinkHost}/s/${link.token}\`` — correct. Sweep for any `signedUrl` / `downloadUrl` / direct `presignGet` result leaking to a client. `presignPut` (upload-side PUT target) stays. Only the canonical `fastsha.red/s/:token` may represent a download.

**Verification:**
```bash
cd backend && rg -n "signedUrl|signed_url|downloadUrl" src/routes src/services
# Expected: no matches in route handlers (r2.ts internals OK)
cd backend && npm run typecheck
```

**Acceptance:**
- No route returns an R2 signed URL to the client.
- `/v1/uploads/:id/complete` still carries `shortUrl`.
- `/v1/history` returns the same canonical shape.

---

### A1.7 — Add `/og-image.png` static passthrough

**Files:** Create `backend/src/routes/assetsPublic.ts`; modify `backend/src/index.ts` to add `/og-image.png` to `APP_PATH_PREFIXES` and `app.route('/', assetsPublicRoutes)`.

**Intent:** The preview page's `og:image` → `${SHORT_LINK_HOST}/og-image.png`. The apex currently proxies non-app paths to Pages; we want the Worker to serve this directly with `caches.default` so Slack/iMessage/Discord social-card unfurls don't pay a Pages round-trip. Fetch from `PAGES_ORIGIN` once, cache with TTL 86400s. Plan C ships the actual PNG at the Pages origin; this task only wires the passthrough.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- `GET /og-image.png` → 200 + `Content-Type: image/png`.
- Second request served from `caches.default` (`CF-Cache-Status: HIT` in preview env).
- `Cache-Control: public, max-age=86400, immutable`.

---

### A1.8 — `/ring-default:codereview` checkpoint for Part 1

REQUIRED SUB-SKILL: `ring-default:requesting-code-review` on the Part 1 diff (`git diff main..HEAD -- backend/src/routes/redirect.ts backend/src/lib/previewPage.ts backend/src/lib/httpRange.ts backend/src/lib/contentDisposition.ts backend/src/services/r2.ts backend/src/routes/uploads.ts backend/src/routes/assetsPublic.ts`). Fix Critical/High/Medium; `TODO(review):` for Low, `FIXME(nitpick):` for Cosmetic. Reviewers specifically check: HTML escaping in `renderPreviewPage`; the range handler does not buffer the R2 body; no `await` on the body promise before returning; `Cache-Control: private, no-store` on every `/s/*` response; `incrementAccess` only fires on full-content or first-chunk requests.

---

## Part 2 — Subscriptions schema + migration

### A2.1 — Add Drizzle `subscription` table

**Files:** Modify `backend/src/db/schema.ts` (append only).

**Intent:** Append the `subscription` table following the `deletionJob` pattern (SQL CHECK constraints live in the migration; TS literal-union arrays `SUBSCRIPTION_TIERS` / `SUBSCRIPTION_STATUSES` are exported from here). Extend the `drizzle-orm/pg-core` import line to add `boolean`, `jsonb`. Add `Subscription` / `NewSubscription` inferred types to the bottom block. Exact schema shape:

```ts
export const SUBSCRIPTION_TIERS = ['monthly', 'annual', 'lifetime'] as const;
export type SubscriptionTier = (typeof SUBSCRIPTION_TIERS)[number];

export const SUBSCRIPTION_STATUSES = [
  'active', 'expired', 'in_grace', 'in_billing_retry', 'revoked', 'refunded',
] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

export const subscription = pgTable('subscription', {
  id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
  deviceId: uuid('device_id').notNull().references(() => device.id),
  appleOriginalTransactionId: text('apple_original_transaction_id').notNull().unique(),
  tier: text('tier').notNull(),                         // CHECK in SQL
  status: text('status').notNull(),                     // CHECK in SQL
  expiresAt: timestamp('expires_at', { withTimezone: true }), // NULL for lifetime
  autoRenewStatus: boolean('auto_renew_status').notNull().default(true),
  latestTransactionId: text('latest_transaction_id').notNull(),
  rawNotificationPayload: jsonb('raw_notification_payload'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  deviceIdx: index('subscription_device_idx').on(t.deviceId),
  activeDeviceIdx: uniqueIndex('subscription_active_per_device').on(t.deviceId),
  // Partial predicate `WHERE status = 'active'` lives in the SQL migration.
}));
```

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- New exports: `subscription`, `Subscription`, `NewSubscription`, `SUBSCRIPTION_TIERS`, `SUBSCRIPTION_STATUSES`.
- No existing export removed or renamed.

---

### A2.2 — Write SQL migration `0002_subscriptions.sql`

**Files:** Create `backend/drizzle/0002_subscriptions.sql`.

**Intent:** Wrap in `BEGIN; … COMMIT;` like `0001_ephemeral.sql`. Create `subscription` with CHECK constraints on `tier` and `status`, `device_id` FK `ON DELETE RESTRICT`, unique index on `apple_original_transaction_id`, non-unique index on `device_id`, and a **partial** unique index on `(device_id) WHERE status = 'active'` (at most one active subscription per device — history rows remain, only one is active). No trigger; callers update `updated_at` via `sql\`now()\``. Leading comment documents the Apple invariant: `apple_original_transaction_id` is stable across renewals, `latest_transaction_id` moves.

**Verification:**
```bash
cd backend && head -5 drizzle/0002_subscriptions.sql  # begins with comment + BEGIN;
cd backend && DATABASE_URL=<throwaway-neon-url> npm run db:migrate
```

**Acceptance:**
- Migration runs clean on an empty DB after 0000 + 0001.
- `\d subscription` shows the partial unique index `WHERE status = 'active'`.
- `DROP TABLE subscription;` leaves no orphan indexes.

---

### A2.3 — Subscription service (CRUD helpers)

**Files:** Create `backend/src/services/subscriptions.ts`.

**Intent:** Thin service layer. Exports:
- `findActiveByDeviceId(db, deviceId): Promise<Subscription | null>` — `WHERE device_id = $1 AND status = 'active' LIMIT 1`.
- `findByOriginalTransactionId(db, originalTransactionId): Promise<Subscription | null>`.
- `upsertFromAppleEvent(db, { deviceId, originalTransactionId, tier, status, expiresAt, autoRenewStatus, latestTransactionId, rawNotificationPayload })` — `onConflictDoUpdate` keyed on `apple_original_transaction_id`; sets `updated_at = now()`. When flipping a new row to `active`, first expire any OTHER active row for the same device (wrap in `db.transaction` if Neon HTTP supports it; otherwise sequential + retry-once on `23505` from the partial unique index).
- `deriveTierFromProductId(productId): SubscriptionTier` — constants `PRODUCT_ID_MONTHLY = 'red.fastsha.pro.monthly'`, `PRODUCT_ID_ANNUAL = 'red.fastsha.pro.annual'`, `PRODUCT_ID_LIFETIME = 'red.fastsha.pro.lifetime'`. Unknown → throw (caller 422s).
- `deriveStatusFromNotificationType(type, subtype?): SubscriptionStatus` — pure map shared by verify + webhook: `DID_RENEW→active`, `EXPIRED→expired`, `REFUND→refunded`, `REVOKE→revoked`, `GRACE_PERIOD_EXPIRED→expired`, `DID_CHANGE_RENEWAL_STATUS→unchanged (caller only flips autoRenewStatus)`, `DID_FAIL_TO_RENEW+subtype=GRACE_PERIOD→in_grace`, `DID_FAIL_TO_RENEW+no subtype→in_billing_retry`.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Four helpers exported with the signatures above.
- `deriveTierFromProductId` and `deriveStatusFromNotificationType` are pure (no `db`/`env`/I/O).

---

### A2.4 — `/ring-default:codereview` checkpoint for Part 2

REQUIRED SUB-SKILL: `ring-default:requesting-code-review` on `backend/src/db/schema.ts`, `backend/drizzle/0002_subscriptions.sql`, `backend/src/services/subscriptions.ts`. Reviewers check: partial unique index correctness; status/tier enum coverage vs the canonical Apple notification list; race window on `flip-other-active → insert-new-active`.

---

## Part 3 — IAP endpoints

Mount at `/v1/iap` in Part 8. Route + client work proceed in lockstep but stay separate tasks for reviewability.

### A3.1 — IAP route module scaffold

**Files:** Create `backend/src/routes/iap.ts`.

**Intent:** Export `iapRoutes = new Hono<AppBindings>()`. Two handlers, both 501 stubs for now:
- `POST /verify` — route-level `auth()` (NOT global — the webhook must stay unauthenticated), then `ratelimit({ bucket: 'iap_verify', limit: 20, windowSeconds: 600 })`.
- `POST /webhook` — no auth, `ratelimit({ bucket: 'iap_webhook_ip', limit: 1000, windowSeconds: 60, keyFrom: 'ip' })` (generous for Apple bursts, caps leaked-URL abuse).

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Two handlers registered, both 501 via `problem(...)`.
- Middleware applied per-route, not globally.

---

### A3.2 — `POST /v1/iap/verify` [depends: A4.1, A4.2]

**Files:** Modify `backend/src/routes/iap.ts`.

**Intent:** Zod body `{ jwsRepresentation: z.string().min(20) }`. Pipeline:
1. `verifyTransactionJWS(jws)` → `{ productId, originalTransactionId, transactionId, expiresDate, environment }`; on throw → `422 invalid_receipt`.
2. `getSubscriptionStatus(originalTransactionId)` → authoritative. Map Apple `status` int (`0=active, 1=expired, 2=in_billing_retry, 3=in_grace, 4=revoked`) + `autoRenewStatus`.
3. `deriveTierFromProductId(productId)` — unknown → 422 `unknown_product`.
4. `upsertFromAppleEvent(db, { deviceId: c.get('deviceId')!, originalTransactionId, tier, status, expiresAt, autoRenewStatus, latestTransactionId: transactionId, rawNotificationPayload: { source: 'verify', apple: statusResponse } })`.
5. Return `{ tier, status, expiresAt: expiresAt?.toISOString() ?? null, autoRenewStatus }`.

Sandbox-in-prod guard: if `environment !== 'Production' && env.APP_ENV === 'production'` → 422 (sandbox receipts never unlock Pro in prod).

**Verification:** `cd backend && npm run typecheck` (integration test in A7.2).

**Acceptance:**
- No bearer → 401.
- Valid mocked JWS → 200 `{ tier, status, expiresAt }` + single upserted row.

---

### A3.3 — `POST /v1/iap/webhook` [depends: A4.3]

**Files:** Modify `backend/src/routes/iap.ts`.

**Intent:** Apple posts `{ signedPayload: string }` (App Store Server Notifications v2). Envelope shape:
```
{ notificationType, subtype?, notificationUUID, signedDate, version: '2.0',
  data: { bundleId, environment, signedTransactionInfo, signedRenewalInfo, status?, appAppleId } }
```

Pipeline (in this exact order — security-sensitive):
1. **First:** `verifyNotificationJWS(signedPayload)` — verify the JWS against Apple's root. Bad signature → 401 (tells Apple to stop retrying; don't 5xx — they'd retry).
2. Check KV `iap:notif:<notificationUUID>`. Hit → 200 `{ ok: true }` no-op (log `iap_notif_duplicate`). Miss → `put(key, '1', { expirationTtl: 604800 })` AFTER step 9.
3. Guard `bundleId === env.APPLE_BUNDLE_ID` → else 200 no-op + log.
4. Guard environment vs `env.APP_ENV` — sandbox-in-prod → 200 no-op + log.
5. `verifyTransactionJWS(signedTransactionInfo)` → `{ originalTransactionId, productId, transactionId, expiresDate }`.
6. Decode `signedRenewalInfo` (same verifier) → `autoRenewStatus`, `autoRenewProductId`, `expirationIntent`.
7. `findByOriginalTransactionId(db, originalTransactionId)`. No row → log orphan (no associated device yet — `/verify` hasn't landed) and return 200. We only touch rows we can tie back to a device via prior `/verify`.
8. Compute new status. For `DID_CHANGE_RENEWAL_STATUS`: keep prior status, only flip `autoRenewStatus`. Otherwise: `deriveStatusFromNotificationType(notificationType, subtype)` + `deriveTierFromProductId(productId)`.
9. `upsertFromAppleEvent(...)` with `rawNotificationPayload: { source: 'webhook', notificationUUID, notificationType, subtype, decoded: { transaction, renewal } }`, then `KV.put` idempotency key.
10. Return 200 `{ ok: true }`.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Endpoint is unauthenticated (no `auth()`).
- Valid JWS + orphan → 200 + log (no DB write).
- Bad JWS → 401.
- Replay same `notificationUUID` within 7d → 200, no DB write.

---

### A3.4 — `/ring-default:codereview` checkpoint for Part 3

REQUIRED SUB-SKILL: `ring-default:requesting-code-review` on `backend/src/routes/iap.ts`. Reviewers check: webhook is unauthenticated; JWS verification happens BEFORE envelope parse; sandbox-in-prod guard is active; `notificationUUID` idempotency is checked BEFORE the DB write.

---

## Part 4 — App Store Server API client

### A4.1 — Module scaffold + JWT builder + env wiring

**Files:**
- Create: `backend/src/lib/appStoreServerApi.ts`
- Modify: `backend/src/env.ts` — add `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_P8_KEY_BASE64`, `APPLE_BUNDLE_ID` to `Env` and `envSchema` (`.min(1)`, `.min(20)` on the p8).
- Modify: `backend/wrangler.toml` — add `APPLE_BUNDLE_ID = "red.fastsha.FastShared"` to `[vars]` (public; the other three stay as Wrangler secrets).
- Modify: `backend/vitest.config.ts` — mock values for the four new vars so tests can build the client. p8 fixture: generate a self-signed ES256 keypair at test setup (`jose.generateKeyPair('ES256')` + export PKCS8 → base64).

**Intent:** Factory `createAppStoreServerApi(env: Env)` returns `{ verifyTransactionJWS, verifyNotificationJWS, getSubscriptionStatus }` — stubs here, implemented in A4.2/A4.3. Private `buildAuthJwt()`: base64-decode `env.APP_STORE_CONNECT_P8_KEY_BASE64`, `jose.importPKCS8`, sign ES256 JWT with claims `{ iss: env.APP_STORE_CONNECT_ISSUER_ID, iat, exp: iat + 1800, aud: 'appstoreconnect-v1', bid: env.APPLE_BUNDLE_ID }` and header `{ alg: 'ES256', kid: env.APP_STORE_CONNECT_KEY_ID, typ: 'JWT' }`. Cache in module-level `WeakMap<Env, { jwt, expiresAt }>` with 25-min TTL so we don't re-sign per request.

**Dependency:** `npm install jose` in `backend/` (add to `dependencies`).

**Verification:** `cd backend && npm install jose && npm run typecheck`

**Acceptance:**
- `jose` in `dependencies` (not `devDependencies`).
- `envSchema` rejects missing App Store secrets on `assertEnv`.
- `buildAuthJwt()` returns a string whose header and claims match spec (verified in A7 tests).

---

### A4.2 — Transaction JWS verifier [parallel: A4.3]

**Files:** Modify `backend/src/lib/appStoreServerApi.ts`.

**Intent:** Implement `verifyTransactionJWS(jws): Promise<DecodedTransaction>`. Apple's signed transactions carry an `x5c` header chained to `AppleRootCA-G3.cer`. Pipeline: `jose.decodeProtectedHeader` → extract `x5c` → verify chain terminates at Apple root (bundle the root cert as a TS template literal inside this module; cite Apple's URL in a comment) → `jose.importX509(leafPem)` → `jose.jwtVerify`. Return `DecodedTransaction = { transactionId, originalTransactionId, productId, purchaseDate: Date, expiresDate: Date | null, environment: 'Production' | 'Sandbox', bundleId }`. On any failure, throw `InvalidJwsError` (exported class) with a short reason code for logs.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Rejects a JWS not chaining to Apple root (A7.2).
- Structural decode succeeds even on old-but-valid JWS; route decides freshness policy.

---

### A4.3 — Notification JWS verifier + status fetch [parallel: A4.2]

**Files:** Modify `backend/src/lib/appStoreServerApi.ts`.

**Intent:** Two methods, sharing a private `verifyAppleSignedJws(jws)` helper:
1. `verifyNotificationJWS(signedPayload)` — same chain-verification as A4.2, returns the envelope shape from A3.3.
2. `getSubscriptionStatus(originalTransactionId)` → `GET https://api.storekit.itunes.apple.com/inApps/v1/subscriptions/${originalTransactionId}` (sandbox host `api.storekit-sandbox.itunes.apple.com` when `env.APP_ENV !== 'production'`). `Authorization: Bearer <buildAuthJwt()>`. Retry exponential backoff 250/500/1000ms on 5xx; honor `Retry-After` (seconds or HTTP-date) on 429; give up after 3 attempts → throw `AppStoreApiError`. Parse `{ data: [{ lastTransactions: [{ status, signedTransactionInfo, signedRenewalInfo }] }] }`, pick the entry matching the `originalTransactionId`, decode via `verifyTransactionJWS`, return `{ status, tier, expiresDate, autoRenewStatus, latestTransactionId, environment, raw }`.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- 3 retries on 500 then throws.
- Sandbox host when `APP_ENV=test`.
- Honors `Retry-After` on 429 (asserted in A7).

---

### A4.4 — `/ring-default:codereview` checkpoint for Part 4

REQUIRED SUB-SKILL: `ring-default:requesting-code-review` on `backend/src/lib/appStoreServerApi.ts` + env/wrangler/vitest diffs. Reviewers check: real cert-chain verification (no `no-verify` flags); p8 decoded exactly once per process; no log lines include the raw JWT or p8; sandbox-vs-prod host selection cannot be forced to sandbox in prod.

---

## Part 5 — Free-tier enforcement middleware

### A5.1 — Middleware module

**Files:** Create `backend/src/middleware/rateLimitFreeTier.ts`.

**Intent:** Export `rateLimitFreeTier(): MiddlewareHandler<AppBindings>`. Runs AFTER `auth()`. Order:
1. Require `c.get('deviceId')` else 401.
2. `const active = await findActiveByDeviceId(createDb(c.env.DATABASE_URL), deviceId)`.
3. If Pro (`active.expiresAt === null || active.expiresAt > now`) → `next()`, bypass all caps.
4. Free path: clone request body via `c.req.raw.clone()` before reading (Hono consumes body once; downstream Zod must still parse). Extract `sizeBytes`, `retentionPolicy`, `customTtlSeconds`. Invalid JSON → fall through (downstream handles).
5. **Size cap:** `sizeBytes > 100 * 1024 * 1024` → 402 with `{ code: 'free_tier_size_exceeded', limitMB: 100, actualMB, upgrade: { tier: 'pro', url: 'https://fastsha.red/pricing' } }`. Extend `problem.ts` to accept an `extras` arg that merges into the body; use the same `extras` shape for all three Free-tier 402s. Do NOT increment the KV counter.
6. **Retention clamp (silent):** if TTL > 24h, rewrite the request to `retentionPolicy: 'oneDay'` (strip `customTtlSeconds`). Set `c.set('freeTierClampedRetention', true)` so A5.2 can echo `{ retentionClamped: true, clampedTo: 'oneDay' }`.
7. **Daily count cap:** KV key `ft:${deviceId}:${utcDate()}` (`utcDate = new Date().toISOString().slice(0,10)`). Read-parse-put pattern from `middleware/ratelimit.ts`; `expirationTtl: 172800`. If counter >= 3 → 402 `{ code: 'free_tier_daily_exceeded', limit: 3, used: 3, resetsAt: <next UTC midnight ISO>, upgrade: {...} }`. Increment only after size cap passed.
8. `next()`.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Pro bypasses on the DB lookup alone.
- Size-cap 402 before KV counter changes.
- Retention clamp is silent (no 402).

---

### A5.2 — Mount the middleware on upload presign

**Files:** Modify `backend/src/routes/uploads.ts`.

**Intent:** Add `uploadRoutes.use('/', rateLimitFreeTier())` after `auth()` and the existing `ratelimit({ bucket: 'upload', ... })`. Scope to `POST /v1/uploads/` only — NOT `/complete` or `/fail`. Use path-specific `.use('/', …)` or an early return inside the middleware when `c.req.path !== '/v1/uploads/'`. If `c.get('freeTierClampedRetention')` is true after the handler runs, include `{ retentionClamped: true, clampedTo: 'oneDay' }` in the presign response payload.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Middleware only fires on `POST /v1/uploads/`.
- Pro unchanged.
- 4th Free upload in a UTC day → 402.

---

### A5.3 — `/ring-default:codereview` checkpoint for Part 5

REQUIRED SUB-SKILL: `ring-default:requesting-code-review` on the middleware + uploads.ts diff. Reviewers check: body clone-before-consume (downstream Zod still parses); KV increment race is documented; 402 envelope is consistent across all three breaches; retention clamp actually mutates the request the handler sees (not just a flag).

---

## Part 6 — `GET /v1/me`

### A6.1 — Route module + shared caps constants

**Files:**
- Create: `backend/src/lib/tierCaps.ts` — exports `FREE_CAPS` and `PRO_CAPS`. `rateLimitFreeTier` (A5.1) imports `FREE_CAPS` from here — one source of truth.
- Create: `backend/src/routes/me.ts`.

**Intent:** `meRoutes = new Hono<AppBindings>()` with route-level `auth()`. Single handler `GET /` returns:

```ts
interface MeResponse {
  tier: 'free' | 'monthly' | 'annual' | 'lifetime';
  expiresAt: string | null;          // ISO-8601 UTC
  caps: {
    uploadsPerDay: number;           // Free: 3, Pro: -1 (unlimited sentinel)
    maxFileSizeMB: number;           // Free: 100, Pro: 2048
    maxRetentionHours: number;       // Free: 24, Pro: 720
  };
  subscription: { status: SubscriptionStatus; autoRenewStatus: boolean } | null;
}
```

The `-1` sentinel lets the client render "Unlimited" without per-tier special cases. Grace/billing-retry policy (Apple): when `tier` is monthly/annual and `status ∈ { in_grace, in_billing_retry }` → report `PRO_CAPS`. When `status ∈ { expired, revoked, refunded }` → report `FREE_CAPS` and `tier: 'free'`.

**Verification:** `cd backend && npm run typecheck`

**Acceptance:**
- Unauth → 401.
- No sub rows → `{ tier: 'free', expiresAt: null, caps: FREE_CAPS, subscription: null }`.
- Active monthly → `{ tier: 'monthly', expiresAt, caps: PRO_CAPS, subscription: { status: 'active', autoRenewStatus: true } }`.

---

### A6.2 — `/ring-default:codereview` checkpoint for Part 6

REQUIRED SUB-SKILL: `ring-default:requesting-code-review` on `me.ts` + `tierCaps.ts`. Reviewers check: response shape is stable (clients depend on it); grace-period policy matches Apple's; `FREE_CAPS` is defined exactly once (no drift between middleware and endpoint).

---

## Part 7 — Tests

All tests live under `backend/test/`, follow the fake-drizzle pattern from `test/uploads.test.ts`. Lift the `freshStore` helper into a shared `backend/test/support.ts` at the start of this part and import it from every new file.

### A7.1 — Proxy tests [parallel: A7.2, A7.3, A7.4, A7.5]

**Files:** Create `backend/test/redirect.test.ts`.

**Intent:** Vitest suite over `GET /s/:token` using the Miniflare R2 binding (`env.R2.put` in `beforeEach`). Seed device + asset + shareLink in the drizzle fake. Cases:
- 200 HTML (`Accept: text/html`) — `Content-Type: text/html; charset=utf-8`, body contains `<meta property="og:title" content="..."` and `data-expires-at="..."`, `Cache-Control: private, no-store`.
- 200 binary full (`Accept: */*`) — `Content-Length` = size, `Content-Type` = stored MIME, bytes match R2, `Content-Disposition` starts with `attachment; filename*=UTF-8''`.
- 206 range (`Range: bytes=0-99`) — `Content-Range: bytes 0-99/<size>`, `Content-Length: 100`, first 100 bytes.
- 416 unsatisfiable (`Range: bytes=999999999-`) — `Content-Range: bytes */<size>`.
- 410 expired, HTML Accept — HTML body contains "expired".
- 410 expired, JSON Accept — `application/problem+json`.
- 410 revoked — both content negotiations.
- 404 unknown token — both content negotiations.
- `HEAD /s/:token` — 200 with binary headers, empty body.
- `?dl=1` with HTML Accept → binary stream, not HTML.
- `expect(response.body).toBeInstanceOf(ReadableStream)` on the binary path (fails if handler buffers).

**Verification:** `cd backend && npm test -- redirect.test.ts --run 2>&1 | tail -20`

**Acceptance:** >= 10 test cases pass; stream assertion present; both 410 content negotiations covered.

---

### A7.2 — `/v1/iap/verify` tests [parallel: A7.1, A7.3, A7.4, A7.5] [depends: A4.2]

**Files:**
- Create: `backend/test/iap-verify.test.ts`
- Create: `backend/test/fixtures/apple-jws.ts` — helper that signs test JWS payloads with an ES256 keypair generated in `beforeAll` via `jose.generateKeyPair('ES256')`. Use `vi.mock` to swap the `APPLE_ROOT_CERT_PEM` constant for the test cert — simpler than issuing a real X.509 chain and keeps the JWS format honest.

**Intent:** Mock `getSubscriptionStatus` with a canned Apple response. Cases:
- No bearer → 401.
- Invalid JWS structure → 422 `invalid_receipt`.
- Valid JWS, `red.fastsha.pro.monthly`, status=active → 200 `{ tier: 'monthly', status: 'active', expiresAt }` + row upserted.
- `red.fastsha.pro.lifetime` → 200 `{ tier: 'lifetime', expiresAt: null }`.
- Unknown productId → 422 `unknown_product`.
- Sandbox environment while `APP_ENV=production` → 422.
- Repeat `/verify` with the same `originalTransactionId` → 200, row count unchanged (upsert).

**Verification:** `cd backend && npm test -- iap-verify.test.ts --run 2>&1 | tail -20`

**Acceptance:** 7+ cases pass; no network access from tests.

---

### A7.3 — `/v1/iap/webhook` tests [parallel: A7.1, A7.2, A7.4, A7.5] [depends: A4.3]

**Files:** Create `backend/test/iap-webhook.test.ts`.

**Intent:** Canonical signed-payload fixtures per notificationType. Cases:
- `DID_RENEW` → status=active, expiresAt bumped.
- `EXPIRED` → status=expired.
- `REFUND` → status=refunded.
- `GRACE_PERIOD_EXPIRED` → status=expired.
- `DID_CHANGE_RENEWAL_STATUS` + autoRenewStatus=false → status unchanged, autoRenewStatus flips.
- `DID_FAIL_TO_RENEW` + subtype `GRACE_PERIOD` → status=in_grace.
- `DID_FAIL_TO_RENEW` no subtype → status=in_billing_retry.
- Invalid JWS → 401.
- Wrong bundleId → 200 no-op.
- Replay `notificationUUID` → 200, `store.subscriptions.length` unchanged, KV key `iap:notif:<uuid>` present.

**Verification:** `cd backend && npm test -- iap-webhook.test.ts --run 2>&1 | tail -20`

**Acceptance:** all 7 canonical types covered; replay test asserts KV key.

---

### A7.4 — Free-tier middleware tests [parallel: A7.1, A7.2, A7.3, A7.5]

**Files:** Create `backend/test/rateLimitFreeTier.test.ts`.

**Intent:** Exercise `POST /v1/uploads/` through the Hono stack. Cases:
- Free, 1st upload → 200, KV counter = 1.
- Free, 4th upload → 402 `free_tier_daily_exceeded`, counter still 3.
- Free, size=200MB → 402 `free_tier_size_exceeded`, counter untouched (seed=0, assert still 0).
- Free, retentionPolicy=oneWeek → 200 with `upload_job.retentionPolicy === 'oneDay'` and response flag `retentionClamped: true`.
- Pro, size=1GB x20 uploads → all 200, no 402.
- Pro, retentionPolicy=oneMonth → 200, NOT clamped.

**Verification:** `cd backend && npm test -- rateLimitFreeTier.test.ts --run 2>&1 | tail -20`

**Acceptance:** size-cap test proves counter untouched; clamp test proves silence.

---

### A7.5 — `/v1/me` tests [parallel: A7.1, A7.2, A7.3, A7.4]

**Files:** Create `backend/test/me.test.ts`.

**Intent:** Cases:
- Unauth → 401.
- No sub → Free caps, `expiresAt: null`, `subscription: null`.
- Active monthly → Pro caps, `subscription.status: 'active'`.
- Expired sub row → Free caps, `tier: 'free'`, `subscription: null` (only active subs reported).
- `in_grace` sub → Pro caps, `subscription.status: 'in_grace'`.
- Lifetime → Pro caps, `expiresAt: null`.

**Verification:** `cd backend && npm test -- me.test.ts --run 2>&1 | tail -20`

**Acceptance:** caps match `FREE_CAPS`/`PRO_CAPS` exports from `tierCaps.ts`; grace-period case returns Pro caps.

---

### A7.6 — Full test suite green

**Intent:** Run the whole suite after A7.1–A7.5. Fix any cross-test state pollution (module-level `store` let — `beforeEach(() => store = freshStore())` in every file, lifted to `test/support.ts`).

**Verification:** `cd backend && npm test -- --run 2>&1 | tail -30`

**Acceptance:** zero failing tests; new files import from `test/support.ts` (no copy-pasted `freshStore` bodies).

---

## Part 8 — Wire-up + final review

### A8.1 — Mount new routes in `index.ts` [depends: A3.3, A6.1]

**Files:** Modify `backend/src/index.ts`.

**Intent:** After the existing `app.route(...)` calls, add `app.route('/v1/iap', iapRoutes); app.route('/v1/me', meRoutes);` (the A1.7 og-image route is already mounted). `APP_PATH_PREFIXES` covers `/v1` — verify by reading, no change needed.

**Verification:** `cd backend && npm run typecheck && npm test -- --run 2>&1 | tail -10`

**Acceptance:** both new mounts present; `GET /v1/me` without auth → 401.

---

### A8.2 — Update `wrangler.toml` secrets docstring

**Files:** Modify `backend/wrangler.toml`.

**Intent:** Extend the secrets comment block to list all 7 Wrangler secrets (the 4 existing + `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_P8_KEY_BASE64`). `APPLE_BUNDLE_ID` already lives in `[vars]` from A4.1.

**Verification:** `cd backend && npx wrangler deploy --dry-run 2>&1 | tail -20` — no missing-binding warnings.

**Acceptance:** all 7 secrets listed in the comment; dry-run succeeds.

---

### A8.3 — Update `backend/.env.example` + `README.md`

**Files:** Modify `backend/.env.example` and `backend/README.md`.

**Intent:** Add the four new env placeholders to `.env.example` with one-line provenance comments each. Add a two-paragraph "Pro subscriptions setup" section to `README.md` covering: (a) registering StoreKit product IDs `red.fastsha.pro.monthly|annual|lifetime` in ASC, (b) `base64 -i AuthKey_XXXXXX.p8 | tr -d '\n' | pbcopy` and the `wrangler secret put` commands.

**Verification:** `cd backend && rg -n "APP_STORE_CONNECT" .env.example README.md`

**Acceptance:** both files updated; README section sits under "Setup".

---

### A8.4 — Final `/ring-default:codereview` across the full diff

REQUIRED SUB-SKILL: `ring-default:requesting-code-review` on the full branch diff vs `main`. All 5 reviewers in parallel (code, business-logic, security, test, nil-safety). Fix Critical/High/Medium; `TODO(review):` for Low, `FIXME(nitpick):` for Cosmetic. Do not open a PR until zero Critical/High/Medium remain.

Verify:
- No signed R2 URLs leave the Worker in any response.
- `Cache-Control: private, no-store` on every `/s/*` response.
- Webhook JWS verification is the FIRST operation in `POST /v1/iap/webhook` (before JSON parse, before DB).
- `FREE_CAPS`/`PRO_CAPS` defined exactly once (in `tierCaps.ts`), referenced from middleware + `/v1/me`.
- No `console.log` of raw JWS, p8 bytes, or signed JWTs.
- Every new migration is `BEGIN;`/`COMMIT;`-wrapped.
- `rateLimitFreeTier` clones the request body before `await c.req.json()`.

---

### A8.5 — Smoke test against a preview deployment

**Intent:** Deploy to a preview env (`npx wrangler deploy --env preview` if configured; else a throwaway account) and hit:
- `GET /s/<token>` with `Accept: text/html` → HTML preview, OG tags, download button points at `/download`.
- `GET /s/<token>/download` → streams.
- Same with `Range: bytes=0-99` → 206.
- `GET /v1/me` with a Free device bearer → expected shape.
- POST a fixture webhook → 200 + DB row upsert.

**Verification:** manual curl commands; results captured in the PR description.

**Acceptance:** all five smoke cases pass; preview URL in PR description.

---

## Appendix — Failure recovery

1. **Typecheck fails:** `cd backend && npm run typecheck`. Common cause: a module imports from `~/db/schema` before A2.1 lands — reorder tasks.
2. **Test flakes:** KV or fake-store state leakage. Confirm `beforeEach(resetStore)` is in place.
3. **`wrangler dev` won't start:** `ENV_MISCONFIGURED` → `envSchema` rejected a new var. Double-check `.env`.
4. **Migration fails on a populated DB:** MVP assumes an empty DB (see `0001_ephemeral.sql` preamble). For a pre-existing `subscription` table: `DROP TABLE subscription CASCADE;` and re-run.
5. **Can't recover:** document the failure in the PR description, return to the human partner. Do not `git reset --hard` without approval — preserve partial progress.

---

## Appendix — Task-ID index

- **A1.1** Create HTML preview renderer module
- **A1.2** Add R2 streaming helper
- **A1.3** Add Range header parser
- **A1.4** Add RFC 5987 filename encoder
- **A1.5** Rewrite redirect route into proxy + preview
- **A1.6** Update `uploads.ts` complete-response callers
- **A1.7** Add `/og-image.png` static passthrough
- **A1.8** `/ring-default:codereview` checkpoint for Part 1
- **A2.1** Add Drizzle `subscription` table
- **A2.2** Write SQL migration `0002_subscriptions.sql`
- **A2.3** Subscription service (CRUD helpers)
- **A2.4** `/ring-default:codereview` checkpoint for Part 2
- **A3.1** IAP route module scaffold
- **A3.2** `POST /v1/iap/verify` implementation
- **A3.3** `POST /v1/iap/webhook` implementation
- **A3.4** `/ring-default:codereview` checkpoint for Part 3
- **A4.1** App Store Server API module scaffold + JWT builder
- **A4.2** Transaction JWS verifier
- **A4.3** Notification JWS verifier + status fetch
- **A4.4** `/ring-default:codereview` checkpoint for Part 4
- **A5.1** Free-tier enforcement middleware
- **A5.2** Mount the middleware on upload endpoints
- **A5.3** `/ring-default:codereview` checkpoint for Part 5
- **A6.1** `GET /v1/me` route module
- **A6.2** `/ring-default:codereview` checkpoint for Part 6
- **A7.1** Proxy tests
- **A7.2** `/v1/iap/verify` tests
- **A7.3** `/v1/iap/webhook` tests
- **A7.4** Free-tier middleware tests
- **A7.5** `/v1/me` tests
- **A7.6** Full test suite green
- **A8.1** Mount new routes in `index.ts`
- **A8.2** Update `wrangler.toml` for new secrets + vars
- **A8.3** Update `backend/.env.example` + `README.md`
- **A8.4** Final `/ring-default:codereview` across the full diff
- **A8.5** Smoke test against a preview deployment
