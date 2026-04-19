# FastShared — Twitter/X launch thread

Seven-tweet launch thread, ≤280 characters each. Attach media where marked.
Post on Launch Day, **not** at the moment of the App Store release — wait
until the App Store listing propagates globally (usually ~6 hours after
"Released for sale" flips).

The second half of the file contains a BlueSky-adjusted variant with room to
breathe (1000-char limit).

---

## Twitter / X — 7 tweets

**[T1 — hook]**

> Share anything. Get a link. Watch it vanish.
>
> FastShared is a native iOS, iPadOS, and macOS app that turns "share a file"
> into "a temporary link on my clipboard" in one gesture.
>
> Out today. 🔗 fastsha.red

`[attachment: HERO_GIF_loop.gif — 6–10s loop of the hero arc animation with the
wordmark reveal]`

(267 / 280)

---

**[T2 — the gesture]**

> One gesture:
>
> 1. Share sheet → FastShared.
> 2. Pick how long the link lives.
> 3. Paste anywhere. The short URL is already on your clipboard.
>
> Default 24 h. Custom from 5 minutes to 30 days. No accounts. No residue.

`[attachment: SCREEN_RECORDING_share_flow.mp4 — iPhone share sheet → retention
picker → clipboard toast. 8–12s, no audio]`

(254 / 280)

---

**[T3 — ephemeral by design]**

> Every link expires.
> Every file is deleted.
> By design.
>
> When the window ends, the link returns 410 Gone and the file is hard-deleted
> from a private R2 bucket within hours. Nothing lingers. Nothing to leak.

(229 / 280)

---

**[T4 — Dynamic Island / Live Activity]**

> Watch your upload breathe in the Dynamic Island.
>
> iPhone 14 Pro and newer: progress → short URL → expiry countdown, live in
> the Island. Tap to copy. Tap to revoke.

`[attachment: ISLAND_LOOP.mp4 — Dynamic Island state cycle (upload → copied →
expired) on an iPhone 15 Pro mock]`

(226 / 280)

---

**[T5 — Mac story]**

> On Mac: drag any file onto the window, or paste anything with ⌘V.
>
> Links you create on iPhone are already on your Mac through Universal
> Clipboard — no pairing, no setup.

`[attachment: MAC_DRAG_DROP.gif — file dragged onto Mac app → link toast]`

(222 / 280)

---

**[T6 — what it is not]**

> FastShared is not a cloud drive.
>
> No folders. No tags. No accounts. No permanent hosting.
>
> If you need to keep a file, keep a copy. The point is that this one won't
> stick around.

(186 / 280)

---

**[T7 — CTA]**

> Available today on the App Store for iPhone, iPad, and Mac.
>
> App Store → https://apps.apple.com/app/idXXXXXXXXX
> Landing  → https://www.fastsha.red
> TestFlight → https://testflight.apple.com/join/XXXXXX
>
> Shipped with care. Feedback welcome.

(252 / 280)

---

## BlueSky variant (1000-char limit — fewer tweets, more breath)

**[B1 — hook + what]**

> Share anything. Get a link. Watch it vanish.
>
> FastShared is a native iOS, iPadOS, and macOS utility that turns the
> everyday "share a file" chore into one gesture. Pick any file from any app,
> pick how long the link lives, and the short URL is already on your clipboard
> before the upload finishes. Default is 24 hours. Custom goes from 5 minutes
> up to 30 days. No accounts, no folders, no recipients to manage.
>
> Out today. fastsha.red

`[attachment: HERO_GIF_loop.gif]`

---

**[B2 — ephemeral, the promise]**

> Every link expires. Every file is deleted. By design.
>
> When a link's window ends, it returns 410 Gone and the underlying object is
> hard-deleted from a private Cloudflare R2 bucket. No soft-delete, no
> recovery, no lingering. Reads are signed to a 60-second TTL so the redirect
> URL itself can't leak. Tokens are 131 bits of entropy. The link is the
> credential; revoke any one of them from the history view and it stops
> resolving immediately.
>
> FastShared is a small tool that refuses to pretend otherwise.

---

**[B3 — Apple-native]**

> Built for the share sheet, not the web browser.
>
> iPhone and iPad: native Share Extension, background uploads with
> URLSession, Live Activity and Dynamic Island on iPhone 14 Pro and newer.
> Mac: drag-and-drop, fileImporter, and a Command menu for Paste to Upload.
> Universal Clipboard hands a link you created on iPhone straight to your
> Mac, no pairing, no setup.
>
> It is the tool that should have existed when AirDrop stopped at the edge of
> the room.

---

**[B4 — CTA]**

> Available today on the App Store for iPhone, iPad, and Mac.
>
> https://apps.apple.com/app/idXXXXXXXXX
>
> Landing and full details at https://www.fastsha.red
>
> This is v1.0. The roadmap after this is resumable uploads, password-gated
> links, and max-download counts — all still inside the ephemeral-by-default
> posture. Feedback goes straight to me; reply here or open an issue at
> github.com/MatheusKindrazki/fastshared (issues open after public launch).

---

## Notes for the poster

- Replace `idXXXXXXXXX` with the real App Store ID once the app propagates.
  Easiest way to find it: open the App Store page on any device and tap
  Share.
- Replace `XXXXXX` with the real TestFlight public link (or remove the line
  entirely if TestFlight is closed at launch).
- Pin T1 / B1 to the profile for launch week.
- Queue the Product Hunt and Hacker News posts to land **after** T1 is live
  but **before** T7 — so cross-linking works both ways.
