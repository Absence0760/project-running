#!/usr/bin/env bash
#
# watch-shots.sh — screenshot every custom_watch screen the Renode sim can arm
# and write them out as PNGs plus a self-contained HTML contact sheet.
#
# The sim's panel dumps have always existed for CI to assert "not blank"
# (sim/ci_smoke.py); this makes them viewable. One run boots the sim twice —
# once mid-run to walk the BTN4 page cycle, once --no-autostart for the idle
# faces and the settings menu — and lays every screen out on one page, so a
# layout regression is something you can see instead of something a human has
# to catch while paging through 30-odd screens by hand in --gui.
#
# Each capture is named by the firmware's own log line (`ui: page <Name>`), so
# the file name is the firmware's claim about what it composed, not a guess.
# What a capture proves is exactly what ci_smoke.py's dumps prove: that page
# rendered and inked pixels. Glyph and layout correctness are host-test claims
# (apps/custom_watch/render/src/preview.rs).
#
# Usage:
#   bin/watch-shots.sh                        # both sessions -> /tmp/watch-shots
#   bin/watch-shots.sh --session run          # only the run-view page cycle
#   bin/watch-shots.sh --session idle         # only the idle faces + menu
#   bin/watch-shots.sh --out-dir /path/shots  # somewhere durable
#
# Takes several minutes: two Renode boots, and the run session waits on the
# emulated baro accumulating enough gain to open a climb.
#
# Requires: renode, defmt-print, cargo (as bin/watch-sim.sh does) plus
# ImageMagick 7 (`magick`) for the PPM -> PNG conversion.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"

if [[ ! -f "$WORKSPACE/sim/screenshots.py" ]]; then
	fatal "apps/custom_watch/sim/screenshots.py is missing."
fi

need_cmd python3
need_cmd magick

step "Capturing custom_watch sim screens"
exec python3 "$WORKSPACE/sim/screenshots.py" "$@"
