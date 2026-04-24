# Security

Threats, mitigations, and the reasoning behind each. Paired with [Backend](./backend.md) and [Upload flow](./upload-flow.md).

## Anonymous bearer model

FastShared issues temporary anonymous links. The security posture follows from that choice:

- **The token IS the credential.** 22 characters of base62 (~131 bits entropy). Anyone with the token can fetch the file until it expires or is revoked. There is no recipient auth.
- **DB-backed revocation.** Unlike a bare signed-R2 URL (which is self-verifying and cannot be revoked mid-life), our resolve route hits the DB on every `/s/:token` call. This gives us:
  - Instant revoke via `POST /v1/links/:token/revoke`.
  - Mid-life expiry at `expires_at` (410 Gone once past it).
  - A hook for future per-link policy (password, max-downloads, geo gates).
- **Worker-streamed downloads.** `/s/:token` resolves the DB row and streams the object from the private R2 bucket through the Worker. The browser never receives a raw R2 read URL.
- **No permanent public URLs.** The R2 bucket is private; there is no public hostname, no public bucket ACL, no direct-access path at all.
- **Every upload has a `delete_after`.** Storage is always bounded. An abandoned incident therefore has a worst-case lifetime of 90 days (R2 lifecycle safety net).

Rejected alternatives (so we do not revisit them):

- Direct public R2 URL — permanent exposure, no revoke, no per-link policy hooks.
- Signed R2 URL returned directly to the client — leak-while-valid for the full TTL with no way to invalidate.
- Raw R2 signed GET on resolve — lower Worker work per download, but exposes an extra bearer URL and makes per-link policy harder to enforce consistently.

## Threat model summary

We care about three adversaries:

- **Abusers.** People who try to use FastShared as free CDN for disallowed content, exhaust rate limits, or drain R2 budget.
- **Snoopers.** People who try to enumerate tokens, scrape buckets, or obtain tokens belonging to someone else.
- **Lost devices.** An unlocked device that ends up with someone other than its owner.

We do not currently threat-model a fully compromised Apple device or a malicious Cloudflare account owner.

## Authentication

Two distinct trust surfaces.

### Owner API (authenticated)

`/v1/*` except `/v1/devices` and `/v1/report/:token`. This surface owns upload, history, and revoke.

- **Device tokens.** 32 bytes of CSPRNG, base64url. Minted by `POST /v1/devices` on first launch; no email, no user interaction.
- **Token storage.** Client stores the token in Keychain with the configured `KEYCHAIN_ACCESS_GROUP` (for production, `$(AppIdentifierPrefix)dev.kindrazki.fastshared`) and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. On first launch after the hotfix, the client migrates any legacy App Group `UserDefaults` token into Keychain, deletes the legacy copy, and does not keep a permanent UserDefaults fallback.
- **Server storage.** Only `HMAC-SHA256(DEVICE_TOKEN_PEPPER, token)` is persisted on the `device` row. Raw tokens are never logged.
- **Rotation.** Supported API-side via `POST /v1/devices/:id/rotate` (post-MVP). On rotation, old hash is invalidated atomically; the new token is returned once and immediately persisted.
- **Optional Apple identity.** Sign in with Apple can bind purchases and future cross-device flows to `apple_user_id`; anonymous device-token operation remains supported.
- **Lifecycle.** Tokens live as long as the device row exists. A user "signing out" (post-MVP) deletes the device row and the token is rejected on next request.

### Resolve route (unauthenticated)

`/s/:token` is anonymous. The route uses the URL token as a bearer secret and does not accept any `Authorization` header. Protections live entirely in rate limiting, short signed-URL TTL, and response headers; see below.

## Resolve-route hardening

Every `/s/:token` response — 302, 410, or 404 — carries:

- `Cache-Control: no-store` — no intermediary caching of redirects or error bodies.
- `X-Robots-Tag: noindex, nofollow` — keep tokens out of search indices even if someone leaks them into the public web.
- `Referrer-Policy: no-referrer` — so the destination R2 host never learns the token that led to it.

Additional levers:

- **Private R2 reads.** Downloads are served by the Worker from a private R2 object after DB validation, so leaked link tokens remain the only bearer secret for the resolve route.
- **Per-IP rate limit.** 60 requests/min. Catches a single-source enumeration.
- **Per-token rate limit.** 300 requests/min. Catches bulk fan-out (one token bounced through many IPs) while tolerating legitimate link-preview fan-out from messaging apps.
- **DB-gated.** The handler loads the row, checks `link_status`, `expires_at`, and `asset.deleted_at`. Any mismatch returns `410 Gone` with a `reason` of `expired`, `revoked`, or `deleted`. Unknown tokens return `404` (indistinguishable from random-guess lookups to an attacker).

## Token hygiene

- **Entropy.** 22 characters of base62 = 62^22 ≈ 2^131 values. At the 300 req/min/token ceiling, brute-forcing a specific token requires ~10^30 years. Enumeration is likewise infeasible at 60 req/min/IP.
- **Generation.** `crypto.getRandomValues(new Uint8Array(32))` → base62 → truncate to 22 chars.
- **Collision policy.** Reserve in `TOKEN_RESERVATIONS` KV for 60 s; insert with a `UNIQUE` index; on conflict regenerate. Realistic collision probability at our expected volume is effectively zero; the policy is defensive.
- **Logging.** Tokens are **never logged in cleartext**. The logger recursively redacts device IDs, share tokens, bearer tokens, storage keys, asset IDs, and App Store transaction IDs before serialization. The full share token lives only in the DB `share_link.token` column, in the client's SwiftData store, and briefly in URL handlers.
- **Storage on device.** The token is not a secret in the traditional Keychain sense; it lives in SwiftData alongside the rest of the share metadata and is displayed/copied as part of normal UI. The device token (owner API) is the true secret and lives in Keychain.

## Transport security

- TLS 1.3 everywhere, enforced by Cloudflare.
- HSTS with `max-age=31536000; includeSubDomains; preload` on `fastsha.red` and `api.fastsha.red`.
- No `http://` fallbacks anywhere in the client.
- The Apple client pins the Cloudflare certificate roots by default (system trust); pinning specific leaf certs is not needed because we use Cloudflare-managed certs that rotate.

## Input validation

- **Server.** Every route's body, query, and params are validated with `zod`. Invalid requests get `400` with an RFC 7807 body — never a stack trace.
- **Client.** Before enqueueing, the extension checks the `UTType` against an allowlist and rejects anything unknown. It also clamps `customTtlSeconds` to `[300, 2592000]` before hitting the network; the server re-clamps authoritatively.

## MIME / content-type allowlist

Accepted top-level types in MVP:

- `image/*`
- `video/*`
- `application/pdf`
- `application/zip`
- `text/plain`, `text/markdown`

Anything else is rejected with `415 unsupported-media-type` at `POST /v1/uploads`. The list is held in `backend/src/policy/mime.ts` and mirrored in `FastSharedCore/Policy/MIME.swift`.

## Size caps

| Tier | Cap | Retention | Notes |
| --- | --- | --- | --- |
| Free | 100 MB/file | 24 h | 3 uploads/day, Cloud Sync disabled |
| Pro | 2 GB/file | 30 days | Unlimited uploads, Cloud Sync enabled |
| Beta allowlist | Server configured | Server configured | Only for explicit Apple user IDs in secure env allowlists |

The backend is the source of truth for caps. The Apple client mirrors the defaults for local UX, but presign and batch presign enforce the server caps. Multipart is used for larger uploads; single PUT is limited to the server's multipart threshold.

## Rate limiting

- **Per device (owner API).** `60 uploads/hour`, `600 history reads/hour`, `10 devices/day` (last measured at the IP of the issuing call).
- **Per IP, unauthenticated routes.** `120/hour` on `POST /v1/devices`; `60/min` on `/s/:token`.
- **Per token, resolve route.** `300/min`. Whichever of the two resolve buckets trips first returns `429`.
- **Response.** `429` with `Retry-After` and RFC 7807 body, `type = https://fastsha.red/errors/rate-limited`.
- Implementation: KV now, with token/device-derived keys stored as HMAC digests using `DEVICE_TOKEN_PEPPER`; Durable Object per-token upgrade once measured latency or atomicity requires it.

## Abuse prevention

- **sha256 blocklist hook.** `POST /v1/uploads` consults a blocklist keyed by sha256; lookups are in KV so they are free in the hot path. The dedup lookup restricts to live assets, so a tombstoned hash will not be silently re-shared.
- **`/v1/report/:token`.** Unauthenticated endpoint, heavily rate-limited. In MVP it stores a report row and returns 202; review is manual. The reported token stays live until an operator acts; reviewers can call revoke.
- **Takedowns.** Operator calls `POST /v1/links/:token/revoke` with an ops-only `X-Ops-Key` header (auth middleware accepts this as an authorization path). Revoke schedules immediate deletion and the object is reaped within a minute.

## Secrets management

- **Server.** All secrets injected via `wrangler secret put`. Never in `wrangler.toml`, never in repo. CI deploy is gated behind a GitHub environment with required reviewers.
- **Client.** Device token only in Keychain. Share tokens in SwiftData. Build-time configuration (API host, short link host) is in `xcconfig` files in `apple/Config/`; these are public and hold no secrets.
- **Logging.** The logger redacts known sensitive fields recursively; there is no "dump request" mode in production. Tokens (share and device), storage keys, asset IDs, and App Store transaction IDs are redacted at the logger layer, not at call sites.

## App Group and extension data safety

- The staging directory and SwiftData store are in the App Group container, which is sandboxed to the team and gated by device lock state.
- Staging files are `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` equivalent at the filesystem level: after first unlock, until reboot, they are readable only by app and extension.
- Files older than 72 h in staging are reaped on every app launch and on extension start to minimize the footprint.

## R2 access strategy

- **Writes are presigned.** Upload clients receive short-lived R2 PUT URLs after API authentication, cap checks, and token reservation.
- **Reads are proxied by the Worker.** The resolve route validates token state, expiry, revocation, and asset state before streaming bytes from private R2. This keeps future password prompts, download-count enforcement, and abuse controls on the same path as today's downloads.
- **Why not a public bucket?** A public bucket removes all per-link policy options (expiry, revoke, abuse-takedown, future password-protection). A private bucket plus Worker resolve keeps real enforcement levers without exposing raw object keys.

## Future hardening

- **Password-protected links.** The `share_link` schema already carries enough metadata to gate a redirect on a form; a post-MVP deploy wires up a password column + a minimal HTML challenge page.
- **Max-download count.** `share_link.max_access_count` is already present (null in MVP); the resolve handler will 410 once `access_count >= max_access_count`. Hook exists; UI does not.
- **sha256 blocklist.** KV lookup already present on upload; operator tooling to populate it comes post-MVP.
- **`/report/:token`.** MVP stores rows, review is manual. Post-MVP adds an ops dashboard.
- **Geographic gates.** Cloudflare edge carries country/region data. Post-MVP adds an allow/deny list per link.
- **Per-link download policy.** Password prompts, max-download enforcement, and manual expiry can be layered onto the existing Worker-streamed resolve path.
- **CSAM scanning.** Integrate a scanner (e.g. PhotoDNA via a partner) at complete-time against `image/*`. Requires KYC with the vendor; out of scope for MVP.
- **Expanded account binding.** Use Sign in with Apple plus passkeys for cross-device history and loss-of-device recovery.
- **2FA** for any future admin or non-Apple account path.
- **Bucket-level encryption keys** managed by us rather than Cloudflare-managed — increases key hygiene burden; revisit once we have compliance customers.
