#!/usr/bin/env bash
# Render brand/og-image.html to the 1200x630 social card, then check it against
# the design-intelligence pixel targets before letting it overwrite anything.
#
# Why headless Chrome and not ImageMagick (which export.sh uses for the icons):
# the card is typographic, and its whole point is being the same Bricolage
# Grotesque + JetBrains Mono as the site. Compositing text with `magick` would
# reproduce the layout but not the typeface, the stylistic alternates, or the
# optical size axis — so it would look adjacent to the brand instead of being it.
#
# Usage:
#   ./og-image.sh            # render, audit, and install into web/public + brand
#   ./og-image.sh --check    # render to a temp file and audit only; installs nothing
set -euo pipefail

cd "$(dirname "$0")"

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

CHROME=${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}
AUDIT=${AUDIT:-$HOME/.claude/skills/design-intelligence/scripts/pixel_audit.py}
SRC="$PWD/og-image.html"
TMP="$(mktemp -d)"
OUT="$TMP/og-image.png"
trap 'rm -rf "$TMP"' EXIT

if [[ ! -x "$CHROME" ]]; then
  echo "Google Chrome not found at: $CHROME" >&2
  echo "Override with CHROME=/path/to/chrome $0" >&2
  exit 1
fi

# --virtual-time-budget lets the webfonts finish loading before the capture; the
# stylesheet is requested with display=block so Chrome does not paint a fallback
# face first and bake the wrong typeface into the PNG.
"$CHROME" \
  --headless \
  --disable-gpu \
  --hide-scrollbars \
  --force-device-scale-factor=1 \
  --window-size=1200,630 \
  --virtual-time-budget=20000 \
  --screenshot="$OUT" \
  "file://$SRC" >/dev/null 2>&1

if [[ ! -s "$OUT" ]]; then
  echo "Render produced no output." >&2
  exit 1
fi

# Refuse to ship a card that is not 1200x630. Every consumer assumes it, and the
# og:image:width/height meta in Base.astro states it as fact.
read -r W H < <(python3 -c "
from PIL import Image
w, h = Image.open('$OUT').size
print(w, h)
")
if [[ "$W" != "1200" || "$H" != "630" ]]; then
  echo "Rendered $W x $H, expected 1200 x 630 — refusing to install." >&2
  exit 1
fi
echo "rendered ${W}x${H}"

if [[ -f "$AUDIT" ]]; then
  echo "-- pixel audit --"
  python3 "$AUDIT" "$OUT" | python3 -c "
import sys, json
d = json.loads(sys.stdin.readline())
lum = d['luminance']['mean']; std = d['contrast']['std']
sat = d['saturation']['mean']; dom = d['dominant_colors'][0]
ok = lambda c: 'ok  ' if c else 'FAIL'

# The saturation check is NOT a flat threshold, and the reason is measured rather
# than a matter of taste. HSV saturation is a ratio, so it is ill-conditioned in
# deep shadow: the ground token --cream #0f0f12 is (15,15,18), a 3/255 blue lift,
# which HSV reports as 0.167 saturated. With that ground covering ~85% of a card,
# the mean cannot go below ~0.14 no matter how neutral the design is — the flat
# 0.15 target from the skill is unreachable while staying faithful to the site's
# own token, and the only way to "pass" it would be to pick a ground the site does
# not use. That is exactly the drift this file was rebuilt to end.
#
# (The site itself measures 0.099 only because its screenshot pipeline shifted the
# ground to #111113, S=0.105. Capture artefact, not a different design.)
#
# So the question asked here is the one the metric was trying to ask: is the base
# neutral and the accent merely a point? If the mean sits at or below the ground's
# OWN saturation, every non-ground pixel is net-desaturating, which is a stronger
# result than any absolute number.
def own_sat(hexs):
    h = hexs.lstrip('#'); r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
    mx, mn = max(r, g, b), min(r, g, b)
    return 0.0 if mx == 0 else (mx - mn) / mx

ground = own_sat(dom['hex'])
sat_budget = ground + 0.02

print(f\"  {ok(lum < 60)} luminance      {lum:6.2f}   target < 60 (dark pole)\")
print(f\"  {ok(std >= 40)} contrast std   {std:6.2f}   target >= 40\")
print(f\"  {ok(dom['share'] >= 0.80)} dominant bg    {dom['share']*100:5.1f}%   target >= 80%  ({dom['hex']})\")
print(f\"  {ok(sat <= sat_budget)} saturation     {sat:6.3f}   target <= {sat_budget:.3f}\"
      f\"  (ground {dom['hex']} is itself {ground:.3f})\")
sys.exit(0 if (lum < 60 and std >= 40 and sat <= sat_budget and dom['share'] >= 0.80) else 1)
" || { echo "Pixel targets not met — refusing to install." >&2; exit 1; }
else
  echo "pixel_audit.py not found at $AUDIT — skipping the audit gate." >&2
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "--check: nothing installed."
  exit 0
fi

cp "$OUT" ./og-image.png
cp "$OUT" ../web/public/og-image.png
echo "installed -> brand/og-image.png and web/public/og-image.png"
cat <<'NOTE'

NOT LIVE YET. Committing and deploying is not enough for this asset.
/og-image.png is in APP_PATH_PREFIXES, so the apex is served by the Worker out of
caches.default with max-age=86400, immutable — a new card stays invisible at
fastsha.red for up to 24h per edge, and `immutable` stops scrapers revalidating.

  # origin gets it immediately:
  curl -s https://fastshared-web.pages.dev/og-image.png | shasum -a 256
  # apex may still be cached — compare, and read the headers:
  curl -sI https://fastsha.red/og-image.png | grep -iE 'cf-cache-status|age|content-length'

If they differ, purge that URL in Cloudflare, then re-scrape in the platform's own
card validator (unfurlers cache separately). See web/README.md.
NOTE
