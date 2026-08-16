# FastShared — Hacker News Show HN

Show HN guidelines: self-contained, specific, no marketing verbiage, link to
something people can actually try. HN commenters will smell fluff in one
beat.

Post at **8:00–9:00 ET on a weekday**. Avoid Mondays (front page churns
fast), avoid Fridays (weekend dead zone). Tuesday or Wednesday morning is the
sweet spot.

---

## Title

```
Show HN: FastShared – temporary share links for iPhone, iPad and Mac
```

(69 chars — HN title limit is 80.)

Notes on the title shape:

- `Show HN:` prefix is mandatory for the Show HN category.
- Em-dash (` – `) instead of colon avoids the HN auto-dedupe heuristic that
  collapses `Show HN: X: Y` titles.
- No superlatives. No "finally", no "simple", no "beautiful". These get
  flamed on HN.
- Platforms listed explicitly so the comment section doesn't open with "is
  this only for X?"

---

## Body (≤200 words)

Note — repo is private at launch. Only the landing and App Store links are
public.

```
FastShared is a native iOS / iPadOS / macOS utility I built to collapse the
everyday "share a file" chore into one gesture. Pick any file from any app,
pick how long the link should live, and the short URL is already on your
clipboard before the upload finishes.

Every link expires by design (default 24 h, custom 5 min – 30 d). When the
window closes the link returns 410 Gone and the object is hard-deleted from
a private Cloudflare R2 bucket within hours. No soft-delete, no recovery,
no lingering.

Stack: SwiftUI + SwiftData on the Apple side, background URLSession uploads
so the share extension releases in ~200 ms. Backend is Hono on Cloudflare
Workers, Neon Postgres for metadata, KV for rate limits, three cron
triggers for deletion and reconciliation.

Tokens are 22 chars of base62 (~131 bits). The link is the credential;
there are no accounts. Resolve route signs a 60 s R2 GET and 302-redirects;
noindex + no-referrer + no-store on every response.

Landing (with the architecture writeup): https://fastsha.red
App Store: https://apps.apple.com/app/idXXXXXXXXX

Feedback welcome. Repo is private for now; will open once I clean up the
migration history.
```

(196 words)

---

## Standby responses — 3 likely questions

### Q1 — "What's the business model? Is this going to enshittify?"

```
Fair question. Free for the entire launch window; after that a one-time
unlock (not a subscription) for higher retention ceilings and larger files.
No analytics SDKs, no ads, no telemetry beyond Cloudflare request logs for
rate limiting and debug. The server components cost roughly [insert real
monthly number at launch] and a one-time unlock is enough to cover that at
low scale. I'll publish the actual infrastructure cost breakdown once I've
seen a full month of real usage.

If the economics stop working I will shut the service down cleanly rather
than change the posture. The app is small enough on purpose that an
independent fork could keep running it.
```

### Q2 — "Why not just use \<WeTransfer / Dropbox Transfer / Firefox Send /
signed S3 URL / Tailscale / rsync / a text file on a gist\>?"

```
Short answers:

— WeTransfer / Dropbox Transfer: great for large-file workflows; they do
permanent-link-with-paywall and live on a web page the recipient has to
visit. FastShared is a share-sheet action that produces a clipboard-ready
short URL. Different ergonomics, different target.

— Firefox Send: RIP, and also RIP client-side encryption for this use case.
FastShared does not do client-side E2EE — files are encrypted at rest by R2
but the server can read them in principle. I decided against E2EE for v1.0
because it would block future features like takedown and CSAM scanning; I
think that's the right trade-off for this product, but I understand if it's
a dealbreaker for some.

— Signed S3 URLs directly: no revoke, no mid-life expiry, no per-link
policy hooks. The resolve indirection we use exists specifically to make
revoke real.

— Tailscale / ssh / text-file-on-a-gist: perfect for technical recipients
with accounts; fails at "my mom's iPad".
```

### Q3 — "How do you prevent abuse? What's the CSAM / illegal-content story?"

```
Honest answer: at v1.0, abuse prevention is reactive, not proactive.

Mechanical controls: per-device rate limits (60 uploads/hour), per-IP and
per-token rate limits on the resolve route, a sha256 blocklist hook in the
upload pipeline, size caps by type (50 MB for images, 2 GB for video,
100 MB for other), and a MIME allowlist. Every file has a delete_after, so
any incident has a bounded blast radius — 90 days max via an R2 lifecycle
rule as a safety net.

/report/:token is public and heavily rate-limited; reports land in a
queue and I review them manually. Revoke is one operator call and the
object is reaped within a minute.

CSAM scanning is not in v1.0. It requires KYC with a partner (e.g.
PhotoDNA) and the vendor onboarding timeline is months. It's on the
post-MVP roadmap, documented in /docs/architecture/security.md. If the app
is used meaningfully I will pull this forward. I take this seriously —
ephemeral is not a license for hosting anything.

Full threat-model writeup is in the security doc linked above (will open
when the repo opens).
```

---

## Do / don't for the thread itself

- **Do** reply to every substantive question within the first 2 hours.
- **Do** concede when someone is right. HN rewards intellectual honesty.
- **Do** link to the docs (security, product overview) where they answer
  better than a fresh comment.
- **Don't** post "thanks!" or "great question!" as standalone replies — they
  get greyed out and make the thread look astroturfed.
- **Don't** ask friends to upvote from the thread. Ballot-stuffing is
  visible to HN's modlog and will drop you off the front page within an hour.
- **Don't** post links to Product Hunt or Twitter in the HN thread itself —
  cross-linking is fine on the socials, not fine in-thread.
