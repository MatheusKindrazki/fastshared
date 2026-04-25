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
