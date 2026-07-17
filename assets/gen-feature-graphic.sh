#!/usr/bin/env bash
#
# Render the Play Store feature graphic (1024x500 PNG, required by the
# store listing — see apps/mobile_android/deployment.md) from its committed
# SVG source. Deterministic, idempotent, safe to re-run. Sibling of
# gen-icons.sh, which owns the square app-icon pipeline.
#
# Requires: inkscape.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$SCRIPT_DIR/feature-graphic.svg"
OUT="$SCRIPT_DIR/feature-graphic.png"

if [[ ! -f "$SVG" ]]; then
  echo "error: source not found at $SVG" >&2
  exit 1
fi
command -v inkscape >/dev/null 2>&1 || { echo "error: 'inkscape' not on PATH" >&2; exit 1; }

inkscape "$SVG" -w 1024 -h 500 -o "$OUT" >/dev/null 2>&1
echo "wrote $OUT (1024x500)"
