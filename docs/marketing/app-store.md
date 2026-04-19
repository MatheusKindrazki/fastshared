# FastShared — App Store Connect copy

Ready-to-paste strings for App Store Connect. Every field has been measured against its
limit; the number in parentheses after each block is the character count of the selected
(final) version.

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

(2777 / 4000)

---

## Keywords (final)

```
share,link,temporary,ephemeral,upload,transfer,file,expire,vanish,private,send,cloud,airdrop,clip
```

(97 / 100)

### Why these keywords

- `share`, `link`, `upload`, `transfer`, `file`, `send` — raw intent. People
  type these when they're looking for exactly this class of tool.
- `temporary`, `ephemeral`, `expire`, `vanish` — differentiator keywords. They
  let us show up when someone wants the "disappearing" nuance without typing
  it.
- `private` — the privacy-driven searcher funnel.
- `cloud` — broad match for people comparing to Dropbox/Drive.
- `airdrop` — Apple-native comparison query. We are not AirDrop, but people
  looking for "AirDrop but to Android/any link" find us here.
- `clip` — short-link / clipboard association; also helps surface against
  clipboard-centric tools.

`quick` was considered and cut to stay under the 100-char cap; the app name
itself already carries speed intent.

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
