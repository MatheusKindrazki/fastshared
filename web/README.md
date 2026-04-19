# FastShared — web

Marketing landing page for FastShared. Astro + Tailwind + GSAP, deployed to
Cloudflare Pages under `www.fastsha.red`.

## Stack

- **Astro 4** (static output, islands only where needed)
- **TailwindCSS 3**
- **GSAP 3** for the hero temporal-link arc
- **TypeScript** strict mode
- **pnpm** (the rest of the monorepo uses pnpm too)
- **Cloudflare Pages** (custom domain wired manually in the Pages UI)

## Develop

```bash
pnpm install
pnpm dev              # http://127.0.0.1:4321
```

## Build & preview

```bash
pnpm build
pnpm preview
```

## Deploy (Cloudflare Pages)

First time, in the Pages UI, create a project named `fastshared-web`
pointing to this directory, build command `pnpm build`, output `dist`.
After that, you can deploy from the command line:

```bash
pnpm install
pnpm build
pnpm dlx wrangler pages deploy dist --project-name fastshared-web
```

Then attach the custom domain `www.fastsha.red` in the Cloudflare Pages
project settings. The apex `fastsha.red` is reserved for short-link
redirects served by the backend Worker — do NOT point the apex at Pages.

## Open threads

- `public/og-image.png` — placeholder / TODO. Generate a 1200×630 PNG
  from `brand/appicon.svg` on a dark canvas (use `rsvg-convert`) before
  shipping the public beta.
- TestFlight URL — currently `#testflight`. Replace when the TestFlight
  build is live on App Store Connect.
- `/privacy` and `/terms` — placeholder copy. Final versions land before
  the public beta.

## Layout

```
src/
├── pages/
│   ├── index.astro        # The single landing page
│   ├── privacy.astro
│   └── terms.astro
├── layouts/Base.astro     # HTML shell, fonts, meta, OG, JSON-LD
├── components/            # One file per landing section
├── styles/global.css      # palette, typography, noise bg, grid
└── scripts/hero.ts        # GSAP hero orchestration + island rotator
```

## Notes

- No React. No analytics yet (will land in a later milestone).
- The page renders and is fully readable without JavaScript.
  GSAP enhances; it never gates content.
- `prefers-reduced-motion: reduce` skips the arc draw and shows the
  static end frame; Dynamic Island also freezes on "completed".
