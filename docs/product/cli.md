# FastShared CLI

FastShared CLI is the scriptable surface for agents and terminal workflows. It uploads a local artifact and prints a temporary FastShared URL.

## Install

```bash
curl -fsSL https://fastsha.red/install.sh | bash
```

The installer requires Node.js 20+, installs into `~/.local/share/fastshared-cli`, and creates `~/.local/bin/fastshared`.

## Usage

```bash
fastshared ./artifact.zip
fastshared ./folder
fastshared ./a.log ./b.json
fastshared - --name output.txt
fastshared ./trace.log --ttl 60s --json
```

Default stdout is URL-only:

```bash
url="$(fastshared ./result.json)"
```

Progress and errors go to stderr so agents can safely consume stdout.

## Behavior

- Default retention is `1h`; supported `--ttl` values are `60s`, `1h`, `1d`, `1w`, and `30d`.
- A single file uploads as itself. A directory or multiple paths are zipped locally into one temporary archive and uploaded as one link.
- `-` reads stdin; use `--name` to preserve a useful filename and MIME type.
- `--json` returns `{ shortUrl, token, expiresAt, deleteAfter, linkStatus, retentionPolicy }`.

## Auth And Config

On first use the CLI registers a `cli` device through `POST /v1/devices` and stores the returned bearer token in:

```text
~/.config/fastshared/config.json
```

The file is written with `0600` permissions. Overrides:

- `FASTSHARED_DEVICE_TOKEN` uses a token without reading/writing auth.
- `FASTSHARED_API_URL` changes the API host.
- `FASTSHARED_CONFIG` changes the config file path.

V1 uses the same device limits as the app: Free devices keep the current Free caps; heavier agent usage can move to a scoped API-token model later.

## Publications

Requires the publications API. These commands are not temporary `/s/` links, and this document does not claim that API is available in production.

```bash
fastshared publish ./site --title "Notes"
fastshared publish ./manual.pdf
fastshared publish ./index.html --update <id-or-slug>
fastshared publications list [--json]
fastshared publications revoke <id-or-slug>
fastshared publications opens <id-or-slug> [--json]
fastshared mcp
```

- A directory is zipped locally and sent as `kind=site`.
- A single `.html` file is zipped with an `index.html` entry and sent as `kind=site`.
- A `.pdf` is sent as `kind=pdf`. Any other single file is sent as `kind=file`.
- `publish` prints only the stable URL. `--json` prints `{ id, slug, url, version, fileCount, totalBytes }`.
- `--update` calls `POST /v1/publications/:id/versions`. HTTP 402 exits 2 and prints `Same-URL updates are a Pro feature` plus `upgradeUrl` on stderr.
- HTTP 202 on complete polls `GET /v1/publications/:id/versions/:version`, or the `Location` header when that URL is on the API host, until the version is ready or 60 seconds pass.
- `unpack_error` values from the publications API (`compression_ratio`, `duplicate_path`, `file_too_large`, `invalid_zip`, `no_entry`, `too_many_entries`, `total_too_large`, `unsafe_entry`, `unsafe_path`) are printed as short explanations. An unknown code is printed with the code itself.

`fastshared mcp` speaks MCP over stdio. Tools: `publish`, `update`, `revoke`, `list`, `opens`.

Client shapes, all camelCase JSON and bearer auth:

| Call | Body / response the CLI uses |
|---|---|
| `POST /v1/publications` and `POST /v1/publications/:id/versions` | `{ title?, kind, filename, sizeBytes, contentType }` → `{ id, slug, url, version, upload: { url, method: "PUT", headers } }` |
| `PUT` `upload.url` | Raw bytes. |
| `POST /v1/publications/:id/versions/:version/complete` | `200 { url, version, fileCount, totalBytes }`, `202 { status: "processing" }`, or problem+json `{ code: "unpack_error", unpack_error }` |
| `GET /v1/publications/:id/versions/:version` | `{ status: "processing" }`, `{ status: "ready", url, version, fileCount, totalBytes }`, or `{ status: "failed", unpack_error }` |
| `GET /v1/publications` | `{ publications: [{ id, slug, url, title?, kind, status, version, expiresAt, opens7d }] }` |
| `POST /v1/publications/:id/revoke` | `{ id, status }` |
| `GET /v1/publications/:id/opens` | `{ id, versions: [{ version, count, lastOpenedAt }] }` |

`:id` accepts an id or a slug. Poll interval and timeout can be overridden with `FASTSHARED_PUBLICATION_POLL_INTERVAL_MS` and `FASTSHARED_PUBLICATION_POLL_TIMEOUT_MS`.
