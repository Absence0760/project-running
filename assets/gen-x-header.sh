#!/usr/bin/env bash
#
# Render the X (Twitter) profile header (1500x500 PNG, X's recommended banner
# size) from its committed SVG source. Deterministic, idempotent, safe to
# re-run. Sibling of gen-feature-graphic.sh; the profile picture itself is
# icon_1024.png from gen-icons.sh.
#
# X overlaps the avatar on the banner's bottom-left corner (roughly x<400,
# y>330 at this size) and some clients trim the top and bottom edges, so the
# wordmark stays centred inside the y 90-410 band.
#
# Requires: inkscape.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$SCRIPT_DIR/x-header.svg"
OUT="$SCRIPT_DIR/x-header.png"

if [[ ! -f "$SVG" ]]; then
  echo "error: source not found at $SVG" >&2
  exit 1
fi
command -v inkscape >/dev/null 2>&1 || { echo "error: 'inkscape' not on PATH" >&2; exit 1; }

inkscape "$SVG" -w 1500 -h 500 -o "$OUT" >/dev/null 2>&1
echo "wrote $OUT (1500x500)"
