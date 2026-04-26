# fastshared - brand v2.0

FastShared now uses a luminous paper-plane mark over a violet flight arc. The
PNG masters are the visual source of truth because the logo depends on glow,
soft alpha, and raster shading that should not be approximated differently per
platform. SVG files in this folder are simplified compatibility assets for
favicon, mask-icon, and vector download surfaces.

## Files

```text
brand/
├── source-mark.png            # transparent source generated from the approved mark
├── source-lockup-dark.png     # square dark reference lockup from the approved prompt
├── appicon-1024.png           # App Store/web icon master, RGB, no alpha
├── logo-mark.png              # transparent mark, 2048 x 2048
├── logo-horizontal.png        # transparent horizontal lockup, 2400 x 800
├── wordmark-horizontal-dark.png
├── wordmark-horizontal-light.png
├── wordmark-mark.png
├── og-image.png               # 1200 x 630 social card
├── appicon.svg                # simplified vector fallback
├── logo-mark.svg              # simplified vector fallback
├── logo-horizontal.svg        # simplified vector fallback
├── clean_mark.py              # alpha-speck cleanup for generated transparent PNGs
├── export.sh                  # regenerates PNG assets and Apple AppIcon sizes
└── preview.html               # local brand preview
```

## Palette

| role | hex |
|---|---|
| ink | `#070318` |
| night violet | `#12082d` |
| arc violet | `#9d7aff` |
| arc shadow | `#3b0f58` |
| arc soft | `#c7b4ff` |
| milk | `#fffdf8` |

## Export

```bash
cd brand
./export.sh
```

`export.sh` writes the public brand PNGs into `brand/` and every Apple icon
size into `brand/out/`. Copy `brand/out/*.png` into
`apple/FastSharedApp/Assets.xcassets/AppIcon.appiconset/`.

## Usage Rules

- Use `appicon-1024.png` for app icons, nav chips, README badges, and Apple touch icons.
- Use `logo-horizontal.png` only on dark or controlled backgrounds where the app icon tile can sit cleanly.
- Use `wordmark-horizontal-dark.png` for press and social surfaces on ink backgrounds.
- Use `logo-mark.svg` only for favicon/mask/vector fallback contexts.
- Do not restore the old PlaneArc path artwork or stroke-draw animation; this mark is a raster/glow identity.
