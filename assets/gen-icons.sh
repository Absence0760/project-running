#!/usr/bin/env bash
#
# Regenerate EVERY platform app-icon PNG from the single source of truth,
# assets/icon.svg. Deterministic, idempotent, safe to re-run.
#
# Each target is the full 1024x1024 master rendered (or downscaled) to that
# target's exact committed pixel size — the design is never altered here.
#
# Requires: inkscape (render SVG -> PNG at size) and ImageMagick 7 (magick).
#
set -euo pipefail

# Resolve this script's own directory so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SVG="$SCRIPT_DIR/icon.svg"

# iOS / watchOS require opaque icons (no alpha). The master's top-left gradient
# stop is the flatten backdrop; the master is fully opaque so this is lossless.
OPAQUE_BG="#FE5932"

if [[ ! -f "$SVG" ]]; then
  echo "error: master not found at $SVG" >&2
  exit 1
fi
for tool in inkscape magick; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: '$tool' not on PATH" >&2; exit 1; }
done

# render_png <size> <out> — full master rendered from the SVG at <size>x<size>,
# alpha channel preserved.
render_png() {
  local size="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  inkscape "$SVG" -w "$size" -h "$size" -o "$out" >/dev/null 2>&1
  echo "  wrote $out (${size}x${size})"
}

# render_opaque <size> <out> — same, but flattened onto an opaque background and
# stripped of any alpha channel (App Store / watchOS requirement).
render_opaque() {
  local size="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  inkscape "$SVG" -w "$size" -h "$size" -o "$out" >/dev/null 2>&1
  # -alpha remove/off drops the alpha semantics; forcing TrueColor (png color
  # type 2) stops ImageMagick from auto-optimising small icons into an indexed
  # palette PNG that still carries a tRNS transparency chunk (Apple rejects any
  # icon with alpha, indexed or not).
  magick "$out" -background "$OPAQUE_BG" -alpha remove -alpha off \
    -define png:color-type=2 "$out"
  echo "  wrote $out (${size}x${size}, opaque)"
}

# dims_of <png> — echo the current pixel size (square) of an existing PNG.
dims_of() {
  magick identify -format '%w' "$1"
}

echo "Regenerating app icons from $SVG"

# 1. Master roundtrip -------------------------------------------------------
echo "[master]"
render_png 1024 "$SCRIPT_DIR/icon_1024.png"

# 2. Web --------------------------------------------------------------------
echo "[web]"
WEB="$REPO_ROOT/apps/web/static"
render_png 32  "$WEB/favicon.png"
render_png 180 "$WEB/apple-touch-icon.png"
render_png 192 "$WEB/icon-192.png"
render_png 512 "$WEB/icon-512.png"

# 3. Garmin (size read from the existing file) ------------------------------
echo "[garmin]"
GARMIN="$REPO_ROOT/apps/watch_garmin/resources/drawables/launcher_icon.png"
render_png "$(dims_of "$GARMIN")" "$GARMIN"

# 4. Android mobile mipmaps -------------------------------------------------
echo "[mobile_android]"
ANDROID_RES="$REPO_ROOT/apps/mobile_android/android/app/src/main/res"
declare -A ANDROID_MIPMAP=(
  [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192
)
for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  render_png "${ANDROID_MIPMAP[$density]}" \
    "$ANDROID_RES/mipmap-$density/ic_launcher.png"
done

# 5. Wear OS mipmaps (both files, size read from each existing file) ---------
echo "[watch_wear]"
WEAR_RES="$REPO_ROOT/apps/watch_wear/android/app/src/main/res"
for f in "$WEAR_RES"/mipmap-*/ic_launcher.png "$WEAR_RES"/mipmap-*/ic_launcher_foreground.png; do
  render_png "$(dims_of "$f")" "$f"
done

# 6. iOS mobile app icon set (data-driven, opaque) --------------------------
echo "[mobile_ios]"
IOS_SET="$REPO_ROOT/apps/mobile_ios/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for f in "$IOS_SET"/*.png; do
  render_opaque "$(dims_of "$f")" "$f"
done

# 7. watchOS app icon set (data-driven, opaque) -----------------------------
echo "[watch_ios]"
WATCHOS_SET="$REPO_ROOT/apps/watch_ios/WatchApp/Assets.xcassets/AppIcon.appiconset"
for f in "$WATCHOS_SET"/*.png; do
  render_opaque "$(dims_of "$f")" "$f"
done

echo "Done."
