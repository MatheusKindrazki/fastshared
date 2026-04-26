<p align="center">
  <img src="./apple/FastSharedApp/Assets.xcassets/AppIcon.appiconset/appstore-1024.png" alt="FastShared app icon" width="120" />
</p>

<h1 align="center">FastShared</h1>

<p align="center">
  <strong>Share anything. Get a link. Watch it vanish.</strong>
</p>

<p align="center">
  Apple-native temporary share links for iPhone, iPad, and Mac.
</p>

<p align="center">
  <a href="https://fastsha.red">Website</a>
  ·
  <a href="./docs/product/overview.md">Product overview</a>
  ·
  <a href="./docs/product/cli.md">CLI</a>
  ·
  <a href="./docs/architecture/security.md">Security</a>
  ·
  <a href="./docs/ops/testflight-setup.md">TestFlight runbook</a>
</p>

<p align="center">
  <a href="https://github.com/MatheusKindrazki/fastshared/actions/workflows/backend.yml"><img src="https://github.com/MatheusKindrazki/fastshared/actions/workflows/backend.yml/badge.svg" alt="Backend CI" /></a>
  <a href="https://github.com/MatheusKindrazki/fastshared/actions/workflows/apple.yml"><img src="https://github.com/MatheusKindrazki/fastshared/actions/workflows/apple.yml/badge.svg" alt="Apple CI" /></a>
  <a href="https://github.com/MatheusKindrazki/fastshared/actions/workflows/apple-preview.yml"><img src="https://github.com/MatheusKindrazki/fastshared/actions/workflows/apple-preview.yml/badge.svg" alt="Apple preview TestFlight" /></a>
</p>

## What it is

FastShared turns the everyday "share a file" chore into one gesture: pick a
file, choose how long the link should live, and paste the temporary URL from
your clipboard.

Every link expires. Every file is deleted. By design.

## Built for Apple

| Surface | Experience |
| ------- | ---------- |
| iPhone and iPad | Native Share Extension, background uploads, Live Activity, and Dynamic Island progress. |
| Mac | Menu bar workflow, drag-and-drop uploads, paste-to-upload command, and structured recent links. |
| CLI | Scriptable uploads for agents and shell workflows; stdout returns the temporary URL. |
| Recipient | Opens a short link in any browser. No account, app, or sign-in required. |

## Product limits

| Tier | File size | Retention | Uploads | Sync |
| ---- | --------- | --------- | ------- | ---- |
| Free launch access | 2 GB per file | Up to 30 days | Unlimited | Local history |
| Pro | 2 GB per file | Up to 30 days | Unlimited | iCloud metadata sync |

The backend is the source of truth for caps and retention. For launch, Free
uses Pro upload ceilings while keeping account-level sync features paid.

## How it works

```text
Share Extension / Mac App
        |
        | presign + retention policy
        v
Cloudflare Worker API
        |
        | direct upload
        v
Cloudflare R2 private bucket
        |
        | metadata, expiry, owner actions
        v
Neon Postgres + KV rate limits
        |
        | short link
        v
fastsha.red/s/<token>
```

Default retention is 24 hours. When a link expires, the resolve endpoint
returns `410 Gone`; the underlying object is then deleted by the retention
workflow, with storage lifecycle rules as a safety net.

## Tech stack

| Layer | Stack |
| ----- | ----- |
| Apple | SwiftUI, SwiftData, Share Extension, background `URLSession`, Keychain Sharing, CloudKit metadata sync |
| CLI | Node.js 20+, TypeScript, native `fetch`, local ZIP staging |
| Backend | Cloudflare Workers, Hono, Drizzle ORM, Neon Postgres, R2, KV |
| Web | Astro landing/docs surfaces |
| CI/CD | GitHub Actions, Xcode/TestFlight lanes, Wrangler deploy workflows |

## Repo layout

| Path | Purpose |
| ---- | ------- |
| `apple/` | iOS, iPadOS, macOS app targets, Share Extension, shared Swift package |
| `cli/` | Node/TypeScript command-line uploader for agents and scripts |
| `backend/` | Hono Worker API, persistence, billing verification, retention jobs |
| `web/` | Public site and static marketing surfaces |
| `docs/` | Product, architecture, security, launch, and ops documentation |
| `.github/` | CI, preview, production, and release workflows |

## Quickstart

Apple:

```bash
make bootstrap
make ios
```

Backend:

```bash
cd backend
pnpm install
cp ../.env.example .dev.vars
pnpm dev
```

Web:

```bash
cd web
pnpm install
pnpm build
```

CLI:

```bash
cd cli
pnpm install
pnpm test
pnpm build
```

## Validation

Backend:

```bash
cd backend
npm run typecheck
npm test
```

Apple core package:

```bash
cd apple/Packages/FastSharedCore
swift test
```

Web:

```bash
cd web
pnpm build
```

CLI:

```bash
cd cli
pnpm typecheck
pnpm test
pnpm build
```

## Documentation

- [Product overview](./docs/product/overview.md)
- [CLI](./docs/product/cli.md)
- [System design](./docs/architecture/system-design.md)
- [Apple client](./docs/architecture/apple-client.md)
- [Backend](./docs/architecture/backend.md)
- [Upload flow](./docs/architecture/upload-flow.md)
- [Security](./docs/architecture/security.md)
- [Data model](./docs/architecture/data-model.md)
- [MVP roadmap](./docs/plan/mvp-roadmap.md)
- [Implementation checklist](./docs/plan/implementation-checklist.md)

## Release notes

- Apple preview builds publish both iOS and macOS TestFlight artifacts.
- Backend deploys are separated between staging and production promotion flows.
- Public docs should match the real retention, logging, Keychain, and download behavior before release.

## License

TBD. This repository is currently private; a license will be chosen before any
public release.
