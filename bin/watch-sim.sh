#!/usr/bin/env bash
#
# watch-sim.sh — boot the custom_watch firmware on an emulated nRF52840 DK
# (Renode, no hardware) and stream decoded defmt logs until Ctrl-C, feeding
# the canned NMEA fixture into the emulated GPS UART on a loop.
#
# The ELF is the same thumbv7em build watch-flash.sh flashes, plus three sim
# features: `sim-autostart` (start recording on the first fix so a run records
# without a button), `sim-buttons` (poll the button pins so BTN1-5 presses
# work — clicked on the --gui window's bezel, or injected via the watch.resc
# btn1..btn5 monitor macros: BTN1 start/pause/resume + dismiss-home from FIN,
# BTN2 stop (press twice), BTN3 page left / idle GNSS mode, BTN4 page right /
# idle diagnostics toggle, BTN5 lap / idle settings menu — decisions §350 +
# §351), and `sim-course` (the
# canned breadcrumb course the Nav page follows; the bench_jog fixture leaves
# it on two legs so the off-course alert fires each lap). What you can't
# simulate: BLE (nrf-softdevice needs the real radio), power draw, GPS/HR
# analog behaviour. See apps/custom_watch/local_testing.md § Simulating
# without a board.
#
# Usage:
#   bin/watch-sim.sh                      # build + simulate the default binary
#   bin/watch-sim.sh --gui                # also open the live watch-screen window
#   bin/watch-sim.sh --bin app            # simulate a named binary (`app` is the only one today)
#   bin/watch-sim.sh --fixture mountain_loop  # a named fixture from sim/nmea/
#   bin/watch-sim.sh --nmea path/to.nmea  # substitute the GPS fixture (full path)
#   bin/watch-sim.sh --no-autostart       # boot idle; BTN1 starts the run, so the
#                                         # idle face (BTN3 GNSS-mode cycling) is
#                                         # reachable before recording begins
#   bin/watch-sim.sh --storm              # compress the § 376 storm window to 60 s
#                                         and arm the banner, so a scripted
#                                         pressure fall is readable inside a
#                                         scenario's budget
#   bin/watch-sim.sh --no-alerts          # drop the sim's shortened alert
#                                         # cadences (fuel / distance / time /
#                                         # pace), so no banner covers the hero
#                                         # rows — what watch-shots.sh wants
#   bin/watch-sim.sh --no-course          # drop the canned breadcrumb course.
#                                         # The course-driven alerts (§381 off-
#                                         # course, §380 cutoff) arm on data
#                                         # presence, not a setter, so this is
#                                         # the only way to unarm them
#   bin/watch-sim.sh --no-workout         # drop the canned 5-step demo workout.
#                                         # Its step banners (§354) are alerts
#                                         # a setter cannot silence either
#
# A scenario boots only the rails it asserts on and sheds the rest through these
# three flags — sim/ci_smoke.py derives them from SCENARIO_ARMED_RAILS rather
# than listing exclusions. That is about keeping ONE writer on the single alert
# slot a scenario reads, not about finding a quiet window: since decisions.md
# § 465 the engine itself guarantees the page comes back between banners
# (watch_core::alerts::ALERT_QUIET_S), whatever is armed.
#
# The default GPS fixture is sim/nmea/bench_jog.nmea. Select another named
# fixture from sim/nmea/ with --fixture <name> (or the NMEA_FIXTURE env var);
# --nmea <full-path> still overrides with an arbitrary file. bench_jog stays
# the default when none is given.
#
# Requires: renode (workstation CLAUDE.md § Specific tool decisions) and
# defmt-print (cargo install defmt-print --locked). No board, no probe-rs.
#
# For a non-interactive run that asserts on the output instead of streaming it
# (what CI's sim-firmware job runs), see apps/custom_watch/sim/ci_smoke.py — it
# drives this script and reads its combined output, so the contract it depends
# on is the "Streaming defmt logs" line, the WATCH_SIM_LATEST pointer, and the
# run dir's monitor.port / renode.log / defmt.raw.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"
BIN=app
NMEA_FILE="$WORKSPACE/sim/nmea/bench_jog.nmea"
# NMEA_FIXTURE selects a named fixture from sim/nmea/<name>.nmea (default:
# bench_jog). --fixture overrides it; --nmea overrides both with a full path.
[[ -n "${NMEA_FIXTURE:-}" ]] && NMEA_FILE="$WORKSPACE/sim/nmea/${NMEA_FIXTURE}.nmea"
GUI=0
GUI_VIEWER=0
PHONE_PORT=7788
AUTOSTART=1
ALERTS=1
COURSE=1
WORKOUT=1
SCREENS=0
STORM=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--gui)          GUI=1; shift ;;
		--bin)          BIN="${2:?--bin needs a value}"; shift 2 ;;
		--fixture)      NMEA_FILE="$WORKSPACE/sim/nmea/${2:?--fixture needs a value}.nmea"; shift 2 ;;
		--nmea)         NMEA_FILE="${2:?--nmea needs a value}"; shift 2 ;;
		--phone-port)   PHONE_PORT="${2:?--phone-port needs a value}"; shift 2 ;;
		--no-autostart) AUTOSTART=0; shift ;;
		--no-alerts)    ALERTS=0; shift ;;
		--no-course)    COURSE=0; shift ;;
		--no-workout)   WORKOUT=0; shift ;;
		--screens)      SCREENS=1; shift ;;
		--storm)        STORM=1; shift ;;
		*) fatal "unknown argument: $1 (supported: --gui, --bin <name>, --fixture <name>, --nmea <file>, --phone-port <port>, --no-autostart, --no-alerts, --no-course, --no-workout, --screens, --storm)" ;;
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
# sim-buttons: poll the button pins so the watch.resc btn1..btn5 macros
# work (Renode's GPIO models the IN register but not the SENSE/DETECT edge
# path the hardware button task waits on). sim-course: the canned breadcrumb
# course the Nav page follows (the bench_jog fixture leaves it on two legs,
# so the off-course alert fires each lap). sim-workout: the canned 5-step demo
# workout whose step banners drive the Workout page (dropped by --no-workout —
# the banners are unconditional alerts, so a quiet-slot scenario sheds them the
# way --no-course sheds the course arms). sim-alerts: the shortened fuel /
# distance / time / pace cadences the `alerts` scenario observes (dropped by
# --no-alerts, which is how a screenshot walk gets a watch with nothing
# covering the hero rows). sim-screens: three canned composed data screens
# (§364, one per layout), OFF unless --screens asks for them — they seat
# immediately after the Dashboard, so leaving them on would shift every other
# scenario's page walk. sim-storm: the § 376 tracker on a 60 s window instead
# of three hours, plus the banner armed, OFF unless --storm asks — a
# compressed window would have every other scenario reporting a tendency off a
# minute of air. All OFF on the hardware build —
# see apps/custom_watch/app/src/tasks/{record,button,nav}.rs.
# log-personal-data: the fix coordinates + BPM in the defmt stream, which
# sim/ci_smoke.py asserts on. Safe to enable HERE and nowhere else — the sim's
# fixture coordinates are the synthetic bench_jog rectangle and no one is
# wearing anything. A bench build keeps it off; see docs/custom_watch/privacy.md.
FEATURES=sim-buttons,dev-blink,log-personal-data
[[ "$COURSE" == 1 ]] && FEATURES="sim-course,$FEATURES"
[[ "$WORKOUT" == 1 ]] && FEATURES="sim-workout,$FEATURES"
[[ "$STORM" == 1 ]] && FEATURES="sim-storm,$FEATURES"
[[ "$SCREENS" == 1 ]] && FEATURES="sim-screens,$FEATURES"
[[ "$ALERTS" == 1 ]] && FEATURES="sim-alerts,$FEATURES"
[[ "$AUTOSTART" == 1 ]] && FEATURES="sim-autostart,$FEATURES"
step "Building firmware (release, --features $FEATURES)"
(cd "$WORKSPACE" && cargo build --release --bin "$BIN" --features "$FEATURES")
ELF="$WORKSPACE/target/thumbv7em-none-eabihf/release/$BIN"
[[ -f "$ELF" ]] || fatal "build produced no ELF at $ELF"

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/watch-sim.XXXXXX")"
LATEST_LINK="$(watch_sim_latest_link)"
DEFMT_RAW="$RUN_DIR/defmt.raw"
GPS_PTY="$RUN_DIR/gps-pty"
RENODE_LOG="$RUN_DIR/renode.log"
: > "$DEFMT_RAW"

RENODE_PID=""
cleanup() {
	# The status that is ending the script, read before anything below can
	# overwrite it (a caller may override it — see the INT trap). This used to
	# be `exit 0` unconditionally, so every `fatal` above reported SUCCESS to
	# whatever launched the sim: sim/ci_smoke.py could only notice a failed
	# launch by an effect that never appeared, and said so as "exited early
	# with status 0".
	local status="${1:-$?}"
	# Ignore further signals rather than resetting to default: pnpm forwards
	# its own SIGINT right behind the tty's group-wide one (a second Ctrl-C
	# does the same), and with the trap reset that second INT kills the
	# script on this very line — before the Renode kill below — orphaning
	# the emulator on the phone port.
	trap '' INT TERM HUP
	trap - EXIT
	# Teardown is not `set -e`'s business. Every step below is best-effort — a
	# kill of a pid that has already gone, a `pkill` with no children left to
	# find — and under `set -e` the first one to return non-zero abandoned the
	# REST of the teardown. `pkill` returning 1 (nothing left to sweep) is the
	# common case, and it skipped both the `wait` and the removal of the
	# latest-run pointer, leaving the next session following a symlink into a
	# dead run directory.
	set +e
	# /usr/bin/renode is a shell wrapper around dotnet — killing the wrapper
	# alone leaves Renode.dll running (and holding its monitor port), so also
	# kill the real PID that Renode wrote to the pid-file.
	[[ -f "$RUN_DIR/renode.pid" ]] && kill "$(cat "$RUN_DIR/renode.pid")" 2>/dev/null
	[[ -n "$RENODE_PID" ]] && kill "$RENODE_PID" 2>/dev/null
	# Not `kill $(jobs -p)`: that names only each job's leader, so the tail
	# half of the `tail | defmt-print` pipeline survived every run. Sweep all
	# remaining direct children instead.
	pkill -P $$ 2>/dev/null
	wait 2>/dev/null
	[[ "$(readlink -f "$LATEST_LINK" 2>/dev/null)" == "$(readlink -f "$RUN_DIR")" ]] && rm -f "$LATEST_LINK"
	dim "sim artifacts kept in $RUN_DIR (renode.log, defmt.raw)"
	exit "$status"
}
# HUP included: closing the terminal tab that ran the script would otherwise
# kill it without the trap, orphaning Renode still holding the phone port —
# the very stale instance the port claim below then has to wait out.
#
# INT is the exception that keeps its own status: Ctrl-C is how an interactive
# session ENDS rather than how it fails (the script streams until stopped, so
# there is no other way out), and `pnpm watch:sim` would print a lifecycle
# error on every normal stop otherwise.
trap 'cleanup 0' INT
trap cleanup TERM HUP EXIT

# Both ports below are CLAIMED, not checked. `ss` can only report who held a
# port a moment ago, and watch.resc binds them several seconds later — Renode
# compiles seven C# peripheral models on the way — so two sims launched inside
# that window both cleared the check and the loser's include aborted at the
# socket, leaving a pty that never appeared as the only symptom. An advisory
# lock per port, taken on a descriptor Renode inherits, answers the question a
# check cannot: who is allowed to bind it NEXT. It stays held for as long as
# anything in this session can still be holding the socket, so a second sim
# waits for the real release instead of racing it.
#
# `ss` stays, after the claim, for the holder no lock can coordinate with: a
# Renode orphaned by a killed session, or an unrelated program on the port.
PORT_LOCK_WAIT_S="${WATCH_SIM_PORT_WAIT_S:-45}"
HAVE_FLOCK=0
command -v flock >/dev/null && HAVE_FLOCK=1
if [[ "$HAVE_FLOCK" == 0 ]]; then
	# macOS ships no flock(1). The check below is all there is there, and it
	# is the check-then-use this claim exists to replace — say so rather than
	# leave the weaker guarantee looking like the strong one.
	warn "flock is not on PATH, so the phone port can only be CHECKED, not claimed — a sim starting alongside this one can still take port $PHONE_PORT out from under it"
fi

if [[ "$HAVE_FLOCK" == 1 ]]; then
	exec 8>"${TMPDIR:-/tmp}/watch-sim.phone-$PHONE_PORT.lock"
	if ! flock -n 8; then
		step "Another watch sim holds phone-link port $PHONE_PORT — waiting up to ${PORT_LOCK_WAIT_S}s for it to release"
		flock -w "$PORT_LOCK_WAIT_S" 8 || \
			fatal "phone-link port $PHONE_PORT is claimed by another watch sim that has not exited within ${PORT_LOCK_WAIT_S}s. Close it, or run this one with --phone-port $(( PHONE_PORT + 1 ))."
	fi
fi
PHONE_PORT_HOLDER="$(ss -tlnpH "sport = :$PHONE_PORT" 2>/dev/null || true)"
if [[ -n "$PHONE_PORT_HOLDER" ]]; then
	HOLDER_PID="$(grep -oP 'pid=\K[0-9]+' <<<"$PHONE_PORT_HOLDER" | head -1)"
	fatal "phone-link port $PHONE_PORT is already in use${HOLDER_PID:+ by pid $HOLDER_PID} and the holder is not a watch sim this one can wait for. Close its Renode window${HOLDER_PID:+ or 'kill $HOLDER_PID'}, or run this one with --phone-port $(( PHONE_PORT + 1 ))."
fi

# Per-run monitor port, under the same claim. It had none at all: a bare draw
# from a 20k-wide range, and Renode aborts on AddressAlreadyInUse with the same
# invisible symptom the phone port has. Unlike the phone port this one has no
# fixed value to honour, so a taken candidate is answered by drawing again.
# (Renode's own default, 1234, collides across concurrent or stale instances,
# which is why it is per-run at all.) The telnet monitor also lets you poke the
# machine mid-run:
#   ncat localhost <port>   then e.g.:  sysbus.spi3.display DumpFrame "/tmp/f.ppm"
# bin/watch-monitor.sh attaches here without knowing the port — it follows
# this checkout's watch-sim.latest-* pointer to this run dir and reads
# monitor.port. Beware: the Renode monitor treats a closed stdin as `quit`,
# so `echo <cmd> | ncat localhost <port>` runs the command and then kills the
# emulator. To script one command without ending the run, hold stdin open
# (e.g. `{ echo "<cmd>"; sleep 2; } | ncat localhost <port>`).
MONITOR_PORT=""
for _ in $(seq 1 20); do
	CANDIDATE=$(( 20000 + RANDOM % 20000 ))
	if [[ "$HAVE_FLOCK" == 1 ]]; then
		exec 9>"${TMPDIR:-/tmp}/watch-sim.monitor-$CANDIDATE.lock"
		flock -n 9 || continue
	fi
	[[ -n "$(ss -tlnH "sport = :$CANDIDATE" 2>/dev/null || true)" ]] && continue
	MONITOR_PORT="$CANDIDATE"
	break
done
[[ -n "$MONITOR_PORT" ]] || fatal "could not claim a free Renode monitor port in 20 draws from 20000-39999 — something is holding most of that range."

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
# Launch + wait for the pty symlink, whose appearance means the emulation
# script ran to completion.
#
# The deadline is a FAILURE BOUND and nothing else. The old one was 30 s, which
# is short enough to decide the outcome of a healthy boot: the first run in a
# Renode process compiles seven C# peripheral models before it reaches the pty
# — ~3 s on this workstation, several times that on a cold, contended CI runner
# — and nothing in the wait could tell a compile still running from a machine
# that had died. It is now 180 s, six times the widest boot ever measured here,
# so expiry means something is actually wrong rather than that the runner was
# busy; what the boot GOT TO is read off watch.resc's own stage markers instead
# of guessed at. Returns 0 on a booted machine, 1 on an early exit, 2 on a boot
# that ran out the bound.
BOOT_TIMEOUT_S="${WATCH_SIM_BOOT_TIMEOUT_S:-180}"
start_renode() {
	renode "${RENODE_FLAGS[@]}" -e "$RENODE_CMDS" >"$RENODE_LOG" 2>&1 &
	RENODE_PID=$!
	local started=$SECONDS
	while (( SECONDS - started < BOOT_TIMEOUT_S )); do
		[[ -e "$GPS_PTY" ]] && return 0
		kill -0 "$RENODE_PID" 2>/dev/null || return 1
		sleep 0.2
	done
	return 2
}

# The furthest watch.resc got, for a boot that did not finish. Renode does not
# put an error raised inside an include into the log file, so without these the
# only fact available about a half-run include was that it had not finished.
boot_stage() {
	sed -n 's/.*watch\.resc stage: //p' "$RENODE_LOG" 2>/dev/null | tail -1
}

start_renode && BOOT=0 || BOOT=$?

# A UI-less Renode build (the macOS arm64 .NET build: renode/renode#886)
# prints `Couldn't start UI` and falls back to a stdin console monitor, which
# reads this backgrounded launch's closed stdin as `quit`. Crucially the
# emulation script may still RUN TO COMPLETION first — the pty existing does
# not mean a window is up — so the log line decides the fallback, never the
# exit timing. (A first version keyed on the process dying inside the wait
# loop, and lost the race: the machine survived just long enough to win the
# pty check, then died window-less during streaming.) Deliver what --gui
# promised anyway: relaunch headless and put the live window up via
# bin/watch-view.sh once the monitor is up.
if [[ "$GUI" == 1 ]] && grep -q "Couldn't start UI" "$RENODE_LOG" 2>/dev/null; then
	step "This Renode build cannot start its UI (renode/renode#886) — relaunching headless with the bin/watch-view.sh live window"
	kill "$RENODE_PID" 2>/dev/null || true
	wait "$RENODE_PID" 2>/dev/null || true
	rm -f "$GPS_PTY"
	GUI_VIEWER=1
	RENODE_FLAGS+=(--disable-xwt --hide-analyzers)
	RENODE_CMDS="${RENODE_CMDS%"; showAnalyzer sysbus.spi3.display"}"
	start_renode && BOOT=0 || BOOT=$?
fi

if [[ "$BOOT" == 1 ]]; then
	tail -n 30 "$RENODE_LOG" >&2
	fatal "Renode exited during startup — full log: $RENODE_LOG"
elif [[ "$BOOT" == 2 ]]; then
	STAGE="$(boot_stage)"
	tail -n 30 "$RENODE_LOG" >&2
	fatal "Renode never created the GPS pty within ${BOOT_TIMEOUT_S}s — the emulation script got as far as '${STAGE:-nothing: not one stage marker reached the log, so the include never got past the platform and the C# peripheral models}' and stopped there. Full log: $RENODE_LOG (monitor errors do not reach it, which is what the stage markers are for; re-run the include under 'renode --console' to see the error itself)."
fi
grep -q "defmt-rtt drain active" "$RENODE_LOG" || \
	fatal "defmt-rtt drain did not arm — check $RENODE_LOG and sim/defmt_rtt.py (must stay ASCII-only for Renode's IronPython)"
ok "Renode up — log: $RENODE_LOG, monitor: bin/watch-monitor.sh (ncat localhost $MONITOR_PORT)"
if [[ "$GUI_VIEWER" == 1 ]]; then
	# The --gui fallback: the live window rides the monitor port. Backgrounded
	# and non-fatal — a missing tkinter python prints watch-view's own hint,
	# and the headless sim is still fully usable underneath.
	"$(dirname "${BASH_SOURCE[0]}")/watch-view.sh" "$MONITOR_PORT" &
fi
dim "buttons: click BTN1-5 in the --gui window, or in the monitor run  runMacro \$btn1 (start/pause/dismiss; grid: GO; menu: edit right), \$btn2 (stop x2; grid: cancel; menu: cursor up), \$btn3 (page left / idle GNSS mode; menu: cursor down), \$btn4 (page right / idle diag toggle; menu: exit), \$btn3h or \$btn4h (page grid; idle \$btn3h: QNH re-zero), \$btn5 (lap / idle: settings menu; menu: edit left)"

# Feed the fixture into the emulated GPS UART. Sentences come in GGA+RMC pairs
# per GPS second; two lines per wall-clock second matches the 1 Hz fix rate a
# real MAX-M10S emits.
#
# The feed loops so a short fixture can carry a long session. Note what the loop
# point IS, because it is not a no-op: it teleports the runner from the fixture's
# end back to its start, which for bench_jog is metres and for a point-to-point
# fixture is hundreds of them. The recorder handles that correctly (a jump past
# MAX_JUMP_M at a one-fix interval is a teleport and credits nothing), but any
# assertion about distance that runs past the loop is reading a different
# scenario than the fixture describes — sim/ci_smoke.py's `dropout` finds the
# restart in the published-fix stream and refuses to read past it.
#
# A --nmea-once flag was tried instead and removed: however the feed is stopped,
# the firmware stops receiving sentences that were written before it stopped, so
# the fixture silently loses its tail (gps_dropout delivered its clean opening
# leg and then nothing, and the void never ended). Holding the write fd open past
# the last line did not change that. Whatever buffers between here and the
# emulated UARTE only drains while the writer is still writing.
# The feed survives a failed write and says so. It used to run under the
# inherited `set -e` with its stderr on /dev/null, so ONE write that did not
# take ended the GPS stream for the rest of the session and left no trace: the
# firmware simply stopped receiving fixes, which is indistinguishable from a
# runner standing still, so the recorder auto-paused and every distance-driven
# assertion waited out its budget. CI run 31361094964, scenario `workout`: four
# fixes, then nothing for the remaining 270 s of a 300 s budget, and a failure
# that read as a broken workout runner. Reopening the pty is the recovery that
# matters — the reader on the other side is Renode, which outlives a transient
# write error — and giving up is now loud rather than silent.
(
	set +e
	open_gps() {
		exec 3>"$GPS_PTY"
	}
	if ! open_gps; then
		echo "watch-sim: could not open the GPS pty $GPS_PTY for writing" >&2
		exit 1
	fi
	while true; do
		while IFS= read -r line; do
			if ! printf '%s\r\n' "$line" >&3; then
				echo "watch-sim: GPS write failed, reopening $GPS_PTY" >&2
				exec 3>&-
				if ! open_gps; then
					echo "watch-sim: GPS pty gone — the fix stream stops here" >&2
					exit 1
				fi
			fi
			sleep 0.5
		done < "$NMEA_FILE"
	done
) &

step "Streaming defmt logs (Ctrl-C to stop)"
dim "NMEA feed: $NMEA_FILE -> sysbus.uart0 at 1 Hz"
dim "phone link: tcp://localhost:$PHONE_PORT (Android emulator: 10.0.2.2:$PHONE_PORT) — try: ncat localhost $PHONE_PORT"
# Backgrounded + wait rather than a foreground pipeline: bash defers traps
# while a foreground job runs, so Ctrl-C/TERM would never reach cleanup and
# Renode would outlive the script.
tail -c +1 -f "$DEFMT_RAW" | defmt-print -e "$ELF" &
wait $!
