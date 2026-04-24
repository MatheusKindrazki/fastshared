# FastShared — Product overview

## Purpose

FastShared collapses the common "share a file" interaction on Apple devices into a single gesture that produces a short, shareable link copied to the clipboard. The product optimizes for the 80% case: a user who wants to hand someone a file via any messaging app without thinking about storage, expiry, or permissions.

FastShared is an **ephemeral tool**: media is always temporary by design. Every share gets a bearer link with a mandatory expiration, after which the underlying object is deleted from storage automatically.

## Target users

- Apple-first power users on iPhone, iPad, and Mac who share files daily (screenshots, PDFs, short videos).
- Teams that currently rely on email attachments, Slack uploads, or ad-hoc Drive links and want something faster.
- Developers and designers who paste screen recordings or bundles into threads.

Not targeted at enterprise compliance buyers. Not targeted at cross-platform power users whose primary device is Android or Windows. Not targeted at users who need permanent hosting — the tool deliberately discards content after its retention window.

## Core user journeys

1. **iOS share sheet**
   1. User opens any app with a file (Photos, Files, a browser, a design tool).
   2. User taps the system share sheet and picks FastShared.
   3. Extension stages the file, user picks a retention policy (default `oneDay`), extension enqueues the upload, and returns control within ~200 ms.
   4. Upload completes in the background; the temporary link is copied to the clipboard and a notification is posted with the countdown ("expires in 23h 59m").

2. **Mac drag and drop**
   1. User drags a file from Finder onto the FastShared dock icon or main window.
   2. App stages the file, applies the default retention from Settings, and starts the upload.
   3. On completion, the temporary link is placed on the Mac pasteboard and a toast is shown.

3. **Recipient opens a valid link**
   1. Someone with the link opens it in any browser, messaging preview, or mail client — no sign-in, no account, no FastShared app required.
   2. `/s/:token` resolves on the edge, validates the DB row, and streams the private R2 object through the Worker.
   3. The recipient downloads or previews the file. The response is not cached and the raw R2 object URL is never exposed.
   4. Once the link passes `expiresAt`, any subsequent access returns `410 Gone`.

4. **History browse**
   1. User opens FastShared.
   2. Recent uploads are shown in reverse chronological order, grouped by day. Each row shows a live countdown badge (green > 6 h, amber ≤ 6 h, red ≤ 30 m, grey `Expired`, grey `Removed`).
   3. Tapping a live row re-copies the link; long-press opens actions (share, open in browser, revoke).

5. **Revoke link**
   1. User opens a history row's detail view and taps **Revoke link** (destructive action).
   2. Client sends `POST /v1/links/:token/revoke`.
   3. Server flips `link_status='revoked'`, schedules an immediate deletion job, and returns 200; client marks the row `revoked` locally.
   4. The next `/s/:token` resolve returns `410 Gone` with `reason: "revoked"`.

## MVP scope

- iOS and iPadOS share extension that uploads, picks a retention policy, and copies a temporary link.
- macOS app with drag-and-drop, `.fileImporter`, and a Command menu for Paste to Upload.
- Shared SwiftData-backed history with tombstones and live countdown.
- Per-device bearer token auth for the owner API (upload, history, revoke).
- Temporary links at `https://fastsha.red/s/<token>`.
- **Default retention = 24 h**, with 1 h / 1 d / 1 w / 1 mo presets and a clamped custom value (300 s … 30 d).
- **Link expires automatically** at `expiresAt`; subsequent access returns `410 Gone`.
- **R2 object is deleted automatically** at `deleteAfter = expiresAt + 24 h` via an app-level deletion cron (R2 lifecycle rule as safety net).
- **Anonymous resolve** at `/s/:token` — DB-gated Worker stream from private R2. No sign-in required for recipients.
- **Revoke link** action flips the link to `revoked` and enqueues immediate deletion.
- Multipart uploads for larger files, with tier caps enforced by the backend.
- Cloudflare R2 private bucket with presigned writes and Worker-streamed reads.
- Deployed Workers backend with Neon Postgres and three cron triggers.

## Tiers (v1.1 Pro launch)

FastShared ships in two tiers:

### Free — acquisition + casual users
- 3 uploads per day.
- 100 MB max file size.
- Up to 24 h retention ceiling.
- Single-device history (SwiftData, local to the device).
- No cross-device sync.
- All the core ephemerality guarantees (private bucket, signed reads,
  no-residue). Free is not a crippled demo — it is a real product for
  people who share occasionally.

### Pro — power users, consultants, Apple ecosystem loyalists
- Unlimited uploads per day.
- 2 GB max file size.
- Up to 30 day retention ceiling.
- Cross-device history sync via iCloud (CloudKit private database).
- Priority support, one-business-day SLA.
- Family Sharing on Lifetime (up to 6 members).

### Why Opt B — iCloud metadata sync, not BYO storage

The decision, already captured in session memory: Pro syncs **metadata
only** through CloudKit's private database — never the file bytes. Files
always live on our R2 bucket with the same ephemeral lifecycle as Free.

Why not Opt A (BYO storage — let Pro users point at their own iCloud /
Dropbox): breaks the ephemerality contract, fragments the abuse model,
blows up the engineering surface. The core value of FastShared is "every
link expires and the file is deleted on schedule"; we can't guarantee that
if the file isn't in our bucket.

Opt B gives the cross-device benefit (history follows you from iPhone to
Mac) without changing where the bytes live. Apple is the sub-processor for
the metadata. We never see it.

### Pricing rationale

- **$2.99 / month.** Impulse-buy ceiling. Under $3 is the threshold for
  "yes, why not" among Apple-ecosystem subscribers; above that, churn
  climbs hard.
- **$19.99 / year.** Equivalent monthly price of $1.67 — a ~44% discount
  vs monthly. Enough to convert the "I'll probably keep using this"
  crowd into an annual commit, which drops support volume and boosts
  retention metrics.
- **$49.99 / Lifetime (Early Access).** PR beat — "pay once for a
  privacy tool" is still rare enough in 2026 to get a headline. Also a
  risk hedge: if the product survives, the average lifetime revenue per
  Lifetime buyer exceeds Annual after ~2.5 years; if it doesn't, we got
  the cash up-front. Family Sharing on Lifetime turns one sale into six
  activations and amplifies word of mouth without re-billing. Early
  Access window is 3 months from launch; after that, Lifetime returns to
  its standard price.

No introductory offers. No free trial. The Free tier is the trial — and
it's generous enough to be honest about it.

## Non-goals (MVP)

- **No permanent hosting.** Every file has a deletion deadline; there is no "keep forever" option.
- **No permanent public URLs.** All links are bearer tokens resolved by the Worker against a private R2 bucket.
- **No account-gated recipient access.** Recipients never sign in. The token is the credential.
- No account-gated recipient access. Optional Sign in with Apple exists for purchases and future account-bound features; cross-device history sync via iCloud (CloudKit private database) ships as a **Pro** feature.
- No custom tokens, folders, or tags.
- No per-link passwords, max-download counts, or geographic gates (hooks exist; not exposed).
- No Android, Windows, or web clients beyond the resolve redirect and the minimal expired-page HTML.
- No direct R2 public buckets; all reads go through the `/s/:token` redirect.
- No multipart uploads in MVP (planned M8).

## Roadmap

| Phase    | Features                                                                                                           |
| -------- | ------------------------------------------------------------------------------------------------------------------ |
| MVP      | Share extension, Mac drop, history with countdown + tombstones, temporary links, retention presets, revoke, deletion cron, single-PUT uploads, device auth |
| v1.1 Pro | Pro tier (Monthly / Annual / Lifetime), unlimited uploads, 2 GB files, 30-day retention, iCloud metadata sync via CloudKit private database, Family Sharing on Lifetime |
| Post-MVP | R2 multipart for files >100 MB, resumable uploads, reliability hardening, password-protected links, max-download count, `/report/:token`, geographic gates |
| Future   | Accounts and SSO, team libraries, CSAM scanning, Siri Shortcuts, watchOS, custom expiration presets, one-time links                                         |

## Product principles

- **Ephemeral by default.** Every share is temporary. The tool refuses to pretend otherwise. This is a feature, not a limitation.
- **Speed over features.** Every addition must preserve the "one gesture, one link" promise.
- **Privacy-first.** All reads go through a 60 s signed URL; tokens are bearer secrets; no analytics SDKs on the client.
- **Apple-native UX.** Use system components (share sheet, SwiftData, URLSession) before custom UI.
- **Evolvable to SaaS.** The schema and API already assume accounts, teams, and per-link policy (password, max-downloads, geo) — even though the MVP does not expose them.
- **No fluff.** No onboarding carousels, no settings screens that do not change behavior, no gratuitous animations.
