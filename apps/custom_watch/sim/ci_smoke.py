#!/usr/bin/env python3
"""Boot the custom_watch firmware under Renode and assert on observable output.

The manual `bin/watch-sim.sh` session is the reference harness; this driver
wraps it so a CI runner can prove the sim still works end to end instead of
waiting for someone to run it by hand. It reuses the launcher rather than
re-implementing the boot sequence, so a regression in watch-sim.sh itself
(pty, defmt drain, monitor port, cleanup) also fails here.

Three scenarios, selected with `--scenario` (default `all`):

`smoke` — the original end-to-end pass, unchanged. In order, each assertion
grounded in the manual evidence under sim/verification-2026-07-19/:

  1. the flash run store arms at boot            run_flash: run store armed
  2. the canned NMEA parses into an accepted fix gps: fix ... sats=N (N>=4)
  3. that fix starts a recording                 record: sim-autostart
  4. distance accumulates past a floor           record: recording dist=<m>
  5. the run face actually renders on the panel  DumpFrame -> non-blank PPM
  6. two BTN2 presses stop the run and commit    run_flash: stored run
  7. nothing panicked along the way

`alerts` — the on-run alert engine reaches the panel. The sim arms its own
shortened cadences under `sim-autostart` (drink 30 s / eat 45 s of moving time,
a 100 m distance arm, a 60 s elapsed arm, and a 5:00-5:20/km band the ~5:33/km
bench_jog fixture sits outside), so this asserts what that arming makes
inevitable and nothing more — see `scenario_alerts`.

`pages` — the paged glance cycle. Walks the cycle right with `runMacro $btn4`
(§350: the lower-right key pages right) and, for each page of interest, waits
for the ui task's own page line and then dumps the panel. Two firmware lines are
read per press and they are different claims: the ui task's `ui: page <Name>` is
what the panel COMPOSED, the button task's `button: BTN4 -> page <Name>` is what
the press INTENDED, and each press asserts they agree — disagreement means the
cycle advanced without the panel following. The ui line is change-gated, so its
first occurrence is a boot-time anchor for `Page::default()`, which the walk
asserts and then uses to recognise a full lap. `$btn3` (the lower-left key) taps
back a page and is asserted to be the exact inverse of the forward walk;
`$btn3h`/`$btn4h` (hold) open the page-grid overview and are not exercised here.

**What a panel dump does NOT prove.** A dump shows that *something* was drawn,
not *what*: nothing here reads a glyph. The only evidence that a given page is
on screen is the firmware's own `ui: page <Name>` line, and the only evidence a
banner is up is `record: alert <Kind>` plus the ink a solid inverse-video band
has to add. Every assertion message says which of the two it rests on. Comparing
two dumps is likewise weaker than it looks — the run's clock advances every
second, so any two frames taken seconds apart differ; what the comparison rules
out is a DumpFrame that never landed and left us re-reading a stale file.

What no scenario can cover, per decisions.md §314: BLE (the S140 SoftDevice does
not run under Renode), power draw, and any claim about real silicon — the sensor
models answer what the drivers believe about the parts.

Sessions: `smoke` gets its own boot so its sequence stays byte-for-byte what it
is today (it also ENDS the run, which the other two need in progress).
`alerts` + `pages` share one boot: both need a live recording, neither disturbs
it, and the alert cadences tick through the page walk anyway. Each session gets
its own phone port (`--phone-port` + session index) because watch.resc binds
that port at a FIXED number and watch-sim.sh aborts if it is still held — a
sequential re-launch must not race the previous Renode's teardown. `--budget` is
a cap on the WHOLE process, shared across sessions, so a per-scenario invocation
gets all of it and `--scenario all` splits it across two boots.

Determinism: the altitude and NMEA sources are virtual-time driven with no
randomness, so a given firmware + fixture replays identically. Every wait here
is on a specific decoded log line with a deadline, never a fixed sleep — the
sole exception is the ~1.5 s gap between the two BTN2 presses, which must land
inside the firmware's 4 s stop-confirm window and so cannot wait on the "armed"
line (a block-buffered decoder could delay observing it past the window).

Usage:
  apps/custom_watch/sim/ci_smoke.py [--out-dir DIR] [--fixture NAME]
                                    [--phone-port N] [--budget SECONDS]
                                    [--scenario {smoke,pages,alerts,all}]

Requires: renode + defmt-print on PATH, and the sim-feature ELF already built
(the launcher builds it if not, but pre-building it in a separate step keeps a
compile failure distinguishable from a sim failure). `DEFMT_LOG=debug` is set
for the build the launcher does — the distance, fix and page assertions all
read debug-level lines, and defmt filters at compile time.
"""

import argparse
import itertools
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from collections import namedtuple
from contextlib import contextmanager
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]

MIN_DISTANCE_M = 20.0
MIN_DARK_PIXELS = 200
MIN_WHITE_PIXELS = 200
MIN_SATS = 4
STOP_ATTEMPTS = 3

SCENARIO_ORDER = ("smoke", "alerts", "pages")

# The pages the walk has to reach and render. Two always-available heroes
# (Distance / Pace, the generated-numeral pages), plus the pages the recent
# batches added or changed: Pacer (which now carries the race-phase row),
# GuidedRun, RouteElev (the drawn course climb profile), and Daylight (the
# sunset/sunrise countdown the demo settings' UTC-6 offset arms — its render
# under bench_jog is the golden-tested pre-dawn sunrise case).
#
# Anything added here must be a page the sim actually arms data for. With
# `hide_empty_pages` at its on-watch default the cycle is FILTERED, so an
# unarmed page is absent from the walk rather than blank in it, and thirteen
# pages cannot be armed at all today because their setters have no `SET1` wire
# field: Fitness, Readiness, Goals, RaceDay, Recap, Streaks, RunStats,
# PrRecency, PlanReplan, PlanAdaptive, RouteSimplify, AutoEffort,
# TrainingPaces. DistanceBand needs ~5 km and stays dark on this fixture too.
PAGES_OF_INTEREST = ("Distance", "Pace", "Pacer", "GuidedRun", "RouteElev", "Daylight")

# The run view opens on `Page::default()`, so the forward walk wrapping back to
# it marks one full lap. Asserted from the ui task's boot-time anchor line
# rather than assumed — see `scenario_pages`.
START_PAGE = "Dashboard"

# The ui task's page line — what the panel actually COMPOSED. Change-gated: it
# fires once at boot as a baseline anchor and then only on a real change, so it
# never repeats on a re-render and there is exactly one per effective press.
PAGE_LINE = re.compile(r"ui: page (\w+)")
# The button task's page line — what the press INTENDED. A different claim from
# the line above, and the pair disagreeing is its own bug class (the button task
# advanced its page but state::PAGE never reached the composer), so each press
# asserts they agree. One pattern per paging key (§350: BTN4 pages right,
# BTN3 pages left), so a walk also asserts WHICH key the firmware credited.
PAGE_INTENT_LINES = {
    "$btn3": re.compile(r"button: BTN3 -> page (\w+)"),
    "$btn4": re.compile(r"button: BTN4 -> page (\w+)"),
}
PAGE_STEP_TIMEOUT = 30
PAGE_PRESS_ATTEMPTS = 2
# Enough presses for two-plus laps of the filtered cycle: an unsynced sim watch
# carries ~12-18 of the 35 pages, and the full cycle is 35.
MAX_PAGE_PRESSES = 48

# `record: alert <Kind>` on a raise, `record: alert cleared` when its TTL runs
# out. The kind carries its payload for the parameterised arms (`Distance(100)`,
# `Time(60)`).
ALERT_ANY = re.compile(r"record: alert (\S+)")
ALERT_RAISED = re.compile(r"record: alert (?!cleared\b)(\S+)")
ALERT_CLEARED = re.compile(r"record: alert cleared")
FUEL_ALERT = re.compile(r"record: alert (Drink|Eat)\b")
# The arms the sim added on top of fuel. Asserted as a disjunction, not one by
# one: Distance and Time are DROPPED (not queued) when the single display slot
# is busy, and the pace arm latches once per excursion, so which of them wins a
# slot is not something the arming makes inevitable.
OTHER_ALERT = re.compile(r"record: alert (Distance|Time|PaceFast|PaceSlow)\b")
ALERT_BANNER_ATTEMPTS = 4
# The quiet baseline is sampled too, for the same repaint-lag reason the banner
# side retries — see `scenario_alerts`.
ALERT_QUIET_ATTEMPTS = 3
ALERT_CLEAR_TIMEOUT = 30

# How much extra ink an alert banner has to put on the panel over the same page
# with no banner. The banner is a solid inverse-video band across the two hero
# rows — 168x32 = 5376 px of ink less the knocked-out text — replacing a hero
# whose numerals ink far less than that, so the real delta is thousands. This
# sits an order of magnitude under that and well over the handful of pixels a
# ticking second changes.
MIN_BANNER_INK_DELTA = 500

Panel = namedtuple("Panel", "path width height dark data")


class SmokeFailure(Exception):
    pass


def announce(msg):
    print(f"    {msg}", flush=True)


def passed(msg):
    print(f"  PASS  {msg}", flush=True)


def error(msg):
    if os.environ.get("GITHUB_ACTIONS"):
        print(f"::error::{msg}", flush=True)
    print(f"  FAIL  {msg}", file=sys.stderr, flush=True)


class LogTail:
    """Incremental reader over the launcher's combined output."""

    def __init__(self, path):
        self.path = Path(path)
        self.pos = 0
        self.partial = ""
        self.lines = []

    def poll(self):
        if not self.path.exists():
            return
        with self.path.open("r", errors="replace") as fh:
            fh.seek(self.pos)
            chunk = fh.read()
            self.pos = fh.tell()
        if not chunk:
            return
        self.partial += chunk
        *complete, self.partial = self.partial.split("\n")
        self.lines.extend(complete)

    def mark(self):
        """Index of the next line to arrive — the "from here on" cursor a
        repeated wait needs. Lines are only ever appended, so it stays valid."""
        self.poll()
        return len(self.lines)

    def search(self, pattern, start=0):
        for line in self.lines[start:]:
            m = pattern.search(line)
            if m:
                return m
        return None

    def wait(self, pattern, timeout, what, guard=None, start=0):
        deadline = time.monotonic() + timeout
        while True:
            self.poll()
            for line in self.lines[start:]:
                m = pattern.search(line)
                if m:
                    return m
            if guard is not None:
                guard()
            if time.monotonic() >= deadline:
                raise SmokeFailure(
                    f"expected {what} within {timeout:.0f}s — no decoded log line "
                    f"matched /{pattern.pattern}/ ({len(self.lines) - start} lines seen)"
                )
            time.sleep(0.25)

    def text(self):
        self.poll()
        return "\n".join(self.lines)


class Monitor:
    """One long-lived connection to the Renode telnet monitor.

    Renode treats a closed stdin as `quit`, so the connection has to outlive
    every command we send — and its output has to be drained, or a full socket
    buffer blocks the monitor thread mid-emulation.
    """

    def __init__(self, port, log_path):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=15)
        self.sock.settimeout(1.0)
        self.log = open(log_path, "w")
        self.stop = threading.Event()
        self.reader = threading.Thread(target=self._drain, daemon=True)
        self.reader.start()

    def _drain(self):
        while not self.stop.is_set():
            try:
                data = self.sock.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                return
            if not data:
                return
            self.log.write(data.decode("utf-8", errors="replace"))
            self.log.flush()

    def send(self, command):
        announce(f"monitor: {command}")
        self.sock.sendall((command + "\n").encode())

    def close(self):
        self.stop.set()
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        self.log.close()


def read_ppm(path):
    data = path.read_bytes()
    if not data.startswith(b"P6"):
        raise SmokeFailure(
            f"panel dump at {path} is not a P6 PPM (first bytes: {data[:16]!r})"
        )
    fields = []
    pos = 2
    while len(fields) < 3:
        while pos < len(data) and data[pos : pos + 1].isspace():
            pos += 1
        if data[pos : pos + 1] == b"#":
            while pos < len(data) and data[pos : pos + 1] != b"\n":
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos : pos + 1].isspace():
            pos += 1
        fields.append(int(data[start:pos]))
    pos += 1
    width, height, _maxval = fields
    pixels = data[pos:]
    expected = width * height * 3
    if len(pixels) < expected:
        raise SmokeFailure(
            f"panel dump is truncated — {width}x{height} needs {expected} bytes "
            f"of pixel data, got {len(pixels)}"
        )
    dark = 0
    for i in range(0, expected, 3):
        if pixels[i] < 128:
            dark += 1
    return width, height, dark, data


def wait_for_file(path, timeout, what):
    deadline = time.monotonic() + timeout
    last = -1
    while time.monotonic() < deadline:
        if path.exists():
            size = path.stat().st_size
            if size > 0 and size == last:
                return
            last = size
        time.sleep(0.25)
    raise SmokeFailure(
        f"expected {what} at {path} within {timeout:.0f}s — the file never "
        "appeared or never stopped growing"
    )


def assert_rendered(panel, what):
    """The ink/light floors that separate a drawn frame from a blank panel or a
    broken decode. This is the whole of what a dump can say — it cannot say the
    frame shows `what`, only that it is not empty."""
    white = panel.width * panel.height - panel.dark
    if panel.dark < MIN_DARK_PIXELS or white < MIN_WHITE_PIXELS:
        raise SmokeFailure(
            f"the {panel.width}x{panel.height} panel does not look like {what}: "
            f"{panel.dark} dark / {white} light pixels, expected at least "
            f"{MIN_DARK_PIXELS} of each (all-light = nothing drawn, all-dark = "
            "the frame decode is broken)"
        )


class Sim:
    """One booted launcher session: the process, its decoded log, the monitor."""

    def __init__(self, args, label, out_dir, deadline, phone_port):
        self.args = args
        self.label = label
        self.out_dir = out_dir
        self.deadline = deadline
        self.phone_port = phone_port
        self.combined = out_dir / "sim-output.log"
        self.tail = LogTail(self.combined)
        self.proc = None
        self.log_fh = None
        self.run_dir = None
        self.monitor_port = None
        self._monitor = None

    def alive(self):
        if self.proc.poll() is not None:
            raise SmokeFailure(
                f"bin/watch-sim.sh exited early with status {self.proc.returncode} — "
                f"see {self.combined}"
            )
        if time.monotonic() > self.deadline:
            raise SmokeFailure(
                f"exceeded the {self.args.budget:.0f}s budget before finishing"
            )

    def wait(self, pattern, timeout, what, start=0):
        return self.tail.wait(pattern, timeout, what, guard=self.alive, start=start)

    def monitor(self):
        if self._monitor is None:
            self._monitor = Monitor(self.monitor_port, self.out_dir / "monitor.log")
        return self._monitor

    def dump(self, name, what):
        """Dump the panel to `name` in this session's artifact dir and decode it.

        The stale file is removed first: `wait_for_file` accepts any non-empty
        settled file, so a leftover dump would be read back as this frame.
        """
        path = self.out_dir / name
        if path.exists():
            path.unlink()
        self.monitor().send(f"sysbus.spi3.display DumpFrame @{path}")
        wait_for_file(path, 45, what)
        width, height, dark, data = read_ppm(path)
        return Panel(path, width, height, dark, data)

    def boot(self):
        self.out_dir.mkdir(parents=True, exist_ok=True)
        latest_link = self.out_dir / "watch-sim.latest"
        for stale in (self.combined, latest_link):
            if stale.is_symlink() or stale.exists():
                stale.unlink()

        env = dict(os.environ)
        # The distance + fix + page assertions read DEBUG-level lines, and defmt
        # filters at compile time, so this has to be set for the build the
        # launcher does.
        env["DEFMT_LOG"] = "debug"
        env["WATCH_SIM_LATEST"] = str(latest_link)

        cmd = [
            str(REPO_ROOT / "bin" / "watch-sim.sh"),
            "--fixture",
            self.args.fixture,
            "--phone-port",
            str(self.phone_port),
        ]
        announce(f"launching {' '.join(cmd)}")
        self.log_fh = self.combined.open("w")
        self.proc = subprocess.Popen(
            cmd,
            cwd=str(REPO_ROOT),
            env=env,
            stdout=self.log_fh,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        self.wait(
            re.compile(r"Streaming defmt logs"),
            self.args.boot_timeout,
            "bin/watch-sim.sh to reach 'Streaming defmt logs' (Renode up, GPS pty "
            "created, defmt-rtt drain armed)",
        )
        passed("Renode booted the sim ELF and armed the defmt-rtt drain")

        self.run_dir = Path(os.readlink(latest_link))
        self.monitor_port = int((self.run_dir / "monitor.port").read_text().strip())
        announce(f"run dir {self.run_dir}, monitor port {self.monitor_port}")

    def shutdown(self):
        if self._monitor is not None:
            self._monitor.close()
        if self.proc is not None:
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                self.proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
        if self.log_fh is not None:
            self.log_fh.close()
        if self.run_dir is not None:
            for name in ("renode.log", "defmt.raw"):
                src = self.run_dir / name
                if src.exists():
                    shutil.copy2(src, self.out_dir / name)
        announce(f"artifacts in {self.out_dir}")


@contextmanager
def sim_session(args, label, deadline, phone_port):
    sim = Sim(args, label, Path(args.out_dir) / label, deadline, phone_port)
    try:
        sim.boot()
        yield sim
    finally:
        sim.shutdown()


def require_recording(sim):
    """Both run-view scenarios need a run under way: the page cycle only
    exists in a run view (idle, BTN4 toggles diagnostics and BTN3 cycles the
    GNSS mode), and the alert cadences bank on the recorder's clocks."""
    sim.wait(
        re.compile(r"record: sim-autostart on first fix"),
        180,
        "the first accepted fix to start a recording "
        "('record: sim-autostart on first fix')",
    )


def latest_alert(tail):
    """The most recent `record: alert …` payload — an alert kind while a banner
    is on screen, `cleared` once its TTL expired, None before the first one."""
    tail.poll()
    latest = None
    for line in tail.lines:
        m = ALERT_ANY.search(line)
        if m:
            latest = m.group(1)
    return latest


def wait_for_no_alert(sim):
    """Hold until no alert banner is on screen.

    A banner replaces the hero band, so a page dump taken under one is a dump of
    the banner, not of the page — the page assertions would still pass and would
    mean less.
    """
    if latest_alert(sim.tail) in (None, "cleared"):
        return
    mark = sim.tail.mark()
    sim.wait(
        ALERT_CLEARED,
        ALERT_CLEAR_TIMEOUT,
        "the active alert banner to clear at its TTL ('record: alert cleared') so "
        "the next dump is of the page and not of the banner",
        start=mark,
    )


def press_page(sim, macro, what):
    """One paging-key press, resolved by the page line the ui task emits on a
    change.

    That line is the firmware's own statement about which page it now composes,
    and it is the ONLY thing here that proves the page changed — a panel dump
    cannot, it shows that something was drawn, not what. The button task's own
    line is then cross-checked against it: intent and composition agreeing is a
    separate claim from either one alone.
    """
    intent_line = PAGE_INTENT_LINES[macro]
    for attempt in range(1, PAGE_PRESS_ATTEMPTS + 1):
        mark = sim.tail.mark()
        sim.monitor().send(f"runMacro {macro}")
        try:
            composed = sim.wait(
                PAGE_LINE,
                PAGE_STEP_TIMEOUT,
                f"the ui task to report a page change after {what} "
                "('ui: page <Name>')",
                start=mark,
            ).group(1)
        except SmokeFailure:
            if attempt == PAGE_PRESS_ATTEMPTS:
                raise
            announce("no page change seen — the injected press likely missed a poll")
            continue
        # The button task logs before it publishes state::PAGE, so this line is
        # already in the stream by the time the composed one decodes; the wait
        # is only there so decode lag cannot turn agreement into a false miss.
        intent = sim.wait(
            intent_line,
            5,
            f"the button task to report the page it selected on {what} "
            f"('{intent_line.pattern}')",
            start=mark,
        ).group(1)
        if intent != composed:
            raise SmokeFailure(
                f"{what} selected page {intent} in the button task but the ui task "
                f"composed {composed} — the press advanced the cycle without the "
                "panel following it (state::PAGE did not reach the composer)"
            )
        return composed
    raise AssertionError("unreachable")


def scenario_smoke(sim):
    sim.wait(
        re.compile(r"run_flash: run store armed at"),
        60,
        "the flash run store to arm at boot ('run_flash: run store armed at 0x…')",
    )
    passed("flash run store armed at boot")

    fix = sim.wait(
        re.compile(r"gps: fix lat=(-?[\d.]+) lon=(-?[\d.]+).*sats=(\d+)"),
        120,
        f"a parsed GPS fix from the {sim.args.fixture} NMEA fixture "
        "('gps: fix lat=… sats=N')",
    )
    sats = int(fix.group(3))
    if sats < MIN_SATS:
        raise SmokeFailure(
            f"first parsed fix reported sats={sats}, expected at least "
            f"{MIN_SATS} — the fixture's GSV/GGA sentences are not reaching "
            "the parser intact"
        )
    passed(
        f"canned NMEA parsed into a fix (lat={fix.group(1)} lon={fix.group(2)} "
        f"sats={sats})"
    )

    sim.wait(
        re.compile(r"record: sim-autostart on first fix"),
        60,
        "the first accepted fix to start a recording "
        "('record: sim-autostart on first fix')",
    )
    passed("recording started on the first accepted fix")

    dist_re = re.compile(r"record: recording dist=([\d.]+)m")
    deadline = time.monotonic() + sim.args.distance_timeout
    best = 0.0
    while True:
        sim.alive()
        sim.tail.poll()
        for line in sim.tail.lines:
            m = dist_re.search(line)
            if m:
                best = max(best, float(m.group(1)))
        if best >= MIN_DISTANCE_M:
            break
        if time.monotonic() >= deadline:
            raise SmokeFailure(
                f"expected the recorder to accumulate at least "
                f"{MIN_DISTANCE_M:.0f} m within {sim.args.distance_timeout:.0f}s of "
                f"the run starting; the highest 'record: recording dist=' seen "
                f"was {best:.1f} m"
            )
        time.sleep(0.5)
    passed(f"distance accumulated to {best:.1f} m while recording")

    panel = sim.dump("frame.ppm", "a panel frame dump")
    assert_rendered(panel, "a rendered face")
    passed(
        f"run face rendered on the {panel.width}x{panel.height} panel "
        f"({panel.dark} dark pixels of {panel.width * panel.height})"
    )

    stored_re = re.compile(r"run_flash: stored run (\d+) \((\d+) B\) in slot (\d+)")
    stored = None
    for attempt in range(1, STOP_ATTEMPTS + 1):
        announce(f"BTN2 stop pair, attempt {attempt}/{STOP_ATTEMPTS}")
        sim.monitor().send("runMacro $btn2")
        # Inside the firmware's 4 s stop-confirm window; see the module
        # docstring for why this one gap is not gated on a log line.
        time.sleep(1.5)
        sim.monitor().send("runMacro $btn2")
        try:
            stored = sim.wait(
                stored_re,
                25,
                "the stopped run to commit to the flash store "
                "('run_flash: stored run N (M B) in slot S')",
            )
            break
        except SmokeFailure as exc:
            if attempt == STOP_ATTEMPTS:
                raise SmokeFailure(
                    f"{exc} — {STOP_ATTEMPTS} BTN2 press pairs were injected "
                    "and none produced a flash commit"
                ) from exc
            announce("no commit yet — the injected press likely missed a poll")

    if sim.tail.search(re.compile(r"button: BTN2 armed")) is None:
        raise SmokeFailure(
            "the run committed but 'button: BTN2 armed' never appeared — the "
            "two-press stop guard did not arm"
        )
    stored_bytes = int(stored.group(2))
    if stored_bytes <= 0:
        raise SmokeFailure(
            f"the run committed 0 bytes to slot {stored.group(3)} — a stored "
            "run must carry a track"
        )
    passed(
        f"stopped run committed {stored_bytes} B to flash slot "
        f"{stored.group(3)} after the two-press BTN2 guard"
    )

    text = sim.tail.text()
    panics = [ln for ln in text.splitlines() if "panicked" in ln.lower()]
    if panics:
        raise SmokeFailure("the firmware panicked during the run: " + panics[0].strip())
    passed("no firmware panic in the decoded log")


def scenario_alerts(sim):
    """The on-run alert engine, asserted only where the sim's arming makes an
    outcome inevitable.

    `app/src/tasks/record.rs` under `sim-autostart` shortens the fuel cadences to
    30 s drink / 45 s eat of MOVING time and arms the distance (100 m), time
    (60 s elapsed) and pace (5:00-5:20/km, which the ~5:33/km bench_jog fixture
    sits outside) alerts through the same public setters a phone push uses. What
    that guarantees is that a fuel reminder fires and that at least one of the
    newer kinds fires. What it does NOT guarantee is ordering or a specific
    kind: one alert holds the single display slot at a time, a superseded fuel
    reminder re-queues while a distance/time milestone is dropped outright, and
    the pace arm latches once per excursion. So the assertions are one fuel
    reminder, one of the newer kinds as a disjunction, and no claim about which
    came first.
    """
    require_recording(sim)

    fuel = sim.wait(
        FUEL_ALERT,
        240,
        "a fuel reminder on the sim's shortened moving-time cadence "
        "(30 s drink / 45 s eat — 'record: alert Drink' or 'record: alert Eat')",
    )
    passed(f"fuel reminder fired: {fuel.group(1)}")

    other = sim.wait(
        OTHER_ALERT,
        240,
        "one of the distance / time / pace alerts the sim arms "
        "('record: alert Distance(…)' / 'Time(…)' / 'PaceFast' / 'PaceSlow')",
    )
    passed(f"one of the newer alert arms fired: {other.group(1)}")

    # A dump taken under a banner proves only that something was on the panel.
    # The pair is what carries the claim: the same page with no banner, then
    # with one. The banner is a solid inverse-video band over the two hero rows,
    # so it has to add far more ink than the hero it replaces.
    # Both halves of the pair race the panel the same way, and the baseline is
    # the half that fails silently. `wait_for_no_alert` returns on the record
    # task's `cleared` line, but the screen task repaints a beat later, so a
    # quiet dump can still be carrying the very banner it is supposed to be the
    # baseline for — which inflates `quiet` to banner level and makes every
    # later comparison read as "no banner rendered". Sample it a few times and
    # keep the LOWEST: a stale quiet frame can only ever read too inky, never
    # too clean, so the minimum is the one that cannot be the lagging one.
    quiet = None
    for attempt in range(1, ALERT_QUIET_ATTEMPTS + 1):
        wait_for_no_alert(sim)
        shot = sim.dump(
            f"alert-quiet-{attempt}.ppm", "a panel frame with no alert on screen"
        )
        assert_rendered(shot, "the run face between alerts")
        if quiet is None or shot.dark < quiet.dark:
            quiet = shot
    announce(f"quiet baseline: {quiet.dark} dark pixels (lowest of {ALERT_QUIET_ATTEMPTS})")

    # `ALERT_RAISED` is the RECORD task's line; the banner is painted later by
    # the screen task. So a dump can land after the raise is logged, with the
    # alert still up, and still catch the panel one repaint short of the banner
    # — which is a bannerless frame that the `cleared` guard below cannot see.
    # Retry that case rather than reading the first sample as a verdict: the
    # claim is that a banner reaches the panel while an alert is active, not
    # that it is already there the instant the record task logs the raise.
    # Exhausting every attempt still fails, so a banner that never renders is
    # caught exactly as before — the loop widens when the assertion samples,
    # not what it demands.
    banner = None
    dumped = None
    for attempt in range(1, ALERT_BANNER_ATTEMPTS + 1):
        announce(f"waiting for an alert to dump under, attempt {attempt}/{ALERT_BANNER_ATTEMPTS}")
        mark = sim.tail.mark()
        sim.wait(
            ALERT_RAISED,
            240,
            "an alert to raise so its banner can be dumped ('record: alert <Kind>')",
            start=mark,
        )
        # One file per attempt so a failing run keeps every frame it judged.
        shot = sim.dump(
            f"alert-banner-{attempt}.ppm", "a panel frame while an alert is active"
        )
        if latest_alert(sim.tail) == "cleared":
            announce("the alert cleared before the dump landed — waiting for the next")
            continue
        if dumped is None or shot.dark > dumped.dark:
            dumped = shot
        if shot.dark - quiet.dark < MIN_BANNER_INK_DELTA:
            announce(
                f"the alert was still up but the frame carries {shot.dark} dark pixels "
                f"against {quiet.dark} quiet — the repaint had not landed yet, retrying"
            )
            continue
        banner = shot
        break
    if banner is None and dumped is None:
        raise SmokeFailure(
            f"no alert stayed on screen long enough to dump in "
            f"{ALERT_BANNER_ATTEMPTS} attempts — every raise had already logged "
            "'record: alert cleared' by the time the DumpFrame landed, so the "
            "banner's TTL is shorter than a panel dump takes"
        )
    if banner is None:
        ink = dumped.dark - quiet.dark
        raise SmokeFailure(
            f"no frame dumped while an alert was active carried a banner in "
            f"{ALERT_BANNER_ATTEMPTS} attempts — the inkiest was {dumped.dark} dark "
            f"pixels against {quiet.dark} with no alert ({ink:+d}), short of the "
            f"{MIN_BANNER_INK_DELTA} an inverse-video banner band has to add — the "
            "alert reached state::ALERT but nothing that looks like a banner "
            "reached the panel"
        )
    assert_rendered(banner, "the run face with an alert banner")

    ink = banner.dark - quiet.dark
    passed(
        f"an alert banner reached the panel: {banner.dark} dark pixels with a banner "
        f"up against {quiet.dark} without ({ink:+d} ink, consistent with an "
        "inverse-video band; the dump cannot read the banner's text)"
    )


def scenario_pages(sim):
    """Walk the paged glance cycle and prove each page of interest renders.

    Per press: the ui task's `ui: page <Name>` line says which page is now
    composed (the only page-change evidence available), the button task's line
    is cross-checked against it, then a panel dump says the panel is not blank.
    The cycle is `Snapshot::pages_mask` — data-present INTERSECT phone-curated —
    so the walk length is a property of what the sim arms, not of the 35-variant
    enum, and the walk is driven by the reported pages rather than by counting
    presses.

    Renders only, no transitions. Both armed pages move on their own clock and
    neither move is asserted here: the GuidedRun cue advance is elapsed-driven at
    180 s, and the Pacer race-phase row is DISTANCE-driven at 381.4 m — the
    earliest boundary any preset can produce, which on this fixture is ~255 s of
    moving time, not ~127 s (consecutive fixes step ~2.97 m against the 3.0 m
    TRACK_THRESHOLD_M, so about half are absorbed and recorded distance accrues
    at ~1.5 m/s against 3.0 m/s of ground speed). Holding a run past four
    minutes to watch a row change is a poor trade against the per-scenario
    budget, so this is a budget decision, not an oversight — the pages are
    asserted populated, which is what the arming makes inevitable.
    """
    require_recording(sim)

    # The ui task's page line is change-gated, so its first occurrence is the
    # boot-time anchor for whatever `Page::default()` is. That anchor is what
    # lets the walk below read a return to START_PAGE as one full lap, so assert
    # it rather than assume it.
    anchor = sim.wait(
        PAGE_LINE, 60, "the ui task's boot-time page anchor ('ui: page <Name>')"
    ).group(1)
    if anchor != START_PAGE:
        raise SmokeFailure(
            f"the ui task's first page line reports {anchor}, not {START_PAGE} — the "
            f"page state does not anchor at Page::default(), so a return to "
            f"{START_PAGE} below is not a full lap of the cycle"
        )
    passed(f"the page state anchors at {anchor} before the first press")

    walk = []
    dumps = {}
    lap = []
    lap_closed = False
    presses = 0
    while presses < MAX_PAGE_PRESSES and len(dumps) < len(PAGES_OF_INTEREST):
        presses += 1
        page = press_page(sim, "$btn4", f"BTN4 press {presses}")
        walk.append(page)
        if not lap_closed:
            if page == START_PAGE and lap:
                lap_closed = True
            else:
                lap.append(page)
        if page in PAGES_OF_INTEREST and page not in dumps:
            wait_for_no_alert(sim)
            dumps[page] = sim.dump(f"page-{page}.ppm", f"the {page} page's panel frame")
            assert_rendered(dumps[page], f"the {page} page")
            announce(f"{page} rendered ({dumps[page].dark} dark pixels)")

    cycle = " -> ".join([START_PAGE] + lap) if lap else "nothing"
    missing = [p for p in PAGES_OF_INTEREST if p not in dumps]
    if missing:
        raise SmokeFailure(
            f"{', '.join(missing)} never appeared in the BTN4 cycle over {presses} "
            f"presses (the cycle walked: {cycle}). The cycle is "
            "Snapshot::pages_mask (data-present INTERSECT phone-curated), so a page "
            "whose data nothing arms is LEGITIMATELY absent rather than a harness "
            "bug: GuidedRun needs a guided run armed (Recorder::set_guided_run, via "
            "the sim demo settings push in app/src/tasks/record.rs), RouteElev needs "
            "the sim course's per-point elevation (SIM_COURSE_ELEV_M in "
            "app/src/tasks/nav.rs, behind the sim-course feature), Pacer needs the "
            "demo pacer goal. Arm the data, or drop the page from "
            "PAGES_OF_INTEREST — do not widen the walk to reach it"
        )
    passed(
        f"the BTN4 cycle rendered every page of interest in {presses} presses "
        f"({'one full lap: ' + cycle if lap_closed else 'walk: ' + cycle})"
    )

    # Two dumps of two different pages must differ. Weaker evidence than it
    # looks, and claimed as exactly what it is: the run's clock advances every
    # second, so ANY two frames taken seconds apart differ. What this rules out
    # is a DumpFrame that never landed and left `wait_for_file` settling on a
    # stale file — which would make every per-page assertion above vacuous.
    frames = [(name, dumps[name]) for name in PAGES_OF_INTEREST]
    for (a_name, a), (b_name, b) in itertools.pairwise(frames):
        if a.data == b.data:
            raise SmokeFailure(
                f"the {a_name} and {b_name} panel dumps are byte-identical — "
                "DumpFrame did not write a fresh frame for one of them (two "
                "different pages seconds apart cannot produce the same bytes, the "
                "elapsed clock alone changes), so the per-page render assertions "
                "above prove nothing"
            )
    passed(
        f"all {len(frames)} page dumps are distinct frames — each DumpFrame landed "
        "fresh (this does NOT prove the layouts differ; the clock alone changes "
        "pixels, the page identity comes from the 'ui: page' lines)"
    )

    # $btn3 is the left-paging tap (§350): `Page::prev_in` must be `next_in`'s
    # exact inverse over the same mask, so one BTN3 tap has to land back on the
    # page before the last one the forward walk reported.
    back = press_page(sim, "$btn3", "the BTN3 tap")
    if back != walk[-2]:
        raise SmokeFailure(
            f"a BTN3 tap from {walk[-1]} landed on {back}, not {walk[-2]} — "
            "the left-paging walk is not the exact inverse of the forward walk "
            "over the same pages_mask"
        )
    passed(f"a BTN3 tap stepped back from {walk[-1]} to {back}")


SCENARIOS = {
    "smoke": scenario_smoke,
    "alerts": scenario_alerts,
    "pages": scenario_pages,
}


def selected_scenarios(choice):
    return list(SCENARIO_ORDER) if choice == "all" else [choice]


def plan_sessions(selected):
    """Group the selected scenarios into booted sessions.

    `smoke` runs alone: its sequence stays exactly what it is today, and it stops
    the run the other two need in progress. `alerts` + `pages` share a boot —
    both need a live recording, neither disturbs it, and the alert cadences tick
    through the page walk anyway. `alerts` goes first so its banner/no-banner
    pair is taken on the page the run view opens on.
    """
    sessions = []
    if "smoke" in selected:
        sessions.append(("smoke", ["smoke"]))
    shared = [name for name in ("alerts", "pages") if name in selected]
    if shared:
        sessions.append(("-".join(shared), shared))
    return sessions


def run(args):
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for tool in ("renode", "defmt-print", "cargo"):
        if shutil.which(tool) is None:
            raise SmokeFailure(f"{tool} is not on PATH — the sim cannot run without it")

    # Process-wide, not per-session: `all` boots twice and the CI job's own
    # timeout is the only other cap.
    deadline = time.monotonic() + args.budget
    failed = []
    for index, (label, names) in enumerate(plan_sessions(selected_scenarios(args.scenario))):
        print(f"\n=== session {label} ({', '.join(names)}) ===", flush=True)
        try:
            with sim_session(args, label, deadline, args.phone_port + index) as sim:
                for name in names:
                    print(f"\n--- scenario {name} ---", flush=True)
                    try:
                        SCENARIOS[name](sim)
                    except SmokeFailure as exc:
                        error(f"scenario {name}: {exc}")
                        failed.append(name)
        except SmokeFailure as exc:
            # The session never came up (or died during teardown), so nothing in
            # it got a verdict of its own.
            error(f"session {label}: {exc}")
            failed.extend(name for name in names if name not in failed)
    return failed


def report_artifacts(out_dir):
    for log in sorted(out_dir.glob("*/sim-output.log")):
        print(f"--- last 40 lines of {log} ---", file=sys.stderr)
        for line in log.read_text(errors="replace").splitlines()[-40:]:
            print(line, file=sys.stderr)
    for log in sorted(out_dir.glob("*/renode.log")):
        print(f"--- last 20 lines of {log} ---", file=sys.stderr)
        for line in log.read_text(errors="replace").splitlines()[-20:]:
            print(line, file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default=os.environ.get("RUNNER_TEMP", "/tmp") + "/watch-sim-ci",
        help="where the logs, panel dumps and copied sim artifacts land, one "
        "subdirectory per booted session",
    )
    parser.add_argument("--fixture", default="bench_jog")
    parser.add_argument(
        "--phone-port",
        type=int,
        default=7788,
        help="phone-link port for the first session; each further session takes "
        "the next port up, so a re-launch cannot race the previous Renode's "
        "hold on it",
    )
    parser.add_argument(
        "--boot-timeout",
        type=float,
        default=420,
        help="seconds for the launcher to build (if needed) and bring Renode up",
    )
    parser.add_argument("--distance-timeout", type=float, default=180)
    parser.add_argument(
        "--budget",
        type=float,
        default=900,
        help="hard wall-clock cap for the whole process, shared across sessions",
    )
    parser.add_argument(
        "--scenario",
        choices=("smoke", "pages", "alerts", "all"),
        default="all",
        help="which scenario to run; 'all' runs smoke, then alerts + pages",
    )
    args = parser.parse_args()

    try:
        failed = run(args)
    except SmokeFailure as exc:
        error(str(exc))
        report_artifacts(Path(args.out_dir))
        return 1

    if failed:
        report_artifacts(Path(args.out_dir))
        error("failed scenarios: " + ", ".join(failed))
        return 1
    ran = ", ".join(selected_scenarios(args.scenario))
    print(f"\nRenode sim ({ran}): every assertion passed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
