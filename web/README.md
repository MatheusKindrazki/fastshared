# FastShared — web

Marketing landing page for FastShared. Astro + Tailwind + GSAP, deployed to
Cloudflare Pages and served publicly at the apex `fastsha.red` through the
backend Worker (see "Deploy" below). `www.fastsha.red` does not exist — it has
no DNS record and must never appear in canonical URLs, OG tags or metadata.

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

The production Pages project is `fastshared-web` in the personal Cloudflare
account `aad020260082c48f6370fa7954b72f81`. Do not publish FastShared web
assets to the MokLabs account.

GitHub Actions deploys production automatically from `main` when `web/**` or
`.github/workflows/web-deploy.yml` changes. Pull requests run the same build
without deploying.

For a manual deploy, load the repo root `.env` first and pin the personal
account id:

```bash
pnpm install
pnpm build
CLOUDFLARE_ACCOUNT_ID=aad020260082c48f6370fa7954b72f81 \
  pnpm dlx wrangler pages deploy dist --project-name fastshared-web --branch main
```

No custom domain is attached to the Pages project, and none should be. The
apex `fastsha.red` is a **Worker** custom domain (`backend/wrangler.toml`
`[[routes]]`), and `backend/src/index.ts` `routeRequest()` proxies every
non-app path through to `fastshared-web.pages.dev`. That is how this site is
reached in production — deploying to Pages is enough, the apex picks it up.

Do NOT point the apex at Pages directly. `routeRequest()` proxies to Pages only
what `isAppPath()` rejects; the paths it keeps on the Worker are `/s`, `/b`,
`/v1`, `/.well-known`, `/og-image.png` and `/brand`. Hand the apex to Pages and
short links and the Apple app-site-association handoff break.

(`api.fastsha.red` is the same Worker on a second custom domain. The host check
in `routeRequest()` only matches `fastsha.red`, so on `api` nothing is proxied
and every path — `/v1` included — is served by the Worker app.)

## Open threads

- Brand assets are generated from `brand/source-mark.png` via
  `brand/export.sh`; `public/og-image.png` is now the v2 social card.
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
