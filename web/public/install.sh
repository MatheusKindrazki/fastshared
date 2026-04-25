#!/usr/bin/env bash
set -euo pipefail

repo="${FASTSHARED_CLI_REPO:-MatheusKindrazki/fastshared}"
version="${FASTSHARED_CLI_VERSION:-latest}"
asset="${FASTSHARED_CLI_ASSET:-fastshared-cli.tgz}"
install_dir="${FASTSHARED_INSTALL_DIR:-$HOME/.local/share/fastshared-cli}"
bin_dir="${FASTSHARED_BIN_DIR:-$HOME/.local/bin}"

if [ -n "${FASTSHARED_CLI_URL:-}" ]; then
  url="$FASTSHARED_CLI_URL"
elif [ "$version" = "latest" ]; then
  url="https://github.com/$repo/releases/latest/download/$asset"
else
  url="https://github.com/$repo/releases/download/$version/$asset"
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf "fastshared install: missing required command: %s\n" "$1" >&2
    exit 1
  fi
}

need curl
need tar
need node
need npm

node_major="$(node -p "Number(process.versions.node.split('.')[0])")"
if [ "$node_major" -lt 20 ]; then
  printf "fastshared install: Node.js 20+ is required, found %s\n" "$(node -v)" >&2
  exit 1
fi

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

printf "Downloading FastShared CLI from %s\n" "$url" >&2
curl -fsSL "$url" -o "$tmp/$asset"

tar -xzf "$tmp/$asset" -C "$tmp"
if [ ! -f "$tmp/package/package.json" ]; then
  printf "fastshared install: release asset did not contain an npm package\n" >&2
  exit 1
fi

rm -rf "$install_dir"
mkdir -p "$install_dir" "$bin_dir"
cp -R "$tmp/package/." "$install_dir/"

(
  cd "$install_dir"
  npm install --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null
)

if [ ! -f "$install_dir/dist/index.js" ]; then
  printf "fastshared install: package is missing dist/index.js\n" >&2
  exit 1
fi

chmod +x "$install_dir/dist/index.js"
ln -sf "$install_dir/dist/index.js" "$bin_dir/fastshared"

printf "FastShared CLI installed at %s\n" "$bin_dir/fastshared" >&2
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    printf "Add %s to PATH to run 'fastshared' from any shell.\n" "$bin_dir" >&2
    ;;
esac
