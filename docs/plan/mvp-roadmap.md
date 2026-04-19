# MVP roadmap

Scope, milestones, and release plan. The implementation-level to-do list lives in [Implementation checklist](./implementation-checklist.md).

## Scope

- **MVP = M0 through M7.** Ship the core "share a file, get a temporary link" loop across iOS/iPadOS/macOS, including ephemeral-by-default semantics.
- **Post-MVP = M8 and M9** plus the candidates listed at the end of this doc. M8 is reliability hardening, R2 multipart, and deletion-pipeline polish. M9 is the release push: full test coverage, TestFlight polish, app review prep.
- Nothing outside this table is in scope until MVP ships and the team explicitly revisits priorities.

## Milestones

| Milestone | Goal                                | Tasks                                                                                                                                                                                         | Acceptance                                                                                                                        | Risks                                                          | Test strategy                                                           |
| --------- | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------- |
| M0        | Repo, CI, docs                      | Create monorepo layout, `.gitignore`, `.editorconfig`, `.env.example`, Makefile, CI for Apple + backend, full doc set under `docs/`                                                           | Repo clones, CI runs green (apple may be allowed-fail), docs linked from README                                                   | Over-engineering docs that will drift                          | Lint on Markdown links; review                                           |
| M1        | Base SwiftUI app                    | `FastSharedApp` target for iOS/iPadOS/macOS, `FastSharedCore` Swift Package, stub views, `OSLog` subsystem, xcconfig-driven config                                                            | App launches on all platforms, shows an empty history view, build is reproducible via `make ios`                                  | XcodeGen config drift across platforms                         | Build matrix; UI smoke XCUITest                                          |
| M2        | Share Extension                     | `FastSharedShareExt` target, `NSItemProvider` flow, staging to temp (not App Group yet), simple completion stub                                                                               | Extension appears in share sheet, accepts an image/video, exits cleanly                                                           | UTType handling edge cases, large videos                       | Extension unit tests with synthesized providers                          |
| M3        | App Group + shared background       | App Group entitlement on both targets, shared Keychain access group, shared SwiftData store, single background `URLSession` identifier shared between app and extension                      | An upload initiated in the extension completes after the extension exits and is visible in app's history                          | Session identifier collision, entitlement provisioning         | Integration tests with real App Group, kill-the-extension soak           |
| M4        | Backend skeleton                    | Hono app, Wrangler config, `Env` interface, logging middleware, rate limit middleware stub, `POST /v1/devices`, Drizzle schema, Neon connection                                               | `curl POST /v1/devices` returns `{ deviceId, token }`; typecheck + tests green in CI                                              | Neon HTTP driver quirks on Workers, KV setup                   | Unit + in-Worker integration tests                                       |
| **M4.5**  | **Ephemeral lifecycle**             | **Retention policies, token-based share links, deletion + reconciliation crons, revoke endpoint** (see detailed block below)                                                                  | **Token resolves to signed GET <60s; 24h later, R2 object is gone; revoked link returns 410**                                     | **Cron trigger reliability in dev; Neon cold start on deletion worker** | **Unit tests for deletion service with fakes; integration tests for `/s/:token` redirect + 410; soak test with 100 staggered expiries** |
| M5        | R2 upload pipeline                  | `POST /v1/uploads` with presign **carrying `retentionPolicy`**, `POST /v1/uploads/:id/complete` **returning `expiresAt`/`deleteAfter`** with HEAD verification, client ties in, background upload PUT to R2 | A 5 MB PNG shared from iOS ends up in R2 and an `asset` row is written with the correct `delete_after`                            | R2 presign signing quirks, content-length enforcement          | End-to-end harness; flake budget tracked                                 |
| M6        | Token + anonymous resolve + expiry  | 22-char base62 token generator, `share_link` insert in `complete`, `GET /s/:token` anonymous resolve → 302 to 60s signed R2 GET, 410 Gone on expired/revoked/deleted, resolve-route security headers | `curl -I https://fsh.dev/s/<token>` returns 302 to a signed R2 GET; after `expiresAt`, returns 410 Gone                           | Token collisions, cache headers, signed URL leak via Location  | Unit tests on token generator; integration tests on redirect + 410 path  |
| M7        | Upload history                      | `GET /v1/history` paginated (rows carry `expiresAt`/`deleteAfter`/`linkStatus`/`retentionPolicy`/`accessCount`), SwiftData `ShareLinkEntity`, history UI with **tombstone states + countdown badge**, **revoke action in detail view** | User opens app, sees list with live countdown badges, revoke action flips row to `revoked` and recipient gets 410 on next access | SwiftData migration pain, pagination off-by-ones, TimelineView cadence | UI tests; manual checks on both platforms                                |
| M8        | Reliability + multipart             | Implement retry state machine end-to-end, resume-on-launch, staged-file reaper, R2 multipart for >100 MB, **multipart sweeper cron**, **reconciler hardening**, **deletion retries beyond 3 attempts with alerting**, abuse-report stub, ops takedown via revoke | 200-job soak test passes with mixed retentions; a 500 MB video uploads successfully with multipart; abandoned multipart uploads are reaped weekly | Multipart edge cases on flaky networks; deletion pager noise   | Long-running soak, chaos harness, property tests on retry math           |
| M9        | Tests + release                     | Fill unit/integration/UI coverage gaps, App Store privacy labels, crash reporting (opt-in), TestFlight build, marketing page, privacy policy                                                  | 1.0 build submitted to App Review; public beta open                                                                                | App review rejections, privacy label accuracy                  | Full CI pipeline; manual App Review dry-run                              |

## M4.5 — Ephemeral lifecycle (detailed)

**Goal.** Retention policies, token-based share links, deletion + reconciliation crons, revoke endpoint. This milestone makes the schema and the backend ephemeral-by-default. It sits between M4 (backend skeleton) and M5 (upload pipeline) so that by the time real bytes flow in M5, the storage side already knows how to reap them.

**Tasks.**

- Add schema columns and new table via `0001_ephemeral.sql`:
  - Rename `object_key → storage_key`, `slug → token`.
  - `share_link`: `link_status`, `retention_policy`, `expires_at NOT NULL`, `delete_after`, `revoked_at`, `last_accessed_at`, `access_count`, `max_access_count`.
  - `asset`: `delete_after NOT NULL`, `deleted_at`, `deletion_status`, `deletion_attempts`, `deletion_last_error`; swap dedup index to partial live-only.
  - New table `deletion_job` with partial unique index on `(asset_id) WHERE status IN ('pending','running')` and due-queue index on `(scheduled_for) WHERE status = 'pending'`.
  - `upload_job`: `retention_policy`, `custom_ttl_seconds`, extend state check with `deduped` and rename `failed_permanent → failed`.
- Implement `backend/src/services/deletion.ts` — batched `FOR UPDATE SKIP LOCKED LIMIT 50` picker, R2 DELETE, backoff `120 × 2^(attempts-1)s` cap 7200s jitter ±10%, terminal at 8.
- Implement `backend/src/services/reconciliation.ts` — expire stale links, enqueue missing deletion jobs, reset stuck running.
- Implement `backend/src/services/multipartSweeper.ts` — stub in M4.5, fleshed out in M8.
- Add `scheduled` export dispatching by `event.cron`:
  - `*/1 * * * *` → deletion worker.
  - `0 * * * *` → reconciler.
  - `0 3 * * 0` → multipart sweeper.
- Register all three cron triggers in `wrangler.toml` for dev and prod.
- Rewrite `/s/:token` handler: DB-backed lookup, 302 to 60s signed GET, 410 Gone (`code: "link_gone"`, `reason: expired | revoked | deleted`), 404 for unknown. Always emit `Cache-Control: no-store`, `X-Robots-Tag: noindex, nofollow`, `Referrer-Policy: no-referrer`.
- Add per-IP (60/min) and per-token (300/min) rate limit buckets on the resolve route.
- Implement `POST /v1/links/:token/revoke` (owner-only): flip `link_status='revoked'`, `revoked_at=now()`, pull the pending `deletion_job.scheduled_for` forward to `now()`.
- Add retention picker in Share Extension (4 presets, default `oneDay`).
- Add default-retention picker in Settings (Mac + iOS).
- Update client DTOs: `PresignRequest` carries `retentionPolicy` + optional `customTtlSeconds`; `CompleteResponse` carries `token`, `expiresAt`, `deleteAfter`, `linkStatus`, `retentionPolicy`.
- Configure R2 lifecycle rule (90 d expire) via `wrangler r2 bucket lifecycle put`.

**Acceptance.**

- A newly issued token resolves to a signed GET URL with `X-Amz-Expires=60` within 50 ms p95.
- 24 hours after `expiresAt`, the R2 object is gone (HEAD 404) and the asset row has `deleted_at != null`.
- A revoked link returns `410 Gone` with `reason: "revoked"` on the very next request.
- Soak: 100 tokens with staggered expiries, all reach `removed` state inside `expiresAt + 24h + 5min`.

**Risks.**

- **Cron trigger reliability in dev.** Wrangler dev cron support is best-effort; local reproduction requires either `wrangler cron trigger` invocations or the in-process cron simulator. Mitigation: make every scheduled handler directly invokable from a test harness so we never rely on the scheduler in dev.
- **Neon cold start on the deletion worker.** A per-minute worker paying HTTP driver cold-start cost every time is wasteful. Mitigation: picker uses a single round-trip `SELECT … FOR UPDATE SKIP LOCKED LIMIT 50`; if no rows, the worker exits in <10 ms. Watch p95 on CI.
- **Token churn vs KV.** 22-char tokens in `TOKEN_RESERVATIONS` KV with 60 s TTL — expected volume is trivial, but we track the KV ops counter anyway.

**Test strategy.**

- Unit tests for `services/deletion.ts` with faked `{ db, r2 }` — cover happy path, transient retry, terminal failure, stuck-running reset, idempotency via partial unique index.
- Integration tests hit the Worker via `unstable_dev` and run `/s/:token` against a seeded DB: happy 302, 410-on-expired, 410-on-revoked, 410-on-deleted, 404-on-unknown, all three header invariants.
- Soak test: seed 100 share_link rows with `expires_at` uniformly distributed over the next 10 minutes, run the cron 20 times, assert all rows reach `removed`.

## Critical path

M0 → M1 → M2 → M3 is strictly sequential and sits on the critical path; the share extension cannot be validated without App Group plumbing. M4 can run in parallel with M1–M3 once M0 is merged. **M4.5 gates M5** because M5's presign response depends on the retention schema and the ability to compute `expiresAt`/`deleteAfter`. M5 joins the two sides. M6 and M7 can be parallelized between two engineers once M4.5 has merged. M8 and M9 are sequential.

Primary risk clusters:

- **Entitlement provisioning.** App Group, Keychain group, and push-like capabilities all require portal work with a named team id. Start M3's entitlement work on day one of M3 to unblock integration testing.
- **Background `URLSession` under extension exit.** Highest-variance item. Budget a full spike in M3 for reproducing the handoff in a minimal project before wiring it into the main app.
- **Neon HTTP driver on Workers.** Validate connection-per-request and transaction behavior in M4 before building routes on top.
- **Cron trigger lifecycle.** In M4.5, validate all three crons deploy cleanly and that a failing deletion batch does not poison subsequent batches.

## Release plan

- **Internal TestFlight at M7.** Engineers + a handful of power-user friends. Feedback focuses on the core gesture, countdown UI, and the revoke action.
- **Public beta at M8.** Open TestFlight. Reliability is the bar: zero duplicate tokens, zero lost jobs on forced app kill, zero objects still live 2 hours past `deleteAfter`.
- **1.0 at M9.** App Store submission, marketing site, privacy policy, and a short launch post. No feature creep between M8 and M9.

## Post-MVP candidates

- **Max-download count.** Expose the existing `max_access_count` column: resolve handler returns 410 once `access_count >= max_access_count`.
- **Password-protected links.** Add a hashed password column and a minimal HTML challenge page before the 302.
- **Proxy-mode per link.** Opt-in per link to stream bytes through the Worker instead of 302'ing. Enables password prompts mid-stream, per-chunk download-count enforcement, and watermarking. Held back because of Workers CPU limits on large videos.
- **`/report/:token`.** Post-MVP: operator dashboard, triage queue, auto-revoke on N confirmed reports.
- **Geographic gates.** Cloudflare edge carries country info; per-link allow/deny list.
- **One-time links.** `max_access_count = 1` preset in the Share Extension.
- **Custom expiration presets.** User-defined saved presets beyond the four built-ins.
- **Accounts and cross-device history.** Sign in with Apple, bind tokens to an account, sync history across devices.
- **Siri Shortcuts / widget.** Recent links glance, share-from-shortcut with a saved retention.
- **R2 multipart polish.** Parallelism tuning, resumable parts on launch, per-part backoff observability.
- **CSAM scanning.** Integrate a scanner at complete-time for `image/*`.
