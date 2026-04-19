# FastShared — design queue

Visual assets needed for a full launch that cannot be generated from text
alone. Each item has acceptance criteria, reference dimensions, and an
owner/when hint. Owners are roles, not names — fill in real names when
assigning.

## Conventions

- All assets use the brand palette (`ink #070318`, `amber #ff9f47`, coral
  `#ff4e7c`, milk `#fafaff`). No gradients outside the ones in `brand/`.
- Typography: **Bricolage Grotesque** for display/body, **JetBrains Mono** for
  captions. Load variable axes; use `opsz` appropriate to the size.
- Dimensions are authoritative for App Store / social upload compliance. Do
  not round or "close enough" — they will reject.
- Export PNG unless told otherwise. No JPEG for anything that has type on it.
- All captions pass through `docs/marketing/voice-tone.md` before final.

---

## 1. App Store screenshots — iPhone 6.9" (iPhone 15 Pro Max / 16 Pro Max)

- **Dimensions.** `1290 × 2796` portrait, PNG, no alpha.
- **Count.** 5 frames, delivered as `01_share.png` … `05_expired.png`.
- **Caption band.** Top 22% of the frame is a solid `#070318` band with a
  JetBrains Mono caption (48pt, tracking 0.04em, milk/80).
- **Device bezel.** No device bezel — Apple adds one on the listing page.
- **Frame content.**
  1. `01_share` — iOS Share Sheet with FastShared highlighted. Caption:
     `one gesture · any file · any app`.
  2. `02_retention` — the retention picker (1 h / 24 h / 1 w / 1 mo / custom).
     Caption: `pick how long the link lives`.
  3. `03_copied` — clipboard toast "Copied — fastsha.red/s/abc…" with the
     Dynamic Island showing the "copied" state. Caption: `the link is already
     on your clipboard`.
  4. `04_history` — History view with a live countdown badge on the top row
     (green, 23:59). Caption: `every link has a countdown`.
  5. `05_expired` — same history view a day later: the row is greyed to
     "Expired" and the next row is live. Caption: `by design, every link
     vanishes`.
- **Owner / when.** Designer · due one week before App Store submission.
- **Acceptance.** Opens on actual iPhone 15 Pro Max without cropping; first
  two frames pass the App Store thumbnail (150px wide) squint test.

## 2. App Store screenshots — iPad 13" (iPad Pro M4)

- **Dimensions.** `2064 × 2752` portrait, PNG, no alpha.
- **Count.** 5 frames, matching iPhone captions but composed for iPad
  (sidebar history visible, retention picker wider, multi-column layout).
- **Owner / when.** Designer · parallel with iPhone set.
- **Acceptance.** Tested at 50% zoom on macOS Preview — every caption still
  legible.

## 3. App Store screenshots — Mac

- **Dimensions.** `2880 × 1800` (or 1440×900 @2x) — Apple accepts any of the
  documented Mac screenshot sizes so long as the ratio is correct.
- **Count.** 5 frames.
- **Frame content.**
  1. Mac main window with the hub view + hero metric (live count).
  2. Drag-and-drop moment — file dragged from Finder onto the window.
  3. Paste-to-upload — ⌘V with clipboard preview and upload starting.
  4. History view with live countdowns and a Revoke affordance.
  5. Universal Clipboard moment — link created on iPhone appearing on Mac.
- **Owner / when.** Designer · parallel with iPad.
- **Acceptance.** Exported on macOS 14+ so the window chrome matches the
  current Big Sur-era design. Light mode only (consistent with the hub).

## 4. App Store preview video — per device

- **Length.** 15–30 seconds. Aim for 20.
- **Container.** `MP4` (H.264 + AAC), 30 fps, 1080p (device-specific
  resolution: 886×1920 for 6.9" iPhone preview, 1200×1600 for iPad 13",
  1920×1080 for Mac).
- **Audio.** None or a single ping on the "copied" beat. No voiceover.
- **Cuts.**
  - 0–2 s: wordmark + arc animation.
  - 2–10 s: share flow on device.
  - 10–15 s: Live Activity / Dynamic Island state cycle.
  - 15–20 s: history view with expiry, fade to wordmark + `fastsha.red`.
- **Owner / when.** Motion designer · due two weeks before submission.
- **Acceptance.** Passes Apple's preview validator. Legible at 50% scale on
  the App Store listing thumbnail.

## 5. Hero motion GIF (for Twitter T1, landing page fallback)

- **Length.** 6–10 seconds, seamless loop.
- **Dimensions.** `1200 × 750`, ≤ 4 MB, 24 fps.
- **Content.** Arc animation from `brand/` rendered onto the hero
  composition, with the wordmark revealing on the last 2 frames.
- **Owner / when.** Motion designer · launch week.
- **Acceptance.** Loops without a visible seam; file size tolerates Twitter's
  auto-conversion to MP4.

## 6. Social banners

| surface          | dimensions    | notes                                                               |
| ---------------- | ------------- | ------------------------------------------------------------------- |
| Twitter / X header | `1500 × 500` | Wordmark left-of-center, hero arc right. Leave safe area for the avatar overlay (bottom-left circle). |
| BlueSky header     | `1500 × 500` | Same composition; BlueSky uses the same spec as Twitter.           |
| LinkedIn company banner | `1128 × 191` | This is LinkedIn's current spec as of 2025/2026 — do not use the legacy `1536 × 768`. Minimal type; the space is cramped. |
| GitHub social preview | `1280 × 640` | Set in repo Settings → Social preview. Include the wordmark + tagline. |

- **Owner / when.** Designer · launch week.
- **Acceptance.** On actual devices at 100% DPR and on Retina, neither wordmark nor tagline crops.

## 7. Social avatars

- **Dimensions.** `400 × 400` PNG, no alpha, dark background.
- **Composition.** Wordmark mark (the arc + sphere) centered with 20% safe
  area on all sides. No wordmark text — tiny avatar, text is illegible.
- **Platforms.** Twitter, BlueSky, GitHub, LinkedIn, Mastodon, Threads.
- **Owner / when.** Designer · launch week.
- **Acceptance.** At 48×48 favicon scale the mark is still identifiable.

## 8. Product Hunt gallery

(Also specified in detail in `launch-producthunt.md`. Replicated here for the
tracking table.)

- Image 1 — share-sheet hero, 1270×760.
- Image 2 — Dynamic Island state cycle, 1270×760.
- Image 3 — ephemeral promise feature shot, 1270×760.
- Optional image 4 — Mac drag-and-drop, 1270×760.
- Optional video — 30 s, 16:9, MP4 H.264.
- **Owner / when.** Designer · 48 h before PH launch day.

## 9. Email signature HTML template

**Status: delivered.** See `docs/marketing/email-signature.html`.

## 10. Favicon set (final pass)

- **Status.** `web/public/favicon.svg` exists. A favicon pass should confirm
  legibility at 16×16 and 32×32 (the SVG is fine at Retina; the fallback
  raster needs a manual ink outline pass).
- **Owner / when.** Designer · post-launch iteration.
- **Acceptance.** Identifiable on a bookmarks bar at 16×16.

---

## Budget sanity check

If the designer can deliver only three items in launch week, prioritize:

1. iPhone 6.9" screenshots (5 frames) — required for App Store.
2. Twitter header + social avatar — required for launch-day propagation.
3. Hero motion GIF — drives the Twitter T1 conversion.

Everything else can land in the two weeks after launch.
