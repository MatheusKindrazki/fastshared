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
```

`DEVICE_TOKEN_PEPPER` must be a long random string (generate with
`openssl rand -base64 48`). Losing it invalidates every device token.

Public vars live in `wrangler.toml` under `[vars]`. Update `R2_ACCOUNT_ID` and
the KV namespace id before first deploy.

## Provision the database

1. Create a Neon project, copy the pooled connection string into `DATABASE_URL`.
2. Apply migrations:

```bash
pnpm db:migrate     # applies drizzle/0000_init.sql then drizzle/0001_ephemeral.sql
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

The response includes `token`, `shortUrl` (`https://fsh.dev/s/<token>`),
`expiresAt`, `deleteAfter`, `linkStatus`, and `retentionPolicy`.

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
