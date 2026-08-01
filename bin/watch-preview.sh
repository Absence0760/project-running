#!/usr/bin/env bash
#
# watch-preview.sh — render every host-composed watch page as a PNG, plus a
# contact sheet, with no Renode and no board.
#
# The render crate's preview tests (render/src/preview.rs) compose each page
# the way the ui task does and, with WATCH_PREVIEW_DIR set, dump the panel as
# a 1:1 P6 PPM per page. This wraps that: run the previews, convert each PPM
# to a crisp PNG (nearest-neighbour upscale), and montage a contact sheet so
# the whole UI is one scannable image.
#
# This is the host rung of the viewing story — the same compositions the
# tests pin, without booting a firmware. bin/watch-shots.sh remains the sim
# rung: it captures what the *firmware* actually drew, page by page, and
# needs renode + defmt-print. Layout review belongs here; "did the firmware
# compose it" belongs there.
#
# Usage:
#   bin/watch-preview.sh                       # -> /tmp/watch-preview
#   bin/watch-preview.sh --out-dir docs/shots  # somewhere durable
#   bin/watch-preview.sh --zoom 4              # 4x PNGs (default 3x)

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"
OUT_DIR="${TMPDIR:-/tmp}/watch-preview"
ZOOM=3

while [[ $# -gt 0 ]]; do
	case "$1" in
	--out-dir)
		OUT_DIR="$2"
		shift 2
		;;
	--zoom)
		ZOOM="$2"
		shift 2
		;;
	*)
		fatal "Unknown argument: $1 (supported: --out-dir DIR, --zoom N)"
		;;
	esac
done

if [[ ! -f "$WORKSPACE/Cargo.toml" ]]; then
	fatal "apps/custom_watch/ Cargo workspace not scaffolded yet. See $WORKSPACE/README.md step 2."
fi

need_cmd cargo
need_cmd rustc
need_cmd magick

HOST_TRIPLE="$(rustc -vV | sed -n 's|host: ||p')"
if [[ -z "$HOST_TRIPLE" ]]; then
	fatal "Could not detect host target triple via 'rustc -vV'."
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.ppm "$OUT_DIR"/*.png

cd "$WORKSPACE"
WATCH_PREVIEW_DIR="$OUT_DIR" cargo test \
	--target "$HOST_TRIPLE" \
	-p watch_render \
	preview

shopt -s nullglob
ppms=("$OUT_DIR"/*.ppm)
if [[ ${#ppms[@]} -eq 0 ]]; then
	fatal "No previews were dumped — did the preview tests run?"
fi

for ppm in "${ppms[@]}"; do
	magick "$ppm" -scale "$((ZOOM * 100))%" \
		-bordercolor '#14171d' -border 10 "${ppm%.ppm}.png"
	rm -f "$ppm"
done

# Grid via +append/-append rather than `montage`, which insists on resolving
# a label font even with labels off and fails on ImageMagick builds without
# a default font configured.
pngs=("$OUT_DIR"/*.png)
rows=()
for ((i = 0; i < ${#pngs[@]}; i += 4)); do
	row="$OUT_DIR/.row$i.png"
	magick "${pngs[@]:i:4}" -background '#14171d' +append "$row"
	rows+=("$row")
done
magick "${rows[@]}" -background '#14171d' -append "$OUT_DIR/contact-sheet.png"
rm -f "$OUT_DIR"/.row*.png

echo "${#ppms[@]} pages rendered. Open $OUT_DIR/contact-sheet.png"
