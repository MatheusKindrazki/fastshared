# Publications — technical design (wave 2)

Companion to `mrr-plan.md` and `mrr-backlog.md`. This design fixes the contracts so that backend, CLI and web work can proceed in parallel. Decisions marked **(founder)** were made by the founder on 2026-11-15.

## Decisions

| Topic | Decision |
|---|---|
| Isolation | **(founder)** Subdomains of `fastsha.red`, not a separate registrable domain. |
| Payments | **(founder)** A merchant of record. Paddle Billing is selected: Brazil is not on Paddle's unsupported-seller list ([Paddle help](https://www.paddle.com/help/start/intro-to-paddle/which-countries-are-supported-by-paddle)), and Paddle supports Pix. Polar is excluded because Brazil is not in its payout list ([Polar](https://polar.sh/docs/merchant-of-record/supported-countries)). |
| Ownership | Publications belong to a **user**, not a device. Free web publishing may start anonymous (a `web` device), but Pro always requires a user. |

## Hosts and origins

Each publication gets its **own origin**: `https://p-<slug>.fastsha.red`.

**Why per-publication origins:**
- A shared origin such as `u.fastsha.red/p/<slug>/` would let one customer's script read another customer's `localStorage` and make same-origin requests to their files.
- First-level wildcard certificates (`*.fastsha.red`) are covered by Cloudflare Universal SSL. A second-level wildcard (`*.u.fastsha.red`) would need Advanced Certificate Manager.

**Slug rules:**
- 10 random base32 characters, lowercase.
- Never user-chosen in this cycle.
- The `p-` prefix keeps them apart from `api`, `www` and future app hosts.

**Hard rule:** the app must never set a cookie with `Domain=.fastsha.red`. `fastsha.red` is not on the Public Suffix List, so any publication could set or overwrite such cookies. A test asserts that no response sets a domain-wide cookie. If the app ever needs cookies, publications move to a dedicated registrable domain. The host is configuration (`PUBLICATION_HOST_SUFFIX`), so the move is an environment change plus a redirect.

The existing `/s/` raw bytes keep using `USER_CONTENT_HOST` from P0-a.

## Data model (Postgres, Drizzle)

**`publication`**
- `id` uuid pk
- `slug` text unique
- `owner_user_id` uuid fk user, nullable for anonymous Free
- `owner_device_id` uuid fk device
- `title` text
- `status`: active | expired | revoked | suspended | deleted
- `current_version_id` uuid
- `expires_at` timestamptz, nullable only while the owner has an active Pro entitlement
- `notify_on_open` bool, default true
- `created_at`, `updated_at`, `deleted_at`

**`publication_version`**
- `id` uuid pk
- `publication_id` fk
- `number` int (unique per publication)
- `kind`: site | pdf | file
- `entry_path` text
- `file_count` int
- `total_bytes` bigint
- `created_at`

**`publication_file`**
- `version_id` fk
- `path` text
- `storage_key` text
- `content_type` text
- `size_bytes` bigint
- Primary key: (`version_id`, `path`)

**`publication_open`**
- `id`
- `publication_id`
- `version_id`
- `visitor_hash`: sha256 of visitor id and pepper
- `opened_at`
- One row per (publication, version, visitor) per 24 h.

**`entitlement`**
- `id`
- `user_id`
- `source`: iap | paddle
- `external_id`
- `status`: active | past_due | canceled | expired
- `current_period_end`
- `created_at`, `updated_at`
- `/v1/me` returns `isPro = any(active entitlement)`. The existing `subscription` table (IAP) stays the source for `source=iap`; this table unifies both.

## Storage

- New R2 bucket `fastshared-publications`, with **no age-based lifecycle rule**. Deletion is application-driven only.
- Keys follow `pub/<publication_id>/v<number>/<path>`.
- The existing `fastshared` bucket and its rules are untouched.

## API contract (backend implements, CLI and web consume)

All routes are under `https://api.fastsha.red`. Auth is the existing bearer device token. Pro checks go through the `entitlement` table.

| Method and path | Purpose |
|---|---|
| `POST /v1/publications` | Body: `{ title?, kind: "site" \| "pdf" \| "file", filename, sizeBytes, contentType }`. Returns: `{ id, slug, url, version: 1, upload: { url, method: "PUT", headers } }`. A site is uploaded as one ZIP. |
| `POST /v1/publications/:id/versions` | Same body. Returns a new upload slot; the URL stays the same. **Pro only.** On Free it returns 402 with `{ upgradeUrl }`. |
| `POST /v1/publications/:id/versions/:n/complete` | The server verifies the object and unpacks the ZIP for `kind=site`. It then sets `current_version_id`. Returns `{ url, version, fileCount, totalBytes }` or a problem+json with an `unpack_error` code. |
| `GET /v1/publications` | The owner's publications with status, current version, `expires_at`, and opens in the last 7 days. |
| `POST /v1/publications/:id/revoke` | Immediate. Schedules deletion. |
| `GET /v1/publications/:id/opens` | Opens per version: count and last-opened time. |

**Free limits:**
- 1 active publication.
- 25 MB upload.
- 7-day expiry.
- 3 open alerts per publication.
- Banner injected.

**Pro limits:**
- 2 GB total storage.
- 250 MB per upload.
- No expiry while active.
- Same-URL versions.
- Unlimited alerts.
- No banner.

Limit values live in `backend/src/lib/tierCaps.ts`, next to the existing caps.

## ZIP unpacking (Worker)

- Stream the ZIP from R2 with `fflate` (pure JS, runs in Workers) and write each entry to R2. Never hold the whole archive in memory. Workers have a 128 MB memory limit.
- **Reject the whole ZIP** when any of these hold:
  - more than 2,000 entries;
  - uncompressed total above the tier cap;
  - a single file above 100 MB;
  - a compression ratio above 100:1 for any entry or in total;
  - a path that is absolute, contains `..` or backslashes, or is a symlink or device entry;
  - duplicate normalized paths.
- **Entry resolution:**
  - `index.html` at the root wins.
  - Otherwise, a single top-level folder that contains `index.html` is unwrapped.
  - Otherwise, if there is exactly one `.html` file, it becomes the entry.
  - Otherwise the result is `unpack_error: no_entry`.
- Content type comes from the extension through a fixed allowlist; anything unknown is `application/octet-stream` served as an attachment.
- If unpacking risks exceeding a single request's CPU budget, move it to a Cloudflare Queue consumer. The `complete` call then returns 202 and the CLI polls.

## Serving `p-<slug>.fastsha.red`

- Route by `Host`. Load the publication and its current version (cached in KV for 60 s, invalidated on new version or revoke).
- For an expired, revoked or suspended publication, return 410 with a neutral page. That page carries no customer content.
- Headers on every file:
  - `Content-Security-Policy: sandbox allow-scripts allow-same-origin allow-popups allow-downloads; frame-ancestors 'none'`. `allow-same-origin` is safe here because the origin is unique per publication. **No `allow-forms`**, which removes credential-harvesting forms. Revisit only for Pro if pilots need forms.
  - `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Robots-Tag: noindex`.
- HTML responses, entry page and others, are rewritten on the way out with `HTMLRewriter`:
  - an open beacon script, the same contract as P0-b (`POST /opened` on the publication origin, visible for at least 1.5 s, visitor id in `localStorage`, dedupe 24 h);
  - on Free, a fixed footer badge: "Hosted with FastShared · Report". This is the growth loop and the abuse escape hatch.
- PDFs are served inline. The browser viewer renders them, and the beacon is not possible there. For PDFs, an open counts at most once per visitor IP hash per 24 h, from a GET with a browser UA and `Sec-Fetch-Dest: document`. The alert copy says "PDF opened" so the user knows it is less certain.

## Lifecycle (cron, existing scheduler)

- Free: `expires_at = created_at + 7 days`. At expiry, set status to expired, and 24 h later delete the R2 prefix.
- Pro becomes active: clear `expires_at` on all the user's publications.
- Pro canceled or expired:
  - set `expires_at = now + 30 days` on all the user's publications;
  - email the user, then send a reminder at day 23;
  - on expiry, follow the Free path.
- Revoke: delete the R2 prefix immediately through the existing deletion job pattern (`backend/src/services/deletion.ts`).

## Billing (Paddle)

- Products: Pro Monthly at US$15 and Pro Annual at US$144. Prices live in Paddle; the app only knows the price ids from environment variables.
- Checkout: Paddle.js overlay on `web/pricing`, with `customData.userId`. A user must be signed in first.
- Webhooks at `POST /v1/billing/paddle/webhook`:
  - verify the `Paddle-Signature` HMAC with `PADDLE_WEBHOOK_SECRET`;
  - process idempotently by `event_id`;
  - handle `subscription.created`, `subscription.updated`, `subscription.canceled`, `subscription.past_due` and `transaction.completed`;
  - upsert `entitlement` (source=paddle).
- Customer portal: a link from the account page through the Paddle customer portal API.

**Founder actions:** create the Paddle account, pass domain and website review (needs live pricing, terms, privacy and refund pages), and create the products. Price ids and secrets go into `wrangler secret`.

## Web sign-in

- Pro and the web dashboard need a user on the web. Use an **email magic link**: `POST /v1/auth/email/start` and `GET /v1/auth/email/verify?token=`. The verify step issues a device token for platform `web`, stored in `localStorage`, consistent with the existing bearer model and with no cookies.
- It needs a transactional email sender. Existing note: `docs/ops/email-dns-setup.md`. The provider is the founder's choice; the default is Resend.
- Sign in with Apple JS can come later. Existing iOS and Mac users link through the same email when Apple shares it.

## Work split (wave 2)

| Stream | Owner | Depends on |
|---|---|---|
| W2-a: schema, storage, publications API, ZIP unpack, `p-` host serving, lifecycle cron | Codex | P0-a and P0-b merged |
| W2-b: CLI `fastshared publish <path> [--update <slug>] [--title]` plus a thin MCP server over the same client (`publish`, `update`, `revoke`, `list`) | Grok | API contract above; mock server in tests |
| W2-c: web uploader (`web/src/pages/publish.astro`, drag-and-drop), dashboard (`web/src/pages/account/*`), pricing page in the new positioning, terms, privacy and refund pages for Paddle review | Grok after W2-b, or Gemini for copy plus Grok for code | Contract above, launch-kit copy |
| W2-d: email magic link plus Paddle billing and entitlement | Codex after W2-a | Founder: Paddle account, email provider |
| Marketing: SEO pages, pilot recruitment, launch kit | Gemini | — |
