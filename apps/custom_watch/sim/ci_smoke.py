#!/usr/bin/env python3
"""Boot the custom_watch firmware under Renode and assert on observable output.

The manual `bin/watch-sim.sh` session is the reference harness; this driver
wraps it so a CI runner can prove the sim still works end to end instead of
waiting for someone to run it by hand. It reuses the launcher rather than
re-implementing the boot sequence, so a regression in watch-sim.sh itself
(pty, defmt drain, monitor port, cleanup) also fails here.

What it asserts, in order, each grounded in the manual evidence under
sim/verification-2026-07-19/:

  1. the flash run store arms at boot            run_flash: run store armed
  2. the canned NMEA parses into an accepted fix gps: fix ... sats=N (N>=4)
  3. that fix starts a recording                 record: sim-autostart
  4. distance accumulates past a floor           record: recording dist=<m>
  5. the run face actually renders on the panel  DumpFrame -> non-blank PPM
  6. two BTN2 presses stop the run and commit    run_flash: stored run
  7. nothing panicked along the way

What it cannot cover, per decisions.md §314: BLE (the S140 SoftDevice does not
run under Renode), power draw, and any claim about real silicon — the sensor
models answer what the drivers believe about the parts.

Determinism: the altitude and NMEA sources are virtual-time driven with no
randomness, so a given firmware + fixture replays identically. Every wait here
is on a specific decoded log line with a deadline, never a fixed sleep — the
sole exception is the ~1.5 s gap between the two BTN2 presses, which must land
inside the firmware's 4 s stop-confirm window and so cannot wait on the "armed"
line (a block-buffered decoder could delay observing it past the window).

Usage:
  apps/custom_watch/sim/ci_smoke.py [--out-dir DIR] [--fixture NAME]
                                    [--phone-port N] [--budget SECONDS]

Requires: renode + defmt-print on PATH, and the sim-feature ELF already built
(the launcher builds it if not, but pre-building it in a separate step keeps a
compile failure distinguishable from a sim failure).
"""

import argparse
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]

MIN_DISTANCE_M = 20.0
MIN_DARK_PIXELS = 200
MIN_WHITE_PIXELS = 200
MIN_SATS = 4
STOP_ATTEMPTS = 3


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

    def search(self, pattern):
        for line in self.lines:
            m = pattern.search(line)
            if m:
                return m
        return None

    def wait(self, pattern, timeout, what, guard=None):
        deadline = time.monotonic() + timeout
        while True:
            self.poll()
            for line in self.lines:
                m = pattern.search(line)
                if m:
                    return m
            if guard is not None:
                guard()
            if time.monotonic() >= deadline:
                raise SmokeFailure(
                    f"expected {what} within {timeout:.0f}s — no decoded log line "
                    f"matched /{pattern.pattern}/ ({len(self.lines)} lines seen)"
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
    return width, height, dark


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


def run(args):
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    combined = out_dir / "sim-output.log"
    frame = out_dir / "frame.ppm"
    latest_link = out_dir / "watch-sim.latest"
    for stale in (combined, frame, latest_link):
        if stale.is_symlink() or stale.exists():
            stale.unlink()

    for tool in ("renode", "defmt-print", "cargo"):
        if shutil.which(tool) is None:
            raise SmokeFailure(f"{tool} is not on PATH — the sim cannot run without it")

    env = dict(os.environ)
    # The distance + fix assertions read DEBUG-level lines, and defmt filters
    # at compile time, so this has to be set for the build the launcher does.
    env["DEFMT_LOG"] = "debug"
    env["WATCH_SIM_LATEST"] = str(latest_link)

    cmd = [
        str(REPO_ROOT / "bin" / "watch-sim.sh"),
        "--fixture",
        args.fixture,
        "--phone-port",
        str(args.phone_port),
    ]
    announce(f"launching {' '.join(cmd)}")
    log_fh = combined.open("w")
    proc = subprocess.Popen(
        cmd,
        cwd=str(REPO_ROOT),
        env=env,
        stdout=log_fh,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    tail = LogTail(combined)
    started = time.monotonic()

    def alive():
        if proc.poll() is not None:
            raise SmokeFailure(
                f"bin/watch-sim.sh exited early with status {proc.returncode} — "
                f"see {combined}"
            )
        if time.monotonic() - started > args.budget:
            raise SmokeFailure(
                f"exceeded the {args.budget:.0f}s smoke budget before finishing"
            )

    monitor = None
    run_dir = None
    try:
        tail.wait(
            re.compile(r"Streaming defmt logs"),
            args.boot_timeout,
            "bin/watch-sim.sh to reach 'Streaming defmt logs' (Renode up, GPS pty "
            "created, defmt-rtt drain armed)",
            guard=alive,
        )
        passed("Renode booted the sim ELF and armed the defmt-rtt drain")

        run_dir = Path(os.readlink(latest_link))
        monitor_port = int((run_dir / "monitor.port").read_text().strip())
        announce(f"run dir {run_dir}, monitor port {monitor_port}")

        tail.wait(
            re.compile(r"run_flash: run store armed at"),
            60,
            "the flash run store to arm at boot ('run_flash: run store armed at "
            "0x…')",
            guard=alive,
        )
        passed("flash run store armed at boot")

        fix = tail.wait(
            re.compile(r"gps: fix lat=(-?[\d.]+) lon=(-?[\d.]+).*sats=(\d+)"),
            120,
            f"a parsed GPS fix from the {args.fixture} NMEA fixture "
            "('gps: fix lat=… sats=N')",
            guard=alive,
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

        tail.wait(
            re.compile(r"record: sim-autostart on first fix"),
            60,
            "the first accepted fix to start a recording "
            "('record: sim-autostart on first fix')",
            guard=alive,
        )
        passed("recording started on the first accepted fix")

        dist_re = re.compile(r"record: recording dist=([\d.]+)m")
        deadline = time.monotonic() + args.distance_timeout
        best = 0.0
        while True:
            alive()
            tail.poll()
            for line in tail.lines:
                m = dist_re.search(line)
                if m:
                    best = max(best, float(m.group(1)))
            if best >= MIN_DISTANCE_M:
                break
            if time.monotonic() >= deadline:
                raise SmokeFailure(
                    f"expected the recorder to accumulate at least "
                    f"{MIN_DISTANCE_M:.0f} m within {args.distance_timeout:.0f}s of "
                    f"the run starting; the highest 'record: recording dist=' seen "
                    f"was {best:.1f} m"
                )
            time.sleep(0.5)
        passed(f"distance accumulated to {best:.1f} m while recording")

        monitor = Monitor(monitor_port, out_dir / "monitor.log")
        monitor.send(f"sysbus.spi3.display DumpFrame @{frame}")
        wait_for_file(frame, 45, "a panel frame dump")
        width, height, dark = read_ppm(frame)
        total = width * height
        white = total - dark
        if dark < MIN_DARK_PIXELS or white < MIN_WHITE_PIXELS:
            raise SmokeFailure(
                f"the {width}x{height} panel does not look like a rendered face: "
                f"{dark} dark / {white} light pixels, expected at least "
                f"{MIN_DARK_PIXELS} of each (all-light = nothing drawn, all-dark = "
                "the frame decode is broken)"
            )
        passed(
            f"run face rendered on the {width}x{height} panel "
            f"({dark} dark pixels of {total})"
        )

        stored_re = re.compile(r"run_flash: stored run (\d+) \((\d+) B\) in slot (\d+)")
        stored = None
        for attempt in range(1, STOP_ATTEMPTS + 1):
            announce(f"BTN2 stop pair, attempt {attempt}/{STOP_ATTEMPTS}")
            monitor.send("runMacro $btn2")
            # Inside the firmware's 4 s stop-confirm window; see the module
            # docstring for why this one gap is not gated on a log line.
            time.sleep(1.5)
            monitor.send("runMacro $btn2")
            try:
                stored = tail.wait(
                    stored_re,
                    25,
                    "the stopped run to commit to the flash store "
                    "('run_flash: stored run N (M B) in slot S')",
                    guard=alive,
                )
                break
            except SmokeFailure as exc:
                if attempt == STOP_ATTEMPTS:
                    raise SmokeFailure(
                        f"{exc} — {STOP_ATTEMPTS} BTN2 press pairs were injected "
                        "and none produced a flash commit"
                    ) from exc
                announce("no commit yet — the injected press likely missed a poll")

        if tail.search(re.compile(r"button: BTN2 armed")) is None:
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

        text = tail.text()
        panics = [ln for ln in text.splitlines() if "panicked" in ln.lower()]
        if panics:
            raise SmokeFailure(
                "the firmware panicked during the run: " + panics[0].strip()
            )
        passed("no firmware panic in the decoded log")
    finally:
        if monitor is not None:
            monitor.close()
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        log_fh.close()
        if run_dir is not None:
            for name in ("renode.log", "defmt.raw"):
                src = run_dir / name
                if src.exists():
                    shutil.copy2(src, out_dir / name)
        announce(f"artifacts in {out_dir}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default=os.environ.get("RUNNER_TEMP", "/tmp") + "/watch-sim-ci",
        help="where the logs, panel dump and copied sim artifacts land",
    )
    parser.add_argument("--fixture", default="bench_jog")
    parser.add_argument("--phone-port", type=int, default=7788)
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
        help="hard wall-clock cap for the whole smoke run",
    )
    args = parser.parse_args()

    try:
        run(args)
    except SmokeFailure as exc:
        error(str(exc))
        tail_path = Path(args.out_dir) / "sim-output.log"
        if tail_path.exists():
            print("--- last 40 lines of sim output ---", file=sys.stderr)
            lines = tail_path.read_text(errors="replace").splitlines()
            for line in lines[-40:]:
                print(line, file=sys.stderr)
        renode_log = Path(args.out_dir) / "renode.log"
        if renode_log.exists():
            print("--- last 20 lines of renode.log ---", file=sys.stderr)
            for line in renode_log.read_text(errors="replace").splitlines()[-20:]:
                print(line, file=sys.stderr)
        return 1
    print("\nRenode sim smoke: every assertion passed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
