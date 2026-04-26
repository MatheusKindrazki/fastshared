#!/usr/bin/env bash
# Export FastShared brand assets from the new raster masters.
# Requires: ImageMagick. The SVG files in this folder are simplified fallbacks
# for favicon/mask/vector consumers; PNG is the visual source of truth.
set -euo pipefail

cd "$(dirname "$0")"

MARK_SRC=${MARK_SRC:-source-mark.png}
OUT=${OUT:-out}
FONT=${FONT:-/Library/Fonts/SF-Pro-Rounded-Bold.otf}

mkdir -p "$OUT"

if ! command -v magick >/dev/null; then
  echo "ImageMagick missing. Install it with: brew install imagemagick" >&2
  exit 1
fi

if [[ ! -f "$MARK_SRC" ]]; then
  echo "Missing $MARK_SRC. Copy the transparent mark PNG into brand/ first." >&2
  exit 1
fi

if [[ ! -f "$FONT" ]]; then
  FONT=$(magick -list font | awk '/Font: System-Font-Bold/{print $2; exit}')
fi

MARK_CLEAN=.mark-clean.png
trap 'rm -f "$MARK_CLEAN" /tmp/fastshared-appicon-bg.png' EXIT
python3 clean_mark.py "$MARK_SRC" "$MARK_CLEAN"

INK="#070318"
INK_2="#12082d"
MILK="#fffdf8"
CHARCOAL="#171323"
VIOLET="#9d7aff"

make_dark_bg() {
  local width=$1
  local height=$2
  local out=$3
  magick -size "${width}x${height}" "gradient:${INK_2}-${INK}" \
    \( -size "${width}x${height}" radial-gradient:"rgba(157,122,255,0.45)-rgba(157,122,255,0)" -resize "${width}x${height}!" \) \
    -gravity center -compose screen -composite -depth 8 -define png:color-type=2 "$out"
}

render_horizontal_lockup() {
  local width=$1
  local height=$2
  local bg=$3
  local text=$4
  local out=$5
  local text_x=760
  local text_y=495
  local dot_x=2054
  local mark_size=650

  if [[ "$bg" == "none" ]]; then
    magick -size "${width}x${height}" xc:none "$out"
  elif [[ "$bg" == "light" ]]; then
    magick -size "${width}x${height}" xc:"#fbf8f1" "$out"
  else
    make_dark_bg "$width" "$height" "$out"
  fi

  if [[ "$bg" == "light" ]]; then
    magick "$out" \
      \( appicon-1024.png -resize "${mark_size}x${mark_size}" \) -geometry +70+75 -composite \
      -font "$FONT" -pointsize 260 -fill "$CHARCOAL" -annotate +"${text_x}"+${text_y} "$text" \
      -font "$FONT" -pointsize 260 -fill "$VIOLET" -annotate +"${dot_x}"+${text_y} "." \
      -strip -define png:color-type=2 "$out"
  else
    magick "$out" \
      \( appicon-1024.png -resize "${mark_size}x${mark_size}" \) -geometry +70+75 -composite \
      -font "$FONT" -pointsize 260 -fill "$MILK" -annotate +"${text_x}"+${text_y} "$text" \
      -font "$FONT" -pointsize 260 -fill "$VIOLET" -annotate +"${dot_x}"+${text_y} "." \
      -strip "$out"
    if [[ "$bg" != "none" ]]; then
      magick "$out" -background "$INK" -alpha remove -alpha off -depth 8 -strip -define png:color-type=2 "$out"
    fi
  fi
}

echo "Generating master PNG assets..."

magick "$MARK_CLEAN" -resize 2048x2048 -strip logo-mark.png
magick "$MARK_CLEAN" -resize 1024x1024 -strip wordmark-mark.png

make_dark_bg 1024 1024 /tmp/fastshared-appicon-bg.png
magick /tmp/fastshared-appicon-bg.png "$MARK_SRC" -gravity center -compose over -composite \
  -background "$INK" -alpha remove -alpha off -depth 8 -strip -define png:color-type=2 appicon-1024.png

render_horizontal_lockup 2400 800 none fastshared logo-horizontal.png
render_horizontal_lockup 2400 800 dark fastshared wordmark-horizontal-dark.png
render_horizontal_lockup 2400 800 light fastshared wordmark-horizontal-light.png

make_dark_bg 1200 630 og-image.png
magick og-image.png \
  \( logo-horizontal.png -resize 1000x333 \) -gravity center -geometry +0-10 -compose over -composite \
  -background "$INK" -alpha remove -alpha off -depth 8 -strip -define png:color-type=2 og-image.png

echo "Generating Apple AppIcon set into $OUT/..."

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
  "ios-1024-dark      1024"
  "ios-1024-tinted    1024"
)

for row in "${SIZES[@]}"; do
  read -r name px <<<"$row"
  out="$OUT/${name}.png"
  magick appicon-1024.png -resize "${px}x${px}" \
    -background "$INK" -alpha remove -alpha off -depth 8 -strip -define png:color-type=2 "$out"
  printf "  %-20s %4dpx  %s\n" "$name" "$px" "$out"
done

printf "\nwrote %d app icons to %s/\n" "${#SIZES[@]}" "$OUT"
printf "copy web assets from brand/*.png and Apple icons from %s/*.png\n" "$OUT"
