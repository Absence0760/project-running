#!/usr/bin/env python3
"""Live watch window for a running headless sim — the --gui replacement on
machines whose Renode build cannot start its own UI (the macOS arm64 .NET
build falls back to console mode: renode/renode#886).

Attaches to the sim's telnet monitor, polls `DumpCanvas` a few times a
second, and shows the device shell in a Tk window. Clicks on the drawn keys
are resolved by the display model's own `HitButtonAt` (no geometry copied
here) and fired as the watch.resc button macros, which press in VIRTUAL
time — a raw press/release pair over the socket lands milliseconds apart in
wall time, which the firmware's ~10 ms poll can miss entirely and its
tap-vs-hold classifier would misread under host load.

Left-click taps a key; right-click (or ctrl-click) holds it where a hold
macro exists (BTN3/BTN4: page grid, BTN5: mark waypoint / hold-erase rows).
Keys 1-5 tap too; shift+key holds.

The monitor connection stays open for the window's lifetime. Closing the
window detaches like watch-monitor.sh's Ctrl-C — the sim keeps running.

Run via bin/watch-view.sh, which resolves the running sim's port and picks a
tkinter-capable python.
"""

import argparse
import pathlib
import re
import socket
import sys
import tempfile
import tkinter as tk

PROMPT = re.compile(rb"\((?:watch|monitor)\)")
HOLD_MACROS = {2: "btn3h", 3: "btn4h", 4: "btn5h"}
POLL_MS = 200


class Monitor:
    """One persistent telnet-monitor connection; command/response in lockstep."""

    def __init__(self, port):
        self.sock = socket.create_connection(("localhost", port), timeout=10)
        self.sock.settimeout(10)
        self.buf = b""
        self.wait_prompt()

    def wait_prompt(self):
        while not PROMPT.search(self.buf):
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("monitor closed the connection")
            self.buf += chunk
        out, self.buf = self.buf, b""
        return out

    def run(self, command):
        self.sock.sendall(command.encode() + b"\n")
        return self.wait_prompt()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True, help="monitor telnet port")
    parser.add_argument("--title", default="custom_watch sim")
    args = parser.parse_args()

    try:
        mon = Monitor(args.port)
    except OSError as exc:
        print(f"cannot attach to the monitor on localhost:{args.port}: {exc}", file=sys.stderr)
        return 1

    canvas_ppm = pathlib.Path(tempfile.mkdtemp(prefix="watch-view.")) / "canvas.ppm"

    root = tk.Tk()
    root.title(args.title)
    root.resizable(False, False)
    label = tk.Label(root, borderwidth=0)
    label.pack()
    status = tk.StringVar(value="attached — click a key, or press 1-5 (shift = hold)")
    tk.Label(root, textvariable=status, anchor="w", padx=6).pack(fill="x")

    state = {"image": None, "dead": False}

    def die(reason):
        state["dead"] = True
        status.set(f"detached: {reason}")

    def refresh():
        if state["dead"]:
            return
        try:
            mon.run(f'sysbus.spi3.display DumpCanvas @{canvas_ppm}')
        except OSError as exc:
            die(f"sim gone? ({exc})")
            return
        try:
            state["image"] = tk.PhotoImage(file=str(canvas_ppm))
            label.configure(image=state["image"])
        except tk.TclError:
            pass  # frame not on disk yet — the next tick has it
        root.after(POLL_MS, refresh)

    def fire(index, hold):
        if state["dead"]:
            return
        if hold and index not in HOLD_MACROS:
            status.set(f"BTN{index + 1} has no hold gesture")
            return
        macro = HOLD_MACROS[index] if hold else f"btn{index + 1}"
        try:
            mon.run(f"runMacro ${macro}")
            status.set(f"sent ${macro}")
        except OSError as exc:
            die(f"sim gone? ({exc})")

    def click(event, hold=False):
        if state["dead"]:
            return
        try:
            reply = mon.run(f"sysbus.spi3.display HitButtonAt {event.x} {event.y}")
        except OSError as exc:
            die(f"sim gone? ({exc})")
            return
        hit = re.search(rb"(-?\d+)", reply)
        index = int(hit.group(1)) if hit else -1
        if index >= 0:
            fire(index, hold)

    label.bind("<Button-1>", click)
    label.bind("<Button-2>", lambda e: click(e, hold=True))
    label.bind("<Button-3>", lambda e: click(e, hold=True))
    label.bind("<Control-Button-1>", lambda e: click(e, hold=True))
    for n in range(5):
        root.bind(str(n + 1), lambda e, i=n: fire(i, hold=False))
        root.bind(f"<Shift-Key-{n + 1}>", lambda e, i=n: fire(i, hold=True))

    refresh()
    try:
        root.mainloop()
    finally:
        # Like watch-monitor.sh's Ctrl-C: drop the connection without sending
        # anything — the sim keeps running.
        mon.sock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
