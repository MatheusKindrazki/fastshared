#!/usr/bin/env bash
# Export the master app icon to every PNG size Apple asks for.
# Requires: brew install librsvg
set -euo pipefail

cd "$(dirname "$0")"
SRC=${SRC:-appicon.svg}
OUT=${OUT:-out}
mkdir -p "$OUT"

if ! command -v rsvg-convert >/dev/null; then
  echo "rsvg-convert missing — run: brew install librsvg" >&2
  exit 1
fi

# Apple AppIcon.appiconset sizes (name  px)
SIZES=(
  "ios-20@2x           40"
  "ios-20@3x           60"
  "ios-29@2x           58"
  "ios-29@3x           87"
  "ios-40@2x           80"
  "ios-40@3x          120"
  "ios-60@2x          120"
  "ios-60@3x          180"
  "ipad-20@1x          20"
  "ipad-20@2x          40"
  "ipad-29@1x          29"
  "ipad-29@2x          58"
  "ipad-40@1x          40"
  "ipad-40@2x          80"
  "ipad-76@1x          76"
  "ipad-76@2x         152"
  "ipad-83.5@2x       167"
  "mac-16@1x           16"
  "mac-16@2x           32"
  "mac-32@1x           32"
  "mac-32@2x           64"
  "mac-128@1x         128"
  "mac-128@2x         256"
  "mac-256@1x         256"
  "mac-256@2x         512"
  "mac-512@1x         512"
  "mac-512@2x        1024"
  "appstore-1024      1024"
)

for row in "${SIZES[@]}"; do
  read -r name px <<<"$row"
  out="$OUT/${name}.png"
  rsvg-convert -w "$px" -h "$px" "$SRC" -o "$out"
  printf "  %-20s %4dpx  %s\n" "$name" "$px" "$out"
done

printf "\nwrote %d icons to %s/\n" "${#SIZES[@]}" "$OUT"
printf "next: drop them into apple/FastSharedApp/Assets.xcassets/AppIcon.appiconset/\n"
