# FastShared — product backlog for the "publications" plan

Companion to `mrr-plan.md`. The order below is the build order. Hour estimates assume one founder at about 10 h/week and are not measured. "Done" means verified by a running test or a real-device check, not by a passing build.

The **sellable slice** is P0 plus P1, about 124 h or roughly 12 weeks. P2 starts only after the first paying customer.

---

## P0 — launch blockers

### P0-a. Isolate user content from the main domain (~20 h)

**Why.** Publishing user HTML means hosting active content. It must never run on `fastsha.red`, where the site, the short links and the brand reputation live. If a browser safety list flags the main domain, every customer link breaks with it.

**Scope:**
- Serve user-provided bytes from a dedicated origin (for example `<id>.fastshared.site`), with no cookies and its own TLS. Keep `fastsha.red` for the app, the preview chrome and redirects.
- Add a strict `Content-Security-Policy`, with `sandbox` on raw responses of active types (HTML, SVG, XML) until the isolated origin is live.
- Add an abuse report link on every hosted page, an owner-side takedown, and an admin suspend switch.

**Files:**
- `backend/src/lib/sizeLimits.ts` (allowed types)
- `backend/src/routes/redirect.ts` (raw and download handlers, `applySecurityHeaders`)
- `backend/wrangler.toml` (routes and hosts)

**Done when:**
- An uploaded HTML test page cannot execute script on `fastsha.red`.
- A report disables the link within one request cycle.

### P0-b. Reliable "opened" alerts (~8 h)

**Why.** Today the preview page schedules the access side effect, which includes the APNs push, for every HTML-accepting request (`backend/src/routes/redirect.ts:141-147`). Link-unfurl bots are deliberately served the preview so that Open Graph cards render (`:364-388`). So pasting a link into WhatsApp or Slack fires a false "opened" alert. iMessage previews are also not in the unfurler list (`:371-384`).

**Scope:**
- Never notify for unfurler or automated user agents.
- Count an open only from a first-party beacon fired by the rendered page, deduplicated per visitor and version.
- Deliver the alert to iOS (APNs, existing), to Mac (new) and by email as a fallback for users without the app.
- Copy says "Opened in a browser", not "Client opened", until recipient verification exists (P2).

**Files:**
- `backend/src/routes/redirect.ts` (`scheduleAccessSideEffects`, `isAutomatedClient`)
- `backend/src/services/apns.ts`
- `apple/FastSharedShareExt/ShareRootView.swift:471-484` (macOS currently hides the toggle)

**Done when:** a matrix test passes, with zero alerts for each unfurler and exactly one alert for a real browser open.

| Paste into | Alerts expected |
|---|---|
| WhatsApp | 0 |
| Slack | 0 |
| iMessage | 0 |
| Telegram | 0 |
| LinkedIn | 0 |
| Real browser open | 1 |

---

## P1 — sellable slice

### P1-a. Publications: a durable entity separate from `/s/` (~38 h)

**Why.** The current model requires an expiry: `share_link.expires_at`, and `asset.delete_after` at `backend/src/db/schema.ts:92`. Custom TTL caps at 30 days (`backend/src/lib/retention.ts:10`). On top of that, the bucket is meant to carry a lifecycle rule that deletes objects after 90 days (`backend/wrangler.toml:1-5`), which would silently delete paid content.

**Scope:**
- New `publication` and `publication_version` tables with a stable slug, an owner (user, not device), a status, a quota, and `expires_at` that is nullable only for an active Pro account.
- Store publications under their own bucket or prefix, with no age-based lifecycle rule.
- A sweeper that ties lifetime to the subscription: Free expires after 7 days; cancelling Pro starts 30 days of notice and export, then deletion. Notice goes by email and in the app.
- Revoke at any time. The existing `/s/` behaviour stays unchanged.

**Files:**
- `backend/src/db/schema.ts`
- `backend/drizzle/*` (migration)
- `backend/src/lib/retention.ts`
- `backend/src/services/deletion.ts`
- `backend/src/services/r2.ts`

**Done when:**
- A Free publication is unreachable after 7 days.
- A cancelled Pro publication stays reachable for 30 days, then its R2 objects are gone.
- An integration test covers both paths.

### P1-b. Publish HTML, ZIP and PDF as a site (~32 h)

**Why.** AI tools output multi-file HTML (CSS, JS and assets). Today the CLI zips a folder into one file (`cli/src/stage.ts:44-68`) and the server stores it as an opaque archive.

**Scope:**
- Server-side unpack of the ZIP on the isolated origin, with these limits:
  - a file count cap;
  - an uncompressed size cap;
  - a compression-ratio cap (zip bomb protection);
  - path traversal rejection;
  - an `index.html` resolution rule.
- PDFs render in the browser viewer.
- A web uploader with drag-and-drop (new page under `web/src/pages/`) that needs no app install.
- CLI: `fastshared publish ./dist`. It prints a stable URL; `--update <slug>` pushes a new version to the same URL.

**Files:**
- `cli/src/stage.ts`
- `cli/src/cli.ts`
- `backend/src/routes/uploads.ts`
- new `backend/src/routes/publications.ts`
- `web/src/pages/`

**Done when:**
- A Vite build and a Playwright HTML report both load with relative assets.
- A malicious ZIP (traversal, bomb) is rejected.
- `--update` keeps the URL and creates version 2.

### P1-c. Web billing (~26 h)

**Why.** Customers who never install the iOS app need to pay on the web. Web purchases must not depend on StoreKit.

**Scope:**
- Checkout through Stripe, or through a merchant of record (Paddle, Polar or Lemon Squeezy) to avoid handling foreign sales tax. The provider choice is the founder's (tax and Brazilian entity).
- An idempotent webhook.
- A `web_subscription` entitlement merged with the existing IAP entitlement in `/v1/me`.
- A customer portal link.

**Files:**
- `web/src/pages/pricing.astro`
- new `backend/src/routes/billing.ts`
- `backend/src/db/schema.ts:269-299` (`subscription`)
- `backend/src/routes/me.ts`

**Done when:**
- A test-mode purchase flips the entitlement within one webhook.
- A refund or cancellation starts the 30-day notice.
- Replayed webhooks are no-ops.

---

## P2 — after the first paying customer

### P2-a. Control (~26 h)

- Same-URL versions with a history view.
- Password protection: the schema already has `visibility = 'password'` and `password_hash` (`backend/src/db/schema.ts:127-129`), but resolve returns 501 (`backend/src/routes/redirect.ts:122-130`).
- Per-version view analytics.
- Optional verified recipient, using an email magic link before viewing, only if pilots ask for it.

### P2-b. MCP server (~6 h)

A thin wrapper over the CLI, with `publish`, `update`, `revoke` and `list` tools. List it in the official MCP registry.

### P2-c. Mobile entry test (~8 h)

Build a matrix of exports from Claude, ChatGPT and Files into the share extension (`apple/FastSharedShareExt/ShareViewController.swift:139-176`) on iPhone, iPad and Mac. Market it only if HTML and PDF pass.

---

## Explicitly not in this cycle

- A Team plan.
- Custom domains.
- Changes to the App Store tier prices.
- Tightening the free tier of the `/s/` app.
- Setapp.
- Paid acquisition.
