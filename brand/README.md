# fastshared — brand v1.0

Identity for a product whose entire value is brevity. Every upload is a countdown; the mark is the countdown in one frame.

**Concept.** A warm origin sphere emits a single arc toward a ghost node. The arc fades as it approaches; where it lands, only particles remain. You are watching a link expire.

## Files

```
brand/
├── appicon.svg         # 1024×1024, full-bleed. Master for Apple App Store.
├── logo-mark.svg       # transparent bg, inherits currentColor for outlines
├── logo-horizontal.svg # mark + wordmark, transparent bg, 2400×600
├── preview.html        # brand guidelines page (open in browser)
├── export.sh           # renders every Apple icon size from appicon.svg
└── README.md
```

Open `preview.html` in a browser to see the full system in motion.

## Palette

| role | name | hex |
|---|---|---|
| ground | ink | `#070318` |
| surface 1 | nightshade | `#1d0d4b` |
| surface 2 | violet | `#3b1f86` |
| accent · primary | amber | `#ff9f47` |
| accent · soft | ember | `#ffc487` |
| accent · fade | farewell | `#ff4e7c` |
| particle | dust | `#ffe0b8` |
| typography | milk | `#fafaff` |

No other colors ship. Amber is the pulse. Coral is the fade. Everything else is silence.

## Type

- **Display / body** — [Bricolage Grotesque](https://fonts.google.com/specimen/Bricolage+Grotesque), variable, `opsz 12–96`, weights 400–700. Tracking `-0.035em` on headlines.
- **Mono / technical** — [JetBrains Mono](https://fonts.google.com/specimen/JetBrains+Mono), weight 500 for captions.

The wordmark is lowercase `fastshared` at weight 700 with tight tracking, followed by an amber dot. The dot is the only ornament.

## Geometry

All composition lives on a 1024-unit grid.

| element | position | size |
|---|---|---|
| origin sphere | x 300, y 580 | r 124 |
| origin glow | concentric | r 240, 55% amber alpha |
| arc path | `C 420,300 · 620,620` | stroke-width 92 |
| ghost node | x 760, y 420 | r 52 (outline), r 14 (inner) |
| particles | x 794 → 922 | r 11 → 2 · opacity 0.92 → 0.2 |
| safe area | inset | 128 px on all sides |

Mark ratio (origin radius : arc length) is approximately **0.618** — because proportion matters.

## Export for the App Store

```bash
# one-time setup
brew install librsvg

# generate every Apple icon size
cd brand
./export.sh
```

Output in `brand/out/` covers iPhone, iPad, Mac, and the App Store marketing icon at 1024×1024. Drop into `apple/FastSharedApp/Assets.xcassets/AppIcon.appiconset/` and update the `Contents.json` to map each size to its file.

> Apple rounds the corners on-device. Do not pre-round. Do not add transparency. Export full-bleed.

## Do

- Let the origin sphere sit warm and luminous — it is the subject.
- Keep clear space equal to one sphere-diameter on every side.
- Use amber as a hot point only — sparingly, confidently, never as fill.
- Pair the wordmark on `#070318` first. Light backgrounds are print-only.
- Animate the arc (stroke-dashoffset) when introducing the brand for the first time in a new context.

## Don't

- Don't recolor the arc. The amber→coral fade carries the concept.
- Don't place the mark on photography or busy imagery.
- Don't rotate, skew, outline, or emboss the wordmark.
- Don't lowercase it further. `fastshared` is already the final form.
- Don't enclose the icon in a badge, ring, or chrome.

## License

Internal brand asset for fastshared. © 2026 Matheus Kindrazki. Not for use outside the product unless explicitly licensed.
