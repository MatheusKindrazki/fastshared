# fastshared-backend

Cloudflare Workers backend for FastShared. Issues R2 presigned PUTs, mints
short-lived tokens, verifies uploads, and serves `/s/:token` redirects. Hono +
Drizzle + Neon Postgres.

## Ephemeral model

Every upload is a temporary anonymous bearer link. The R2 bucket is private —
clients never get a durable public URL. Each share link has a mandatory
`expires_at`; `/s/:token` looks the link up, issues a fresh 60-second signed R2
GET, and 302s to it. After expiry the endpoint returns `410 Gone`. The R2
object is deleted by an app-level cron 24 hours past expiry (grace window).
Three scheduled jobs keep the system honest: a per-minute deletion worker, an
hourly reconciler, and a weekly multipart-upload sweeper.

## Prerequisites

- Node 20+
- pnpm (or npm / bun)
- A Cloudflare account with R2 enabled and a created bucket `fastshared-prod`
- A Neon Postgres project (free tier is fine)
- `wrangler` logged in (`pnpm dlx wrangler login`)

## Install

```bash
pnpm install
```

## Environment

Copy the example and fill in values used by local tooling (drizzle-kit, tests):

```bash
cp .env.example .env
# edit .env, set DATABASE_URL at minimum
```

Set Worker secrets (used in `wrangler dev` and production):

```bash
pnpm dlx wrangler secret put DATABASE_URL
pnpm dlx wrangler secret put R2_ACCESS_KEY_ID
pnpm dlx wrangler secret put R2_SECRET_ACCESS_KEY
pnpm dlx wrangler secret put DEVICE_TOKEN_PEPPER
pnpm dlx wrangler secret put APP_STORE_CONNECT_KEY_ID
pnpm dlx wrangler secret put APP_STORE_CONNECT_ISSUER_ID
pnpm dlx wrangler secret put APP_STORE_CONNECT_P8_KEY_BASE64
```

`DEVICE_TOKEN_PEPPER` must be a long random string (generate with
`openssl rand -base64 48`). Losing it invalidates every device token.

Public vars live in `wrangler.toml` under `[vars]` — `APP_ENV`,
`SHORT_LINK_HOST`, `PUBLIC_API_HOST`, `R2_BUCKET_NAME`, `R2_ACCOUNT_ID`,
`APPLE_BUNDLE_ID`. Update `R2_ACCOUNT_ID` and the KV namespace id before
first deploy.

## Pro subscriptions setup

The `/v1/iap/verify` and `/v1/iap/webhook` endpoints sign App Store Connect
JWTs and verify Apple-signed JWS receipts. Three one-time steps:

1. **Register product IDs in App Store Connect** (Subscriptions + Lifetime
   IAP): `red.fastsha.pro.monthly`, `red.fastsha.pro.annual`,
   `red.fastsha.pro.lifetime`. Match the StoreKit configuration the client
   ships. The server throws `422 unknown_product` on any product ID not in
   this set — keep them in lockstep.
2. **Create an API Key with "In-App Purchase" access** at
   <https://appstoreconnect.apple.com/access/api>. Note the Key ID and
   Issuer ID; download the `AuthKey_XXXXXX.p8` file (one-time download).
3. **Upload the three secrets to Wrangler**:

   ```bash
   base64 -i AuthKey_XXXXXX.p8 | tr -d '\n' | pbcopy
   pnpm dlx wrangler secret put APP_STORE_CONNECT_P8_KEY_BASE64   # paste
   pnpm dlx wrangler secret put APP_STORE_CONNECT_KEY_ID           # the 10-char ID
   pnpm dlx wrangler secret put APP_STORE_CONNECT_ISSUER_ID        # UUID
   ```

Also configure Apple's **Server-to-Server Notifications v2** to point at
`https://api.fastsha.red/v1/iap/webhook` (both Production and Sandbox URLs).
Notifications are signed by Apple; the Worker verifies the JWS chain before
touching the database, so the endpoint is safe to expose unauthenticated.

## Auth: Sign in with Apple

`POST /v1/auth/apple` verifies an Apple identity token, finds-or-creates a
user keyed on the Apple `sub` claim, optionally claims an existing anonymous
device, and issues a fresh device token scoped to the user.

Request body:

```jsonc
{
  "identityToken": "<ES256 JWT from ASAuthorizationAppleIDCredential>",
  "authorizationCode": "<single-use auth code from Apple>",
  "fullName": "Ada Lovelace",          // only populated on FIRST authorization
  "email": "ada@example.com",          // only populated on FIRST authorization
  "claimDeviceToken": "<prior anonymous device token>", // optional
  "platform": "ios",                   // or "ipados" | "macos"
  "appVersion": "0.2.0"                // optional
}
```

Response (201):

```jsonc
{
  "deviceToken": "<new bearer token>",
  "userId": "uuid",
  "isNewUser": true
}
```

Apple only returns `fullName` and `email` on the very first authorization of
your bundle identifier per Apple ID — every subsequent call omits both. The
endpoint must not require them. We persist whatever we see the first time
and never overwrite non-null columns on later calls.

The bundle identifier used as the JWT `aud` claim comes from the
`APPLE_BUNDLE_ID` public var (see `wrangler.toml [vars]` and `.env.example`).
Apple's JWKS is fetched lazily from
<https://appleid.apple.com/auth/keys> and cached at module scope per Worker
isolate.

One-time provisioning: enable "Sign In with Apple" for the bundle ID in the
Apple Developer portal under **Certificates, Identifiers & Profiles →
Identifiers → \<your app ID\> → Capabilities**. See
<https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_js/configuring_your_webpage_for_sign_in_with_apple>.

## Provision the database

1. Create a Neon project, copy the pooled connection string into `DATABASE_URL`.
2. Apply migrations:

```bash
pnpm db:migrate     # applies drizzle/0000_init.sql through drizzle/0003_apple_auth.sql
```

The initial migration requires the `pgcrypto` and `citext` extensions; Neon
enables these per-database automatically via `CREATE EXTENSION IF NOT EXISTS`.
`0001_ephemeral.sql` assumes an empty DB (MVP constraint) — it backfills
`expires_at` and `delete_after` defensively before tightening to NOT NULL.

## R2 lifecycle safety net

The app-level `deletion_job` cron is authoritative — it is what actually deletes
objects on schedule. On top of that, configure a bucket-level lifecycle rule
as a belt-and-suspenders fallback so that if the scheduler is paused for days
nothing lingers forever. Suggested rule: delete all `uploads/` objects 90 days
after creation.

Wrangler config has no R2 lifecycle knob, so set it out-of-band:

```bash
wrangler r2 bucket lifecycle set fastshared-prod --rule '<json>'
```

(See <https://developers.cloudflare.com/r2/buckets/object-lifecycles/>.)

## Run locally

```bash
pnpm dev
```

Wrangler will bind R2 + KV in miniflare and tail logs. Structured JSON logs
print per request and per scheduled invocation.

## Smoke tests

Health:

```bash
curl -sS http://127.0.0.1:8787/v1/health | jq
```

Register a device and stash the bearer token:

```bash
curl -sS -X POST http://127.0.0.1:8787/v1/devices \
  -H 'content-type: application/json' \
  -d '{"platform":"ios","appVersion":"0.1.0"}' | jq
```

Presign an upload (replace `$TOKEN`):

```bash
curl -sS -X POST http://127.0.0.1:8787/v1/uploads \
  -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "clientJobId":"b0bd4c8a-1f2e-4d3c-9a8b-5d6e7f8a9b0c",
    "contentType":"image/jpeg",
    "sizeBytes":204800,
    "originalFilename":"photo.jpg",
    "retentionPolicy":"oneDay"
  }' | jq
```

`retentionPolicy` accepts `oneHour`, `oneDay` (default), `oneWeek`, `oneMonth`,
or `custom` (pair with `customTtlSeconds` between 300 and 2 592 000).

Complete the upload after PUTing bytes to the presigned URL:

```bash
curl -sS -X POST http://127.0.0.1:8787/v1/uploads/$UPLOAD_ID/complete \
  -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"contentType":"image/jpeg","sizeBytes":204800}' | jq
```

The response includes `token`, `shortUrl` (`https://fastsha.red/s/<token>`),
`expiresAt`, `deleteAfter`, `linkStatus`, and `retentionPolicy`.

### Bundle uploads — `POST /uploads/batch`

When the client sends N (>=2) files together, the backend mints a single
bundle link (`https://fastsha.red/b/{token}`) that aggregates every asset.
Single-file flow (`/uploads` + `/s/{token}`) is unchanged.

Request:

```jsonc
{
  "retentionPolicy": "oneDay",
  "visibility": "public",
  "items": [
    {
      "clientJobId": "a",
      "contentType": "image/jpeg",
      "sizeBytes": 1024,
      "sha256": "...",                  // optional
      "originalFilename": "photo1.jpg"  // optional
    },
    { "clientJobId": "b", "contentType": "image/jpeg", "sizeBytes": 2048 }
  ]
}
```

Response:

```jsonc
{
  "bundleToken": "abc123",
  "bundleShortUrl": "https://fastsha.red/b/abc123",
  "expiresAt": "2026-04-21T12:00:00Z",
  "items": [
    { "clientJobId": "a", "uploadId": "...", "putUrl": "..." },
    { "clientJobId": "b", "uploadId": "...", "multipart": { /* ... */ } }
  ]
}
```

Each file in the batch counts as one event against the daily cap (free tier
= 3/day) — a batch of 4 from a free user fails fast with `429` before any
DB insert. Junction-table idempotency is keyed on `(share_link_id,
upload_job_id)`: re-completing the same `uploadId` is a no-op. Two slots
that dedup to the same R2 asset still occupy two distinct junction rows
(one per `uploadJobId`).

`GET /b/:token` renders an HTML preview listing every asset in the bundle.
`GET /b/:token/d/:assetId` streams an individual asset (validated against
the junction table — a stray `assetId` from another bundle returns 404).

Revoke a live link:

```bash
curl -sS -X POST http://127.0.0.1:8787/v1/links/$TOKEN_VAL/revoke \
  -H "authorization: Bearer $TOKEN" | jq
```

Subsequent `GET /s/$TOKEN_VAL` returns `410 Gone`.

## Deploy

```bash
pnpm deploy                      # default env
pnpm dlx wrangler deploy --env production
```

## Tests

```bash
pnpm test
```

## MVP limitations

- Single-part uploads only (R2 presigned PUT is capped around 5 GB; no
  multipart orchestration yet — the weekly sweeper aborts any stale ones).
- Rate limiter is a fixed-window counter in KV. Cheap and good enough for MVP,
  but KV has eventual consistency and no atomic CAS — a Durable Object is the
  correctness upgrade.
- Password-protected links accept the token but the verify endpoint returns
  `501 not_implemented`. Post-MVP.
- History returns tombstones (expired/revoked/deleted) so the client renders a
  full 30-day list with badges; server-side `effectiveLinkStatus` reconciles
  rows whose expiry has slipped past the last reconciler pass.
