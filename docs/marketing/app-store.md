# FastShared — App Store Connect copy

Ready-to-paste strings for App Store Connect. Every field has been measured against its
limit; the number in parentheses after each block is the character count of the selected
(final) version.

The canonical uploadable copy now lives in `apple/fastlane/metadata/en-US/`.
Keep this document as the explanation/rationale layer and keep the fastlane
files as the source App Store Connect receives.

---

## App name

```
FastShared
```

(10 / 30)

---

## Subtitle — 3 options, ranked

**1. Final (recommended).**

```
Temporary share links, fast
```

(27 / 30) — leads with the keyword (`share links`), names the differentiator
(`temporary`), and ends on the promise (`fast`). No filler. No emoji.

**2. Runner-up.**

```
Share a file. Get a link.
```

(25 / 30) — purer tagline, weaker for ASO because "share" is only hit once and
"temporary" is absent.

**3. Backup.**

```
Ephemeral share links, Apple-native
```

(35 / 30 — **over limit**, keep as a paid-ad headline only.) If we want the
"ephemeral" keyword in the subtitle slot, a trimmed variant: `Ephemeral share
links for Apple` (31 / 30 — still over). Use option 1.

**4. Pro-aware (candidate for launch week).**

```
Ephemeral share. Pro sync.
```

(26 / 30) — names Pro explicitly, keeps "ephemeral" as brand word. Loses the
"fast" closer. Use only if the owner decides Pro messaging outranks speed.

**5. Pro-aware (alt).**

```
Temporary links. iCloud sync.
```

(29 / 30) — closer to existing voice, swaps "fast" for the Pro benefit.

---

## Promotional text — 3 options, ranked

Promotional text can be edited without a new submission. Change it per launch
moment.

**1. Final (ship this at 1.0).**

```
Share anything, get a temporary link, watch it vanish. No accounts. No residue. Native for iPhone, iPad and Mac. Default 24 h, custom from 5 minutes to 30 days.
```

(160 / 170)

**2. Launch-week variant (tighter, more hook-forward).**

```
One gesture turns any file into a temporary link, already on your clipboard. Default 24 h. Custom up to 30 days. No accounts. No residue. iPhone, iPad, Mac.
```

(156 / 170)

**3. Live Activity push variant (for when the Dynamic Island feature reviews well).**

```
Watch uploads breathe in the Dynamic Island. Temporary links for iPhone, iPad and Mac — share anything, get a link, watch it vanish. Default 24 h. No accounts.
```

(159 / 170)

**4. Pro launch variant.**

```
Share anything, get a temporary link, watch it vanish. No accounts, no residue. Pro unlocks unlimited uploads, 30-day links, iCloud sync. Monthly, annual, or lifetime.
```

(167 / 170)

---

## Description (final, 1 version)

```
Share anything. Get a link. Watch it vanish.

FastShared is a native Apple utility that turns "share a file" into "get a temporary link on my clipboard" in one gesture. Every link is temporary by design — default 24 hours, custom up to 30 days — and the underlying file is deleted automatically when the window closes.

WHAT IT DOES
• Share any file from any app through the iOS share sheet.
• Drag a file onto the Mac app, or paste anything with ⌘V.
• Pick how long the link lives. Default is 24 hours.
• The short link lands on your clipboard. Paste it anywhere.
• Watch the upload breathe in the Dynamic Island on iPhone 14 Pro and newer.
• A Live Activity shows progress and the countdown until expiry.
• Browse your recent links with a live countdown. Revoke any link instantly.

HOW IT WORKS
1. Pick a file. Any app, any file type we support.
2. Pick how long it lives. 1 hour, 24 hours, 1 week, 1 month, or a custom window from 5 minutes to 30 days.
3. Paste. The short link is already on your clipboard before the upload finishes.

BUILT FOR APPLE
• iOS 17 and later, iPadOS 17 and later, macOS 14 and later.
• Native Share Extension on iPhone and iPad.
• Drag-and-drop, .fileImporter, and a Command menu for Paste to Upload on Mac.
• Live Activity and Dynamic Island on iPhone 14 Pro and newer.
• Background uploads with URLSession — keep sharing while it finishes.
• Universal Clipboard — copy on iPhone, paste on Mac seconds later.
• Apple design language throughout. No onboarding carousels, no settings you don't need.

YOUR FILES, YOUR RULES
• Ephemeral by design. Every link has an expiry. When it expires, the link returns 410 Gone and the file is hard-deleted within hours.
• No accounts. There is no sign-up, no email, no password. Nothing to leak.
• No tracking. No analytics SDKs, no advertising IDs, no third-party trackers.
• Private storage. All files live in a private Cloudflare R2 bucket. Reads are signed and scoped to 60 seconds.
• Bearer tokens with 131 bits of entropy. The link is the credential. Revoke any time.
• noindex, no-referrer, no-store on every resolve — tokens stay out of search engines, out of referrer chains, out of caches.

FASTSHARED PRO
• Unlimited uploads per day. No throttle. No counter.
• 2 GB per file — for the screen recording, the slide deck, the full-resolution export.
• Link retention up to 30 days — enough to ship a contract and still have the link alive next week.
• iCloud history sync. Your links follow you across iPhone, iPad, and Mac.
• Family Sharing on Lifetime — one purchase, up to six people.
• Priority support. Reply within one business day.
• Three ways to buy: $2.99/mo, $19.99/yr, or $49.99 once. Pick the one you don't have to think about.

NOT INCLUDED — ON PURPOSE
• No permanent hosting. Every file has a deletion deadline. There is no "keep forever".
• No accounts, no folders, no tags, no libraries.
• No social graph, no comments, no reactions.
• No Android or Windows app. FastShared is Apple-native.

The recipient never signs in. They open the link in any browser or messaging preview, and the file downloads through a short-lived signed redirect. When the window ends, the link stops working for everyone at once.

Support — https://www.fastsha.red/support
Privacy — https://www.fastsha.red/privacy
Terms — https://www.fastsha.red/terms
```

(3816 / 4000)

---

## Keywords (v1.1 Pro-launch pack — commit for launch)

```
share,link,temporary,ephemeral,upload,transfer,file,expire,private,airdrop,sync,subscription,icloud
```

(99 / 100)

### Why these keywords

- `share`, `link`, `upload`, `transfer`, `file` — raw intent. People
  type these when they're looking for exactly this class of tool.
- `temporary`, `ephemeral`, `expire` — differentiator keywords. They
  let us show up when someone wants the "disappearing" nuance without typing
  it.
- `private` — the privacy-driven searcher funnel.
- `airdrop` — Apple-native comparison query. We are not AirDrop, but people
  looking for "AirDrop but to Android/any link" find us here.
- `sync`, `icloud` — Pro iCloud sync is the core differentiator; pairs with
  `airdrop` for the Apple-ecosystem query.
- `subscription` — high-intent for people comparing subscription utilities
  and owning the in-app-purchase comparison funnel.

Cuts vs v1.0: `vanish` (brand word, low volume), `cloud` (`icloud` is more
specific), `send` (`share`+`upload`+`transfer` cover the intent), `clip`
(niche; Pro slots matter more). `pro` was considered but cut — the app name
"FastShared Pro" already carries that token for Apple's search index.
Re-evaluate in Pack B/C/D if data shows conversion loss.

### v1.0 Keywords (fallback pack)

```
share,link,temporary,ephemeral,upload,transfer,file,expire,vanish,private,send,cloud,airdrop,clip
```

(97 / 100) — Pre-Pro pack. Use as a fallback if the v1.1 pack underperforms on
conversion after the 7-day hold.

Notes:

- No spaces between commas (Apple ignores spaces but counts them).
- We deliberately did NOT include the app name (`fastshared`, `fastshare`) —
  Apple indexes the app name and subtitle separately and double-listing burns
  a slot.
- We did NOT include trademarked competitor names (`wetransfer`, `dropbox`,
  `droplr`) — Apple rejects that and it burns review velocity.
- `qr` was considered and cut. We do generate short URLs suitable for QR but
  the app does not render QR codes today.

---

## What's New in Version 1.0.0

```
First public release. Share anything from any app, pick how long the link lives, and the short URL is already on your clipboard before the upload even finishes. Every file is temporary on purpose — links expire on schedule and the media is deleted automatically. Built for iOS 17, iPadOS 17, and macOS 14 and later, with a Live Activity and Dynamic Island moment on iPhone 14 Pro and newer.
```

(424 chars, well under the 4000 What's New limit.)

---

## What's New in Version 1.1.0

```
FastShared Pro is here. Unlimited uploads, 30-day links, iCloud history sync across iPhone, iPad, and Mac. Pick Monthly at $2.99, Annual at $19.99 — or grab Lifetime at $49.99 during Early Access with Family Sharing included. Free stays free, no strings. Every link is still temporary by design.
```

(295 / 4000)
