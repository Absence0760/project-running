#!/usr/bin/env bash
#
# watch-sim.sh — boot the custom_watch firmware on an emulated nRF52840 DK
# (Renode, no hardware) and stream decoded defmt logs until Ctrl-C, feeding
# the canned NMEA fixture into the emulated GPS UART on a loop.
#
# The ELF is the same thumbv7em build watch-flash.sh flashes, plus three sim
# features: `sim-autostart` (start recording on the first fix so a run records
# without a button), `sim-buttons` (poll the button pins so BTN1-4 presses
# work — clicked on the --gui window's bezel, or injected via the watch.resc
# btn1..btn4 monitor macros: BTN1 start/pause, BTN2 stop, BTN3 page / idle
# GNSS mode, BTN4 lap), and `sim-course` (the canned breadcrumb course the Nav
# page follows; the bench_jog fixture leaves it on two legs so the off-course
# alert fires each lap). What you can't simulate: BLE (nrf-softdevice needs
# the real radio), power draw, GPS/HR analog behaviour. See
# apps/custom_watch/local_testing.md § Simulating without a board.
#
# Usage:
#   bin/watch-sim.sh                      # build + simulate the default binary
#   bin/watch-sim.sh --gui                # also open the live watch-screen window
#   bin/watch-sim.sh --bin sensor_smoke   # simulate a specific binary
#   bin/watch-sim.sh --nmea path/to.nmea  # substitute the GPS fixture
#   bin/watch-sim.sh --no-autostart       # boot idle; BTN1 starts the run, so the
#                                         # idle face (BTN3 GNSS-mode cycling) is
#                                         # reachable before recording begins
#
# Requires: renode (workstation CLAUDE.md § Specific tool decisions) and
# defmt-print (cargo install defmt-print --locked). No board, no probe-rs.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"
BIN=app
NMEA_FILE="$WORKSPACE/sim/nmea/bench_jog.nmea"
GUI=0
PHONE_PORT=7788
AUTOSTART=1

while [[ $# -gt 0 ]]; do
	case "$1" in
		--gui)          GUI=1; shift ;;
		--bin)          BIN="${2:?--bin needs a value}"; shift 2 ;;
		--nmea)         NMEA_FILE="${2:?--nmea needs a value}"; shift 2 ;;
		--phone-port)   PHONE_PORT="${2:?--phone-port needs a value}"; shift 2 ;;
		--no-autostart) AUTOSTART=0; shift ;;
		*) fatal "unknown argument: $1 (supported: --gui, --bin <name>, --nmea <file>, --phone-port <port>, --no-autostart)" ;;
	esac
done

if [[ ! -f "$WORKSPACE/Cargo.toml" ]]; then
	fatal "apps/custom_watch/ Cargo workspace not scaffolded yet. See $WORKSPACE/README.md step 2."
fi

need_cmd cargo
need_cmd renode
command -v defmt-print >/dev/null || \
	fatal "defmt-print not on PATH — install with: cargo install defmt-print --locked"
[[ -f "$NMEA_FILE" ]] || fatal "NMEA fixture not found: $NMEA_FILE"

# sim-autostart: start the run on the first fix so distance accrues without a
# button (dropped by --no-autostart, which leaves the sim on the idle face —
# BTN3 there cycles the GNSS mode — until a BTN1 press starts the run).
# sim-buttons: poll the button pins so the watch.resc btn1/btn2/btn3 macros
# work (Renode's GPIO models the IN register but not the SENSE/DETECT edge
# path the hardware button task waits on). sim-course: the canned breadcrumb
# course the Nav page follows (the bench_jog fixture leaves it on two legs,
# so the off-course alert fires each lap). All OFF on the hardware build —
# see apps/custom_watch/app/src/tasks/{record,button,nav}.rs.
FEATURES=sim-buttons,sim-course,dev-blink
[[ "$AUTOSTART" == 1 ]] && FEATURES="sim-autostart,$FEATURES"
step "Building firmware (release, --features $FEATURES)"
(cd "$WORKSPACE" && cargo build --release --bin "$BIN" --features "$FEATURES")
ELF="$WORKSPACE/target/thumbv7em-none-eabihf/release/$BIN"
[[ -f "$ELF" ]] || fatal "build produced no ELF at $ELF"

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/watch-sim.XXXXXX")"
LATEST_LINK="${TMPDIR:-/tmp}/watch-sim.latest"
DEFMT_RAW="$RUN_DIR/defmt.raw"
GPS_PTY="$RUN_DIR/gps-pty"
RENODE_LOG="$RUN_DIR/renode.log"
: > "$DEFMT_RAW"

RENODE_PID=""
cleanup() {
	trap - INT TERM EXIT
	# /usr/bin/renode is a shell wrapper around dotnet — killing the wrapper
	# alone leaves Renode.dll running (and holding its monitor port), so also
	# kill the real PID that Renode wrote to the pid-file.
	[[ -f "$RUN_DIR/renode.pid" ]] && kill "$(cat "$RUN_DIR/renode.pid")" 2>/dev/null
	[[ -n "$RENODE_PID" ]] && kill "$RENODE_PID" 2>/dev/null
	kill $(jobs -p) 2>/dev/null
	wait 2>/dev/null
	[[ "$(readlink -f "$LATEST_LINK" 2>/dev/null)" == "$(readlink -f "$RUN_DIR")" ]] && rm -f "$LATEST_LINK"
	dim "sim artifacts kept in $RUN_DIR (renode.log, defmt.raw)"
	exit 0
}
trap cleanup INT TERM EXIT

# Per-run monitor port: the default (1234) collides across concurrent or
# stale sim instances and Renode aborts on AddressAlreadyInUse. The telnet
# monitor also lets you poke the machine mid-run:
#   ncat localhost <port>   then e.g.:  sysbus.spi3.display DumpFrame "/tmp/f.ppm"
# bin/watch-monitor.sh attaches here without knowing the port — it follows
# the watch-sim.latest pointer to this run dir and reads monitor.port.
MONITOR_PORT=$(( 20000 + RANDOM % 20000 ))
RENODE_FLAGS=(-P "$MONITOR_PORT" --pid-file "$RUN_DIR/renode.pid")
echo "$MONITOR_PORT" > "$RUN_DIR/monitor.port"
ln -sfn "$RUN_DIR" "$LATEST_LINK"
RENODE_CMDS="\$elf=@$ELF; \$defmt_out=@$DEFMT_RAW; \$gps_pty=@$GPS_PTY; \$phone_port=$PHONE_PORT; include @$WORKSPACE/sim/watch.resc"
if [[ "$GUI" == 1 ]]; then
	step "Starting Renode (GUI — watch screen in a window, BTN1-4 clickable under the LCD)"
	RENODE_CMDS+="; showAnalyzer sysbus.spi3.display"
else
	step "Starting Renode (headless)"
	RENODE_FLAGS+=(--disable-xwt --hide-analyzers)
fi
renode "${RENODE_FLAGS[@]}" -e "$RENODE_CMDS" >"$RENODE_LOG" 2>&1 &
RENODE_PID=$!

# The pty symlink appearing means the emulation script ran to completion.
# Generous timeout: the first run in a Renode process also compiles the C#
# display model, which adds several seconds.
for _ in $(seq 1 150); do
	[[ -e "$GPS_PTY" ]] && break
	if ! kill -0 "$RENODE_PID" 2>/dev/null; then
		tail -n 30 "$RENODE_LOG" >&2
		fatal "Renode exited during startup — full log: $RENODE_LOG"
	fi
	sleep 0.2
done
[[ -e "$GPS_PTY" ]] || fatal "Renode never created the GPS pty — check $RENODE_LOG (monitor errors don't reach the log; re-run the include under 'renode --console' to see them)"
grep -q "defmt-rtt drain active" "$RENODE_LOG" || \
	fatal "defmt-rtt drain did not arm — check $RENODE_LOG and sim/defmt_rtt.py (must stay ASCII-only for Renode's IronPython)"
ok "Renode up — log: $RENODE_LOG, monitor: bin/watch-monitor.sh (ncat localhost $MONITOR_PORT)"
dim "buttons: click BTN1-4 in the --gui window, or in the monitor run  runMacro \$btn1 (start/pause), \$btn2 (stop), \$btn3 (page / idle GNSS mode), \$btn4 (lap)"

# Feed the fixture into the emulated GPS UART on a loop. Sentences come in
# GGA+RMC pairs per GPS second; two lines per wall-clock second matches the
# 1 Hz fix rate a real MAX-M10S emits.
(
	exec 3>"$GPS_PTY"
	while true; do
		while IFS= read -r line; do
			printf '%s\r\n' "$line" >&3
			sleep 0.5
		done < "$NMEA_FILE"
	done
) 2>/dev/null &

step "Streaming defmt logs (Ctrl-C to stop)"
dim "NMEA feed: $NMEA_FILE -> sysbus.uart0 at 1 Hz"
dim "phone link: tcp://localhost:$PHONE_PORT (Android emulator: 10.0.2.2:$PHONE_PORT) — try: ncat localhost $PHONE_PORT"
# Backgrounded + wait rather than a foreground pipeline: bash defers traps
# while a foreground job runs, so Ctrl-C/TERM would never reach cleanup and
# Renode would outlive the script.
tail -c +1 -f "$DEFMT_RAW" | defmt-print -e "$ELF" &
wait $!
