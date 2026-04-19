# FastShared

Native Apple app (iOS, iPadOS, macOS) that turns "share a file" into "get a temporary shareable link on my clipboard" in a single gesture.
Backend is Hono on Cloudflare Workers, storage is Cloudflare R2, metadata is Neon Postgres.
Designed for speed, privacy, and an Apple-native UX. Ephemeral by default: links expire (24 h default) and the underlying media is deleted automatically after a short grace period.

## Screenshots

_Placeholder — screenshots to be added at milestone M2 (share extension) and M6 (short link)._

## How it works

```
+------------------+       presign        +-------------------+
| Share Extension  |  ------------------> |  Workers API      |
|  (stages file +  |   retentionPolicy    |  (Hono + Drizzle) |
|   picks TTL)     |                      |                   |
+--------+---------+                      +----+----------+---+
         |                                     |          |
         | direct PUT (bg URLSession)          | metadata | token
         v                                     v          v
      +-----+                              +--------+  +-----------+
      | R2  |  <------ complete -------->  | Neon   |  | fastsha.red/s/ |
      +-----+                              +--------+  +-----------+
         ^
         |  every minute, deletion cron reaps objects past delete_after
```

Default retention is 24 h. At `expiresAt` the link returns 410 Gone; 24 h later the underlying R2 object is deleted by an app-level cron (with an R2 lifecycle rule as a safety net).

## Repo layout

| Path        | Owner            | Purpose                                           |
| ----------- | ---------------- | ------------------------------------------------- |
| `apple/`    | apple team       | SwiftUI app, share extension, Swift core package  |
| `backend/`  | backend team     | Hono on Cloudflare Workers, Drizzle, R2, Neon     |
| `docs/`     | shared           | Product, architecture, and plan documentation     |
| `.github/`  | shared           | CI workflows                                      |

## Quickstart

Apple:

```bash
make bootstrap
make ios
# opens FastShared.xcworkspace in Xcode
```

Backend:

```bash
cd backend
pnpm install
cp ../.env.example .dev.vars
pnpm dev
```

## Tech stack

- Apple: Swift 5.10, SwiftUI, SwiftData, `URLSession` background uploads, Share Extension, App Group, Keychain Sharing
- Backend: Cloudflare Workers, Hono, Drizzle ORM, Neon Postgres (HTTP driver), R2 (S3-compat presigned URLs), KV for rate limits
- Ephemeral lifecycle: Cloudflare Workers cron triggers (deletion, reconciliation, multipart sweeper) with R2 lifecycle rules as safety net
- Build: XcodeGen for the Apple project, pnpm + Wrangler for backend
- CI: GitHub Actions (macos-14 for Apple, ubuntu + node 20 for backend)

## Docs

1. [Product overview](./docs/product/overview.md)
2. [System design](./docs/architecture/system-design.md)
3. [Apple client](./docs/architecture/apple-client.md)
4. [Backend](./docs/architecture/backend.md)
5. [Upload flow](./docs/architecture/upload-flow.md)
6. [Security](./docs/architecture/security.md)
7. [Data model](./docs/architecture/data-model.md)
8. [MVP roadmap](./docs/plan/mvp-roadmap.md)
9. [Implementation checklist](./docs/plan/implementation-checklist.md)

## Milestone status

| Milestone | Goal                                                  | Status  |
| --------- | ----------------------------------------------------- | ------- |
| M0        | Repo setup, CI, docs                                  | planned |
| M1        | Base SwiftUI app (iOS/macOS)                          | planned |
| M2        | Share Extension                                       | planned |
| M3        | App Group + shared background upload                  | planned |
| M4        | Backend skeleton (Workers + Hono)                     | planned |
| M4.5      | Ephemeral lifecycle (retention, deletion crons, revoke) | planned |
| M5        | R2 presign + direct PUT pipeline                      | planned |
| M6        | Token + anonymous resolve + expiry                    | planned |
| M7        | History UI with countdown + revoke                    | planned |
| M8        | Reliability + R2 multipart + deletion hardening       | planned |
| M9        | Tests + release                                       | planned |

MVP ships at M7. Public beta targets M8. Version 1.0 ships at M9.

## License

TBD. This repository is currently private; a license will be chosen before any public release.

## Contact

Placeholder — maintainer contact to be added once the team is formed.
