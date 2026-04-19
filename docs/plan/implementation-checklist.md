# Implementation checklist

Concrete developer actions, organized by milestone. Check items off as they land on `main`. See [MVP roadmap](./mvp-roadmap.md) for the higher-level view.

## M0 — Repo setup

- [ ] Initialize the monorepo with `apple/`, `backend/`, `docs/`, and `.github/` directories
- [ ] Add top-level `README.md` with quickstart and docs index
- [ ] Add `.gitignore` covering Swift/Xcode, Node/TS, macOS, and general artifacts
- [ ] Add `.editorconfig` with UTF-8 / LF / 2-space default / 4-space Swift
- [ ] Add `.env.example` with backend env var union and Apple xcconfig pointer
- [ ] Add `Makefile` with `bootstrap`, `ios`, `backend-dev`, `backend-test`, `db-migrate`, `db-generate`, `lint`, `fmt`, `clean`
- [ ] Add `.github/workflows/apple.yml` with XcodeGen + xcodebuild (continue-on-error until M1)
- [ ] Add `.github/workflows/backend.yml` with pnpm install / typecheck / test
- [ ] Author `docs/product/overview.md`
- [ ] Author `docs/architecture/system-design.md`
- [ ] Author `docs/architecture/apple-client.md`
- [ ] Author `docs/architecture/backend.md`
- [ ] Author `docs/architecture/upload-flow.md`
- [ ] Author `docs/architecture/security.md`
- [ ] Author `docs/architecture/data-model.md`
- [ ] Author `docs/plan/mvp-roadmap.md`
- [ ] Author `docs/plan/implementation-checklist.md` (this file)
- [ ] Confirm all Mermaid diagrams render in GitHub preview

## M1 — Base SwiftUI app

- [ ] Create `FastSharedCore` local Swift Package under `apple/FastSharedCore/`
- [ ] Create `FastSharedApp` target via XcodeGen `project.yml` for iOS, iPadOS, macOS
- [ ] Register bundle ids: `com.yourco.fastshared` (app), `com.yourco.fastshared.share` (extension, created in M2)
- [ ] Set deployment targets to iOS 17, iPadOS 17, macOS 14
- [ ] Wire `FastSharedApp` to depend on `FastSharedCore`
- [ ] Create `apple/Config/Debug.xcconfig` and `Release.xcconfig` with `PUBLIC_API_HOST` and `SHORT_LINK_HOST`
- [ ] Add `OSLog` subsystem `com.yourco.fastshared` with categories `upload`, `extension`, `ui`, `net`, `storage`
- [ ] Add empty `HistoryView`, `SettingsView`, and a launch-time `AppDelegate`-equivalent
- [ ] Add first `FastSharedCoreTests` target
- [ ] Make CI job required once Apple build is green

## M2 — Share Extension

- [ ] Create `FastSharedShareExt` target, add to `project.yml`
- [ ] Configure `NSExtensionAttributes` with UTType list (image, movie, pdf, file-url)
- [ ] Implement `ShareViewController` that reads `inputItems`, streams to a temp file, computes SHA-256
- [ ] Show a minimal SwiftUI confirmation UI while staging
- [ ] Call `extensionContext?.completeRequest(returningItems:)` once staging enqueues
- [ ] Reject items whose UTType is not in the allowlist with a clear error
- [ ] Extension unit test harness with synthesized `NSItemProvider`
- [ ] Manually verify extension appears in Photos, Files, Safari, Messages share sheets

## M3 — App Group + shared background session

- [ ] Create `APP_GROUP_IDENTIFIER` `group.com.yourco.fastshared` in Apple Developer portal
- [ ] Enable App Group on both app and extension app ids
- [ ] Add App Group entitlement to both targets in `project.yml`
- [ ] Add Keychain Sharing entitlement with access group `$(AppIdentifierPrefix)com.yourco.fastshared`
- [ ] Move staging directory from temp into App Group container
- [ ] Create shared SwiftData `ModelContainer` in `FastSharedCore` pointed at the App Group URL
- [ ] Define `UploadJobEntity` and `ShareLinkEntity` (ephemeral shape lands in M4.5)
- [ ] Implement `Keychain` wrapper using `kSecAttrAccessGroup`
- [ ] Build shared background `URLSession` configuration with identifier `com.yourco.fastshared.upload`
- [ ] Wire `application(_:handleEventsForBackgroundURLSession:completionHandler:)` in the main app
- [ ] Write an integration test that enqueues from extension and observes completion in the app
- [ ] Add a kill-the-extension soak script (manual)

## M4 — Backend skeleton

- [ ] Scaffold `backend/` with `pnpm init`, `hono`, `drizzle-orm`, `@neondatabase/serverless`, `zod`, `aws4fetch`
- [ ] Configure `wrangler.toml` with `env.dev` and `env.prod`, bindings for KV and R2
- [ ] Create KV namespaces `RATE_LIMITS` and `TOKEN_RESERVATIONS` via `wrangler kv namespace create`
- [ ] Create R2 buckets `fastshared-dev` and `fastshared-prod`
- [ ] Set secrets `DATABASE_URL`, `R2_*`, `DEVICE_TOKEN_PEPPER` via `wrangler secret put`
- [ ] Implement `requestId`, `logger`, `errorShape`, `cors`, `rateLimit`, `auth`, `idempotency` middleware
- [ ] Implement `POST /v1/devices` — mint token, hash with pepper, insert `user` + `device`
- [ ] Write Drizzle schema and first migration `drizzle/0000_init.sql`
- [ ] Run `pnpm drizzle-kit migrate` against Neon dev branch
- [ ] Unit tests for middleware and `/v1/devices`
- [ ] `pnpm typecheck` and `pnpm test` green in CI

## M4.5 — Ephemeral lifecycle

- [ ] Write `drizzle/0001_ephemeral.sql`: rename `object_key → storage_key`, rename `slug → token`
- [ ] Add columns to `share_link`: `link_status`, `retention_policy`, `expires_at NOT NULL`, `delete_after`, `revoked_at`, `last_accessed_at`, `access_count`, `max_access_count`
- [ ] Add columns to `asset`: `delete_after NOT NULL`, `deleted_at`, `deletion_status`, `deletion_attempts`, `deletion_last_error`
- [ ] Swap dedup index to partial unique `(owner_device_id, sha256) WHERE deleted_at IS NULL AND delete_after > now()`
- [ ] Add `share_link_active_expires_idx` partial index on `(expires_at) WHERE link_status = 'active'`
- [ ] Add columns to `upload_job`: `retention_policy`, `custom_ttl_seconds`; extend state check with `deduped`; rename `failed_permanent → failed`
- [ ] Create `deletion_job` table with partial unique `(asset_id) WHERE status IN ('pending','running')` and due-queue `(scheduled_for) WHERE status = 'pending'`
- [ ] Implement `backend/src/util/token.ts` — 22-char base62 via `crypto.getRandomValues(32)` + base62 encode + truncate; collision-retry via `TOKEN_RESERVATIONS` KV
- [ ] Implement `backend/src/policy/retention.ts` — map `oneHour|oneDay|oneWeek|oneMonth|custom` to seconds; clamp `customTtlSeconds` to `[300, 2592000]`
- [ ] Implement `backend/src/services/deletion.ts` — `FOR UPDATE SKIP LOCKED LIMIT 50`, R2 DELETE, backoff `120 × 2^(attempts-1)s` cap 7200s jitter ±10%, terminal at 8 attempts
- [ ] Implement `backend/src/services/reconciliation.ts` — expire stale links, enqueue missing deletion jobs, reset stuck running, sampled HEAD probe
- [ ] Implement `backend/src/services/multipartSweeper.ts` — stub that logs (full impl in M8)
- [ ] Export `scheduled(event, env, ctx)` from the Worker dispatching by `event.cron`
- [ ] Register three cron triggers in `wrangler.toml [triggers]`: `*/1 * * * *`, `0 * * * *`, `0 3 * * 0`
- [ ] Rewrite `GET /s/:token` handler: DB-backed load, `link_status` + `expires_at` + `asset.deleted_at` check, 302 to 60 s signed GET, 410 Gone with `code: "link_gone"` and `reason: expired|revoked|deleted`, 404 for unknown
- [ ] Ensure all `/s/:token` responses set `Cache-Control: no-store`, `X-Robots-Tag: noindex, nofollow`, `Referrer-Policy: no-referrer`
- [ ] Add resolve-route rate limit: per-IP 60/min and per-token 300/min (KV buckets with `HMAC-SHA256(pepper, token)` keying)
- [ ] Implement `POST /v1/links/:token/revoke` — owner-only, flip `link_status='revoked'`, `revoked_at=now()`, pull `deletion_job.scheduled_for` to now
- [ ] Update `POST /v1/uploads` to accept `retentionPolicy` + optional `customTtlSeconds`; return `expiresAt`, `deleteAfter`, `retentionPolicy`
- [ ] Update `POST /v1/uploads/:id/complete` to return `token`, `expiresAt`, `deleteAfter`, `linkStatus`, `retentionPolicy`; reject with 409 `complete_too_late` if `expires_at <= now() + 60s`
- [ ] Add retention picker UI to `FastSharedShareExt` (4 presets, default `oneDay`)
- [ ] Add default-retention picker to `SettingsView` on iOS and macOS
- [ ] Update `FastSharedCore` `APIClient` DTOs to carry retention fields end-to-end
- [ ] Update `UploadJobEntity` + `ShareLinkEntity` SwiftData shapes to match data-model doc
- [ ] Configure R2 lifecycle rule (90 d expire) via `wrangler r2 bucket lifecycle put --id 'fs-safety-net' ...` for dev and prod buckets
- [ ] Unit tests for deletion service (happy path, transient retry, terminal failure, stuck-running reset, idempotency)
- [ ] Unit tests for retention clamping, token format, backoff math
- [ ] Integration tests for `/s/:token`: 302 happy path, 410 on expired/revoked/deleted, 404 unknown, all three header invariants, rate-limit trip
- [ ] Integration test for `POST /v1/links/:token/revoke` → next `/s/:token` returns 410 with `reason: "revoked"`
- [ ] Soak test: 100 tokens with staggered `expires_at`, run cron 20x, assert all reach `removed`

## M5 — R2 upload pipeline

- [ ] Implement R2 presign helper using `aws4fetch` and S3-compat endpoint
- [ ] Implement `POST /v1/uploads` with zod body validation, idempotency lookup, and `retentionPolicy` plumbing all the way to `expires_at` / `delete_after` computation
- [ ] Enforce per-type size caps at presign
- [ ] Implement `POST /v1/uploads/:id/complete` with R2 HEAD, size check, transaction that inserts `asset`, `share_link`, and seed `deletion_job`
- [ ] Return `token`, `expiresAt`, `deleteAfter`, `linkStatus`, `retentionPolicy` from `complete`
- [ ] Client `APIClient` methods for both endpoints with typed responses including the retention fields
- [ ] Wire `FastSharedShareExt` to call presign with the user's chosen `retentionPolicy`, then `uploadTask(with:fromFile:)`
- [ ] Wire `FastSharedApp` session delegate to call `complete` and persist `expiresAt` + `deleteAfter` on the SwiftData row
- [ ] Integration test: 5 MB PNG shared end-to-end against a Wrangler dev server and a real R2 dev bucket; verify `delete_after = expires_at + 24h`
- [ ] Error path: forced 413 from presign surfaces cleanly on the client
- [ ] Error path: forced 409 `complete_too_late` surfaces as a retriable error with a fresh presign affordance

## M6 — Token + anonymous resolve + expiry

- [ ] Token generator lives in `backend/src/util/token.ts` (22-char base62) — landed in M4.5; add any missing test coverage
- [ ] `share_link` insert in the `complete` transaction, reserving the token in `TOKEN_RESERVATIONS` KV first
- [ ] Confirm `GET /s/:token` 302 with `SIGNED_GET_TTL_SECONDS=60` configured via env
- [ ] 410 Gone path implemented for `expired`, `revoked`, `deleted` (landed in M4.5; regression-test it here)
- [ ] 404 path for unknown token returns RFC 7807 body with `code: "link_not_found"`
- [ ] Resolve-route security headers present on every response (`no-store`, `noindex, nofollow`, `no-referrer`)
- [ ] Configure route `fastsha.red/s/*` on the Worker
- [ ] `SHORT_LINK_HOST` env respected when formatting `shortUrl` in responses, format is `https://{host}/s/{token}`
- [ ] Integration test: full presign → PUT → complete → redirect round-trip with a real file download
- [ ] Integration test: bump `expires_at` in DB, assert next `/s/:token` returns 410 with `reason: "expired"`
- [ ] Integration test: call revoke, assert next `/s/:token` returns 410 with `reason: "revoked"`

## M7 — Upload history

- [ ] `GET /v1/history` with cursor pagination, `?cursor=` + `?limit=` (max 100); rows carry `expiresAt`, `deleteAfter`, `linkStatus`, `retentionPolicy`, `accessCount`
- [ ] SwiftData write of `ShareLinkEntity` on successful `complete` with all ephemeral fields
- [ ] `HistoryView` lists entries grouped by day, most recent first, with countdown badge (green > 6 h, amber ≤ 6 h, red ≤ 30 m, grey `Expired` / `Revoked` / `Removed`)
- [ ] `TimelineView(.periodic(from: .now, by: 30))` refreshes visible rows every 30 s
- [ ] Implement `lazyMarkExpiredIfNeeded` on row render
- [ ] Row tap re-copies the link (only on `active` rows) and shows a subtle confirmation
- [ ] Row long-press action sheet: Share, Open in browser, Revoke (only on `active` rows)
- [ ] `DetailView` shows `expires at`, `media deleted at`, `accessCount`, and a **Revoke link** destructive action
- [ ] Revoke button calls `POST /v1/links/:token/revoke` and updates SwiftData
- [ ] Tombstone rows persist 30 days, then reaped on launch
- [ ] Mac Command menu: Upload from Clipboard (⌘⇧V), Open Recent Link (⌘L)
- [ ] `.fileImporter` button on Mac main view
- [ ] Drag-and-drop target on Mac main view (applies Settings default retention)
- [ ] UI tests covering happy path + countdown visibility + revoke flow on iOS and macOS
- [ ] Internal TestFlight build cut

## M8 — Reliability + multipart + deletion hardening

- [ ] Finish retry policy for upload path: base 2 s, cap 60 s, full jitter, max 8 attempts
- [ ] Implement resume-on-launch scanner for non-terminal `UploadJobEntity` rows
- [ ] Implement staged-file reaper (>72 h) on launch
- [ ] Server-side multipart flow: `POST /v1/uploads` returns `{ mode: "multipart", ... }` when `size > 100 MB`
- [ ] Implement R2 multipart initiate, part-presign, and complete routes
- [ ] Client multipart orchestration with max 3 in-flight parts
- [ ] Per-part retry (does not restart the whole upload)
- [ ] Flesh out `services/multipartSweeper.ts` — `AbortMultipartUpload` on uploads older than 7 days
- [ ] Reconciler hardening: housekeeping pass that hard-deletes `upload_job` rows in terminal states older than 30 days
- [ ] Reconciler hardening: sampled HEAD probe on assets past `delete_after` marks them deleted without a duplicate R2 call
- [ ] Deletion retry observability: per-attempt log line with `attempts`, `scheduled_for`, `last_error`; alert when `deletion_status='failed'` is reached
- [ ] Pager integration: structured log line at `error` level with `code: "deletion_terminal_failure"` routed to ops
- [ ] Abuse-report endpoint `POST /v1/report/:token` with heavy rate limiting
- [ ] Ops takedown path: `POST /v1/links/:token/revoke` with `X-Ops-Key` header accepted by auth middleware
- [ ] 200-job soak: zero duplicate tokens, zero stuck jobs, zero objects still live 2 hours past `deleteAfter`
- [ ] 500 MB video passes end-to-end with chaotic network

## M9 — Tests + release

- [ ] Fill missing unit tests (target 80% on `FastSharedCore` and `backend/src/`)
- [ ] Fill missing XCUITest coverage for iOS and macOS happy paths, countdown states, and revoke flow
- [ ] Opt-in crash reporting integration (MetricKit + a minimal self-hosted sink)
- [ ] App Store privacy labels drafted and reviewed (ephemeral storage disclosure)
- [ ] Privacy policy live at `https://fastsha.red/privacy`, referencing the deletion guarantee
- [ ] Marketing landing page live at `https://fastsha.red`
- [ ] App icon assets final for all platforms
- [ ] Submit 1.0 build to App Review
- [ ] Public TestFlight open
- [ ] Launch post drafted
