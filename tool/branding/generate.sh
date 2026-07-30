#!/usr/bin/env bash
#
# Regenerates the launcher-icon and native-splash source PNGs from
# assets/branding/logo.svg, then runs the two generators that turn them into
# native resources.
#
#   ./tool/branding/generate.sh              # rasterise + generate native resources
#   ./tool/branding/generate.sh --png-only   # rasterise only
#
# Requires Chrome (used headless as the SVG rasteriser — the machine this was
# written on had no ImageMagick, Inkscape or rsvg). Override the binary with
# CHROME=/path/to/chrome if it is not in one of the probed locations.
#
#
# WHY THE SIZES ARE WHAT THEY ARE
#
# Each variant is a canvas, a tile inside it, and the logo at 72% of the tile.
# The tile percentage is the only number that varies, and none of the four are
# arbitrary:
#
#   icon_fg        tile 92%   Adaptive-icon foreground. flutter_launcher_icons
#                             wraps this in <inset 16%>, which stacks with any
#                             padding baked in here. A 60% tile — the intuitive
#                             choice — measured 39% mark-to-tile on device,
#                             against a 60-70% norm for launcher icons. 92%
#                             lands it at 60%. Do not "fix" this by adding
#                             padding; the inset already supplies it.
#
#   icon_legacy    tile 100%  Square icon for API < 26 and for iOS/web/Windows,
#                             which have no adaptive-icon concept and so get no
#                             inset. White ground, since the mark is
#                             green-on-white and not tintable.
#
#   splash_legacy  tile 100%  Launch screen for API < 31, composited over the
#                  radius 28% flat colour by flutter_native_splash. Rounded to match
#                             BrandMark in the app, so the native screen and the
#                             in-app splash look like the same thing.
#
#   splash_a12     tile 66%   Launch screen for API >= 31. Must fit a 768px
#                  radius 50% circle inside a 1152px canvas (flutter_native_splash's
#                             requirement); 66% = 760px, just inside it.
#
#                             The white disc is baked in rather than set via
#                             `icon_background_color`. That option maps to
#                             windowSplashScreenIconBackgroundColor, which stock
#                             Android draws as a circle but HyperOS draws as a
#                             hard-edged square (seen on a Redmi on API 36).
#                             Baking it takes the OEM out of the decision, and a
#                             disc is the shape to bake because the platform
#                             masks splash icons to a circle regardless.
#
# The 72% logo-within-tile is shared by all four and is just optical margin.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
svg="$root/assets/branding/logo.svg"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

png_only=0
[[ "${1:-}" == "--png-only" ]] && png_only=1

[[ -f "$svg" ]] || { echo "error: $svg not found" >&2; exit 1; }

# --- locate Chrome ---------------------------------------------------------
chrome="${CHROME:-}"
if [[ -z "$chrome" ]]; then
  for c in \
    "/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$(command -v google-chrome || true)" \
    "$(command -v chromium || true)"
  do
    [[ -n "$c" && -x "$c" ]] && { chrome="$c"; break; }
  done
fi
[[ -n "$chrome" && -x "$chrome" ]] || {
  echo "error: Chrome not found. Set CHROME=/path/to/chrome" >&2; exit 1; }

# Chrome here is a native Windows binary under Git Bash, so it needs Windows
# paths. MSYS rewrites POSIX paths in ordinary arguments, but leaves anything
# shaped like a URL alone — so `file:///tmp/tmp.XXXX/x.html` reaches Chrome
# verbatim, resolves to a nonexistent \tmp\... and quietly screenshots the blank
# error page instead of the logo. Converting explicitly avoids relying on those
# heuristics at all. No-op on Linux and macOS.
to_win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
work_win="$(to_win "$work")"
out_win="$(to_win "$here")"

cp "$svg" "$work/logo.svg"

# --- rasterise -------------------------------------------------------------
# shot <name> <canvas px> <tile %> <tile background> <tile border-radius>
shot() {
  local name=$1 canvas=$2 pct=$3 bg=$4 radius=$5
  cat > "$work/$name.html" <<EOF
<html><head><style>
  html,body{margin:0;padding:0;background:transparent}
  .canvas{width:${canvas}px;height:${canvas}px;display:flex;
          align-items:center;justify-content:center;background:transparent}
  .tile{width:${pct}%;height:${pct}%;display:flex;
        align-items:center;justify-content:center;
        background:${bg};border-radius:${radius}}
  img{width:72%;height:72%;display:block}
</style></head>
<body><div class="canvas"><div class="tile"><img src="logo.svg"></div></div></body></html>
EOF
  # --default-background-color=00000000 is what preserves alpha outside the
  # tile; without it the rounded corners come out opaque.
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --user-data-dir="$work_win/chrome-profile" \
    --no-first-run --no-default-browser-check \
    --force-color-profile=srgb \
    --default-background-color=00000000 \
    --screenshot="$out_win/$name.png" --window-size="$canvas,$canvas" \
    "file:///$work_win/$name.html" >/dev/null 2>&1
  [[ -s "$here/$name.png" ]] || { echo "error: $name.png not written" >&2; exit 1; }
  printf '  %-16s %sx%s\n' "$name.png" "$canvas" "$canvas"
}

echo "Rasterising from assets/branding/logo.svg"
shot icon_fg       1024  92 transparent 0
shot icon_legacy   1024 100 "#ffffff"   0
shot splash_legacy  512 100 "#ffffff"   "28%"
shot splash_a12    1152  66 "#ffffff"   "50%"

# --- sanity-check alpha ----------------------------------------------------
# The transparent-corner variants are the easy thing to get wrong, and it is
# invisible in most image viewers (they render alpha as white). Checked here so
# a broken rasterise fails loudly instead of shipping an opaque square.
if python -c "import PIL" >/dev/null 2>&1; then
  python - "$here" <<'PY'
import sys
from PIL import Image
d = sys.argv[1]
bad = []
for name in ("icon_fg", "splash_legacy", "splash_a12"):
    p = f"{d}/{name}.png"
    im = Image.open(p).convert("RGBA")
    if im.getpixel((0, 0))[3] != 0:
        bad.append(name)
if bad:
    sys.exit("error: opaque corners in " + ", ".join(bad)
             + " - alpha was lost (is a Chrome instance hijacking the flags?)")
print("  alpha ok (transparent corners preserved)")
PY
else
  echo "  (skipped alpha check — python+PIL unavailable)"
fi

if (( png_only )); then
  echo "Done (--png-only). Native resources not regenerated."
  exit 0
fi

# --- generate native resources --------------------------------------------
cd "$root"
echo "Generating launcher icons"
dart run flutter_launcher_icons
echo "Generating native splash"
dart run flutter_native_splash:create

cat <<'EOF'

Done. Both generators overwrite native files in android/, ios/, web/ and
windows/ — review `git status` before committing.

Verify on a device rather than by eye: the launcher mark should measure
roughly 60% of its tile width, and a cold start should stay brand green from
the native splash through to Login with no black frame.
EOF
