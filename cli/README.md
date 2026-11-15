# FastShared CLI

Command-line uploader for FastShared.

```bash
fastshared ./report.pdf
fastshared ./screenshots
fastshared - --name output.txt
fastshared ./trace.log --ttl 60s --json
```

Default output is the share URL only, which makes it safe for scripts and AI agents:

```bash
url="$(fastshared ./artifact.zip)"
```

## Publications

`publish` and `publications` require the publications API. They are separate from the temporary `/s/` links above, and they do nothing useful until that API is available.

```bash
fastshared publish ./site
fastshared publish ./deck.pdf --title "Deck"
fastshared publish ./index.html --update my-slug
fastshared publications list
fastshared publications revoke my-slug
fastshared publications opens my-slug
```

stdout for `publish` is the stable URL only. `--json` prints `{ id, slug, url, version, fileCount, totalBytes }`. A directory is zipped locally and published as a site. A single `.html` file is zipped as `index.html` and published as a site. A `.pdf` stays a PDF. Any other single file stays a file.

`--update` keeps the same URL. On the Free plan the API returns HTTP 402, and the CLI exits 2 with `Same-URL updates are a Pro feature` and the upgrade URL on stderr. If completion returns HTTP 202, the CLI polls for up to 60 seconds. Archive rejections from the publications API (`compression_ratio`, `duplicate_path`, `file_too_large`, `invalid_zip`, `no_entry`, `too_many_entries`, `total_too_large`, `unsafe_entry`, `unsafe_path`) are explained on stderr. An unknown code is printed with the code itself.

## MCP

`fastshared mcp` starts a stdio MCP server with tools `publish`, `update`, `revoke`, `list`, and `opens`. It uses the same API client and device token as the CLI, and it also requires the publications API.

