#!/usr/bin/env bash
#
# watch-monitor.sh — attach an interactive Renode monitor to the running
# watch sim (started by bin/watch-sim.sh, headless or --gui). The sim's
# monitor lives on a per-run telnet port, not in a window — this finds it
# via the watch-sim.latest pointer and connects. Button macros, one clean
# press each:
#
#   runMacro $btn1    start / pause / resume the recording
#   runMacro $btn2    stop the recording
#   runMacro $btn3    cycle the run-view page (dashboard/distance/pace/lap/zones/pacer)
#   runMacro $btn4    manual lap
#
# Any other monitor command works too, e.g.:
#   sysbus.spi3.display DumpFrame "/tmp/frame.ppm"
#
# Ctrl-C (or Ctrl-D) detaches; the sim keeps running.
#
# Usage:
#   bin/watch-monitor.sh          # attach to the most recent running sim
#   bin/watch-monitor.sh <port>   # attach to an explicit monitor port
#
# Requires: ncat (Fedora: dnf install nmap-ncat).

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

need_cmd ncat

PORT="${1:-}"
if [[ -z "$PORT" ]]; then
	LATEST_LINK="${TMPDIR:-/tmp}/watch-sim.latest"
	[[ -e "$LATEST_LINK" ]] || \
		fatal "no watch sim found — start one first: bin/watch-sim.sh --gui"
	RUN_DIR="$(readlink -f "$LATEST_LINK")"
	[[ -f "$RUN_DIR/monitor.port" ]] || \
		fatal "no monitor.port in $RUN_DIR — the sim predates watch-monitor.sh; restart it with bin/watch-sim.sh"
	RENODE_PID="$(cat "$RUN_DIR/renode.pid" 2>/dev/null || true)"
	if [[ -z "$RENODE_PID" ]] || ! kill -0 "$RENODE_PID" 2>/dev/null; then
		fatal "the last sim ($RUN_DIR) is no longer running — start one: bin/watch-sim.sh --gui"
	fi
	PORT="$(cat "$RUN_DIR/monitor.port")"
fi

step "Attaching to the Renode monitor on localhost:$PORT"
dim "buttons: runMacro \$btn1 (start/pause), \$btn2 (stop), \$btn3 (page), \$btn4 (lap)"
dim "Ctrl-C detaches; the sim keeps running"
exec ncat localhost "$PORT"
