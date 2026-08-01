#!/usr/bin/env bash
#
# watch-view.sh — open a live, clickable watch window on the running sim.
#
# The --gui flag needs a Renode build that can start its own UI, and the
# macOS arm64 .NET build cannot (renode/renode#886: "Couldn't start UI -
# falling back to console mode"). This is the route that works everywhere:
# start the sim headless (bin/watch-sim.sh), then attach this viewer — a Tk
# window that polls the display model's DumpCanvas over the telnet monitor
# and maps clicks on the drawn keys to the virtual-time button macros.
#
# Left-click taps a key; right-click / ctrl-click holds it (BTN3/BTN4: page
# grid, BTN5: mark waypoint). Keys 1-5 tap, shift+key holds. Closing the
# window detaches; the sim keeps running.
#
# Usage:
#   bin/watch-sim.sh &            # or in another terminal
#   bin/watch-view.sh             # attach to the most recent running sim
#   bin/watch-view.sh <port>      # attach to an explicit monitor port

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"

PORT="${1:-}"
if [[ -z "$PORT" ]]; then
	LATEST_LINK="$(watch_sim_latest_link)"
	[[ -e "$LATEST_LINK" ]] || \
		fatal "no watch sim running from this checkout ($REPO_ROOT) — start one first: bin/watch-sim.sh"
	RUN_DIR="$(readlink -f "$LATEST_LINK")"
	[[ -f "$RUN_DIR/monitor.port" ]] || \
		fatal "no monitor.port in $RUN_DIR — restart the sim with bin/watch-sim.sh"
	RENODE_PID="$(cat "$RUN_DIR/renode.pid" 2>/dev/null || true)"
	if [[ -z "$RENODE_PID" ]] || ! kill -0 "$RENODE_PID" 2>/dev/null; then
		fatal "the last sim ($RUN_DIR) is no longer running — start one: bin/watch-sim.sh"
	fi
	PORT="$(cat "$RUN_DIR/monitor.port")"
fi

# tkinter ships separately from python on Homebrew (python-tk@X.Y); probe for
# a python that actually has it rather than failing inside the viewer.
PYTHON=""
for candidate in python3 python3.13 python3.12; do
	if command -v "$candidate" >/dev/null && "$candidate" -c 'import tkinter' 2>/dev/null; then
		PYTHON="$candidate"
		break
	fi
done
[[ -n "$PYTHON" ]] || fatal "no python with tkinter found — brew install python-tk@3.13 (CLAUDE.md § Specific tool decisions)"

step "Opening the live watch window (monitor port $PORT)"
dim "left-click = tap, right/ctrl-click = hold, keys 1-5 (+shift) — closing the window leaves the sim running"
exec "$PYTHON" "$WORKSPACE/sim/live_view.py" --port "$PORT" --title "custom_watch sim (:$PORT)"
