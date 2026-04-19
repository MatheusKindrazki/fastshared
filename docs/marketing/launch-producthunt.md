# FastShared — Product Hunt launch kit

Everything needed to launch on Product Hunt. Goal: top 5 on launch day. Post
at 00:01 Pacific, not earlier. PH launch day runs 24h on Pacific time.

---

## Tagline (≤60)

```
Share anything. Get a temporary link. Watch it vanish.
```

(54 / 60)

(Alternate kept in reserve in case PH moderation rejects the above for being
too close to a generic "share anything" claim — unlikely but worth having
ready.)

```
Temporary share links for iPhone, iPad, and Mac.
```

(48 / 60)

---

## Description (≤260)

```
A native Apple utility that turns "share a file" into "get a temporary link on my clipboard" in one gesture. Default 24h. Custom up to 30 days. Every link expires and the file is deleted. No accounts, no folders, no residue. iPhone, iPad, Mac.
```

(243 / 260)

---

## Gallery brief (for the designer)

Product Hunt allows up to 10 gallery assets (images + optionally a video).
Three images are the minimum we ship. Dimensions: **1270×760** for images,
**16:9** for video. All images use the brand palette (ink ground, amber pulse).

### Image 1 — hero / cover

- **What it shows.** The iOS share sheet on an iPhone, with FastShared
  selected, alongside the retention picker (1 h / 24 h / 1 week / 1 month /
  custom). Clipboard toast in the bottom-right of the frame: `fastsha.red/s/
  abc…` and "copied".
- **Headline overlay (JetBrains Mono, tracking 0.1em).** `one gesture · one
  link · one countdown`
- **Why it matters.** This is the thumbnail. It has to convey "what does it
  do" without reading a single word.

### Image 2 — Dynamic Island + Live Activity

- **What it shows.** Three frames stacked vertically (or side-by-side on
  wider compositions): _uploading_ → _copied_ → _expired_. Each frame shows
  the Dynamic Island pill with the appropriate state from the real component
  (`apple/FastSharedLiveActivity/`).
- **Headline overlay.** `watch your upload breathe`
- **Why it matters.** The Live Activity story is our strongest
  Apple-differentiation moment. It reads well in the gallery flyover.

### Image 3 — the ephemeral promise (feature shot)

- **What it shows.** The landing page hero text ("Every link expires. Every
  file is deleted. By design.") rendered at gallery size, with the hero arc
  SVG from the brand kit on the right half — the arc fading into particles,
  a subtle countdown (`23:59:47`) baked in as a watermark at bottom-left.
- **Headline overlay.** (no overlay — the image is already headline-sized
  type)
- **Why it matters.** Anchors the brand concept. People who flick through and
  stop here learn the promise without needing to read the description.

### Optional image 4 — Mac drag-and-drop

- **What it shows.** A Finder file being dragged onto the FastShared Mac
  window, with the Mac toast `Link copied · fastsha.red/s/xyz…`. Menu bar
  visible to anchor it as macOS.
- **Headline overlay.** `also on Mac · drag, drop, paste`

### Optional video — hero arc + share flow

- **Length.** 30 s.
- **Cut.** 0–5s brand reveal (arc animation, wordmark) · 5–15s iPhone share
  flow (share sheet → retention picker → clipboard toast) · 15–22s Mac
  drag-drop · 22–30s wordmark outro with fastsha.red URL.
- **Audio.** None, or a single pulse/ping at the clipboard-copy moment. No
  voiceover. No music track with a vocal hook.

---

## Maker's first comment (≤500 words)

Product Hunt's conventional wisdom: the maker's first comment within the
first 15 minutes. This lives on the thread and gets pinned.

```
Hi Product Hunt,

I'm Matheus. I built FastShared because every time I wanted to hand someone
a file, I had to choose between three bad options: messaging apps that lock
the file inside themselves forever, cloud drives that treat every share like
a permanent commitment, or the original WeTransfer pattern that feels like
going to a website to send an email attachment in 2010.

FastShared is the tool I wanted on my own devices. One gesture from the
iOS share sheet. Pick how long the link lives. The short URL lands on the
clipboard before the upload even finishes. When the window ends, the link
stops working and the file is deleted from the private R2 bucket it lived
in. That's the whole product.

A few things that matter to me that I hope come through in the app:

— Ephemeral by design, not by subscription plan. There is no "keep forever"
option, because the point of the tool is that nothing sticks around. The
default is 24 hours; you can dial it from 5 minutes to 30 days.

— No accounts. The link is the credential. There is nothing to sign up for,
nothing to log into, nothing to leak. The recipient never signs in either.

— Apple-native where it counts. Background uploads with URLSession so the
share sheet releases instantly. Live Activity and Dynamic Island on iPhone
14 Pro and newer. Drag-and-drop and Paste to Upload on Mac. Universal
Clipboard hand-off between iPhone and Mac.

— Private storage by default. Cloudflare R2 bucket, always-signed GETs,
60-second URL TTL, noindex and no-referrer on every resolve. Tokens are
22 characters of base62 — 131 bits of entropy. I wrote the threat model
out in /docs/architecture/security.md if you like that sort of thing.

What's not in v1.0: resumable uploads for files over 100 MB, password-gated
links, max-download counts, and one-time tokens. All of those are on the
post-MVP roadmap and they all preserve the ephemeral posture. What will
never be in FastShared: permanent hosting, analytics SDKs, ads, an
Android or Windows client.

The whole thing runs on Cloudflare Workers + R2 + Neon Postgres, and the
Apple side is SwiftUI and SwiftData only — no RxSwift, no Combine gymnastics,
no third-party analytics. I wanted to see how small a utility could stay.

Pricing: free for the entire launch window while we gather feedback. After
that, a one-time unlock for higher retention ceilings and larger files,
priced as a tip jar, not a subscription. I'm allergic to subscriptions for
tools this small.

Grateful for any feedback. Reply here, or at matheus.kindrazki@moklabs.com.br.

— Matheus
```

(488 words)

---

## Hunter outreach message template

Keep it short. Hunters read hundreds of these a week.

```
Hi <name>,

I'm launching FastShared on Product Hunt on <date> — a native iOS/iPadOS/macOS
utility that turns "share a file" into a temporary link on the clipboard in
one gesture. Every link expires and the file is deleted by design.

If the positioning resonates, I'd love for you to hunt it. I have the
tagline, description, and a 30-second gallery video queued; the copy is tight
and under every limit. I can send a 5-minute look at the TestFlight if you
want to try it before you decide.

No follow-up if it's not a fit.

Matheus
fastsha.red
```

(98 words)
