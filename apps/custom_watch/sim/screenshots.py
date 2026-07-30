#!/usr/bin/env python3
"""Screenshot every screen the Renode sim can arm, as PNGs plus a contact sheet.

`ci_smoke.py` dumps a panel to assert it is *not blank*; nothing has ever made
those frames viewable. So the only way to LOOK at the firmware's UI was to run
`bin/watch-sim.sh --gui` and page through 30-odd screens by hand, one at a time,
which is why layout regressions have only ever been caught by a human noticing.
This walks the cycle once and writes every screen out, so the whole UI is one
scrollable page and a bad layout is visible instead of merely non-blank.

Two booted sessions, because the run view and the idle faces are disjoint — the
page cycle only exists mid-run, and the idle faces are only reachable before one
starts:

  `run`  — mountain_loop, autostart, with `terrain`'s two arming steps (the
           BMP581 triangle profile and a BTN5-hold waypoint mark) so Waypoint
           and Climb are in the cycle rather than legitimately filtered out of
           it. Walks one full BTN4 lap and dumps every page it reports.
  `idle` — bench_jog, `--no-autostart`, so the three §291 + §358 idle faces
           (home / diagnostics / ICE) and the §351 settings menu are reachable.

Every capture is named by the ui task's own line — `ui: page <Name>` for a run
page, `ui: idle <View>` for an idle face — so `page-Pacer.png` is the panel the
composer said it composed as Pacer, not a guess, and each press cross-checks
that line against the button task's intent the way `scenario_pages` does. Same
evidence rule as ci_smoke.py: the sim can say WHICH screen rendered and that it
inked pixels; whether the glyphs are the right glyphs is a host-test claim
(`render/src/preview.rs`), not a sim one.

A frame under an alert banner is rejected and re-shot, detected on the captured
pixels (the banner is a solid inverse-video band over the two hero rows) rather
than by waiting for `record: alert cleared` — past roughly 100 s the sim's
shortened cadences go banner-to-banner and that line stops arriving, which is
exactly when a 30-screen walk is still running.

The PNGs are the panel only (168x144, no bezel) and pure 1-bit black/white —
`DumpFrame`'s own output, unretouched, so they are honest about what the glass
shows. The contact sheet is where presentation happens: it frames each panel in
the five-button shell and can tint it to the reflective silver-green a real
Sharp MIP reads as, which is a viewing aid and labelled as one.

Usage:
  bin/watch-shots.sh                       # both sessions -> /tmp/watch-shots
  bin/watch-shots.sh --session run         # just the run-view cycle
  bin/watch-shots.sh --out-dir docs/shots  # somewhere durable
"""

import argparse
import base64
import html
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ci_smoke as ci

# mountain_loop, not bench_jog: the run session arms `terrain`'s climb, and a
# flat fixture cannot produce one. Every page bench_jog arms, mountain_loop
# arms too, so this is a superset — there is no reason to shoot the flat one.
RUN_FIXTURE = "mountain_loop"
IDLE_FIXTURE = "bench_jog"

# The ui task's own idle-face line — what the panel COMPOSED, the idle
# equivalent of `ui: page`. Waiting on the button task's `BTN4 -> idle view`
# instead is a race, and one this harness lost on its first run: the press is
# logged before the composer has repainted, so the dump landed on the previous
# face and two different faces came out byte-identical.
IDLE_COMPOSED = re.compile(r"ui: idle (\w+)")
IDLE_INTENT = re.compile(r"button: BTN4 -> idle view (\w+)")
MENU_LINE = re.compile(r"button: BTN5 -> settings menu")

# One lap plus slack. The walk stops on its own when it returns to the page it
# started on; this only bounds a cycle that never closes.
MAX_PRESSES = 48


def png_from_ppm(ppm: Path, png: Path):
    """Convert DumpFrame's P6 to a 1-bit greyscale PNG, pixel for pixel.

    No scaling here on purpose: the file stays the panel's true 168x144 so it
    can be diffed and measured, and the contact sheet scales it with
    `image-rendering: pixelated` instead of baking an interpolation in.
    """
    subprocess.run(
        [
            "magick",
            str(ppm),
            "-depth",
            "1",
            "-type",
            "Bilevel",
            "-define",
            "png:color-type=0",
            str(png),
        ],
        check=True,
        capture_output=True,
    )


# An alert banner is a solid inverse-video band across the two hero rows
# (168x32), so a bannered frame inks far more of that band than any hero
# numeral can. Measured on the captured pixels rather than inferred from the
# log: `ci_smoke.wait_for_no_alert` waits for `record: alert cleared`, and the
# sim's shortened cadences go banner-to-banner past roughly 100 s so that line
# stops arriving — which is exactly when a 30-screen walk is still running.
HERO_BAND_ROWS = 2
CELL_H = 16
BANNER_INK_FRACTION = 0.5
BANNER_ATTEMPTS = 4
BANNER_SETTLE_S = 3.0


def hero_band_ink_fraction(panel) -> float:
    """Share of the two hero rows that is dark, from the dumped PPM's pixels."""
    band_h = HERO_BAND_ROWS * CELL_H
    dark = 0
    for y in range(min(band_h, panel.height)):
        for x in range(panel.width):
            if panel.data[(y * panel.width + x) * 3] < 128:
                dark += 1
    return dark / (band_h * panel.width)


class Shots:
    """The captures from one session, in the order they were taken."""

    def __init__(self, out_dir: Path):
        self.out_dir = out_dir
        self.items = []
        self.shell = None

    def take(self, sim, slug: str, title: str, note: str, must_differ_from=None):
        """Dump, reject the frame if it is not the one asked for, keep the rest.

        Two rejections, both measured on the captured pixels rather than
        inferred: an alert banner over the hero, and — when `must_differ_from`
        is given — a frame identical to the previous screen's. The composer logs
        its page/face line BEFORE it draws and flushes, so a dump sent the
        instant that line decodes can still read the panel's PREVIOUS frame.
        That is not hypothetical: it is how this harness first "proved" the two
        idle faces render identically — and then, on the very first sheet, how
        `page-Nav.png` came back byte-identical to `page-Climb.png`. The run walk
        had been exempted on the grounds that "its elapsed clock changes every
        frame anyway", which is false: only the dashboard and a handful of pages
        show a clock, so a Climb frame at 116 s and the same frame at 124 s are
        the same bytes. Every capture is checked now.

        The race itself is gone at the source (the ui task logs `ui: page` AFTER
        the flush since § 361, so the line means the panel HAS the screen). This
        stays as the detector, because it also catches the other cause: a state
        that never reached the composer at all.
        """
        ppm = f"{slug}.ppm"
        panel = None
        bannered = False
        stale = False
        for attempt in range(1, BANNER_ATTEMPTS + 1):
            panel = sim.dump(ppm, f"the {title} panel frame")
            ci.assert_rendered(panel, title)
            bannered = hero_band_ink_fraction(panel) >= BANNER_INK_FRACTION
            stale = must_differ_from is not None and panel.data == must_differ_from
            if not bannered and not stale:
                break
            if attempt < BANNER_ATTEMPTS:
                why = "an alert banner" if bannered else "the previous frame"
                ci.announce(
                    f"{title} came back under {why} — re-shooting "
                    f"(attempt {attempt}/{BANNER_ATTEMPTS})"
                )
                time.sleep(BANNER_SETTLE_S)
        if stale:
            # Loud, because after this many tries it is no longer a repaint race:
            # the composer reported the screen and produced the previous frame.
            ci.error(
                f"{title} is byte-identical to the previous screen after "
                f"{BANNER_ATTEMPTS} tries — the ui task reported composing it, so "
                "either the state never reached the composer or the two screens "
                "genuinely render the same pixels"
            )
            note = f"{note} — identical to the previous screen"
        png = self.out_dir / f"{slug}.png"
        png_from_ppm(self.out_dir / ppm, png)
        ink = 100.0 * panel.dark / (panel.width * panel.height)
        if bannered:
            # Kept, not dropped: a bannered frame of a real page is worth more
            # than a hole in the sheet, as long as it says so.
            note = f"{note} — alert banner over the hero"
            ci.announce(f"captured {title} still bannered after {BANNER_ATTEMPTS} tries")
        self.items.append(
            {"slug": slug, "title": title, "note": note, "png": png, "ink": ink}
        )
        ci.announce(f"captured {title} ({panel.dark} dark px, {ink:.1f}% ink)")
        return panel.data

    def take_shell(self, sim, slug: str, title: str, note: str):
        """Capture the whole --gui canvas — case, keys and panel — not the LCD.

        A different artifact from the panel shots, and kept out of the page grid
        for that reason: it is in colour, it is a different size, and it asserts
        nothing about the firmware. It is what the window looks like.
        """
        ppm = self.out_dir / f"{slug}.ppm"
        if ppm.exists():
            ppm.unlink()
        sim.monitor().send(f"sysbus.spi3.display DumpCanvas @{ppm}")
        ci.wait_for_file(ppm, 45, f"the {title} canvas dump")
        png = self.out_dir / f"{slug}.png"
        subprocess.run(["magick", str(ppm), str(png)], check=True, capture_output=True)
        self.shell = {"title": title, "note": note, "png": png}
        ci.announce(f"captured {title} (full canvas)")


def capture_run(sim, shots: Shots):
    """Walk one full BTN4 lap of the page cycle, dumping every page it reports."""
    sim.wait(
        re.compile(r"baro: BMP581 streaming"),
        120,
        "the baro task to reach the BMP581 model — without it the climb "
        "detector reads GPS altitude and the Climb page never arms",
    )
    ci.require_recording(sim)

    # Both arming steps are `scenario_terrain`'s, for its reasons: the triangle
    # profile after the run starts (ClimbDetector resets on Recorder::start, so
    # gain banked before that is gain it never sees), and the BTN5 hold because
    # a marked waypoint is the only thing that puts the Waypoint page in the
    # cycle.
    sim.monitor().send(
        f"sysbus.twi1.bmp581 StartTriangleProfile {ci.TRIANGLE_LOW_M} "
        f"{ci.TRIANGLE_HIGH_M} {ci.TRIANGLE_UP_MM_S} {ci.TRIANGLE_DOWN_MM_S}"
    )
    ci.announce("BMP581 triangle profile armed")

    mark = sim.tail.mark()
    sim.monitor().send("runMacro $btn5h")
    try:
        sim.wait(
            re.compile(r"run_flash: persisted waypoints \((\d+)\)"),
            ci.PAGE_STEP_TIMEOUT,
            "the BTN5 hold to mark a waypoint",
            start=mark,
        )
        ci.passed("a waypoint is marked — the Waypoint page can enter the cycle")
    except ci.SmokeFailure as exc:
        # Not fatal to a screenshot run: it costs one page, and reporting the
        # loss beats aborting a 30-screen capture over it.
        ci.announce(f"waypoint mark did not land ({exc}) — Waypoint will be absent")

    gain_re = re.compile(r"baro: alt=(-?[\d.]+)m gain=([\d.]+)m")
    deadline = time.monotonic() + ci.BARO_GAIN_TIMEOUT
    best = 0.0
    while best < ci.CLIMB_OPEN_GAIN_M and time.monotonic() < deadline:
        sim.alive()
        sim.tail.poll()
        for line in sim.tail.lines:
            m = gain_re.search(line)
            if m:
                best = max(best, float(m.group(2)))
        time.sleep(0.5)
    if best >= ci.CLIMB_OPEN_GAIN_M:
        ci.passed(f"baro gain reached {best:.1f} m — the Climb page can enter the cycle")
    else:
        ci.announce(f"baro gain reached only {best:.1f} m — Climb will be absent")

    anchor = sim.wait(
        ci.PAGE_LINE, 60, "the ui task's boot-time page anchor"
    ).group(1)
    ci.announce(f"cycle anchored at {anchor}")

    seen = set()
    presses = 0
    # The anchor page is on screen now, so shoot it before the first press or
    # the lap-closing test below skips it.
    previous = shots.take(sim, f"page-{anchor}", anchor, "run view, page cycle")
    seen.add(anchor)

    while presses < MAX_PRESSES:
        presses += 1
        page = ci.press_page(sim, "$btn4", f"BTN4 press {presses}")
        if page in seen:
            ci.passed(
                f"the cycle closed after {presses} presses — {len(seen)} pages captured"
            )
            break
        seen.add(page)
        previous = shots.take(
            sim,
            f"page-{page}",
            page,
            "run view, page cycle",
            must_differ_from=previous,
        )
    else:
        ci.announce(f"stopped at the {MAX_PRESSES}-press cap without closing the cycle")


def capture_idle(sim, shots: Shots):
    """Shoot the three idle faces and the settings menu.

    Resolved exactly the way the page walk resolves a page: the ui task's own
    `ui: idle <View>` line is what the panel COMPOSED, the button task's
    `BTN4 -> idle view <View>` is what the press INTENDED, and each press
    asserts they agree. Disagreement means the face advanced without the panel
    following — the same bug class the page walk guards, which the idle faces
    had no line to guard until now.
    """
    sim.wait(
        re.compile(r"gps: fix"),
        180,
        "a GPS fix, so the idle face has a satellite count and a clock to draw",
    )
    anchor = sim.wait(
        IDLE_COMPOSED, 60, "the ui task's boot-time idle-face anchor ('ui: idle <View>')"
    ).group(1)
    previous = shots.take(
        sim, f"idle-{anchor}", f"Idle {anchor}", "idle, §291 home face"
    )
    shots.take_shell(
        sim,
        "shell",
        "The sim window",
        "the --gui canvas on the home face: case, five §350 keys, reflective panel",
    )

    for n in (1, 2):
        mark = sim.tail.mark()
        sim.monitor().send("runMacro $btn4")
        try:
            composed = sim.wait(
                IDLE_COMPOSED,
                ci.PAGE_STEP_TIMEOUT,
                f"the ui task to compose the next idle face after BTN4 press {n} "
                "('ui: idle <View>')",
                start=mark,
            ).group(1)
            intent = sim.wait(
                IDLE_INTENT,
                5,
                f"the button task to report the face it selected on BTN4 press {n}",
                start=mark,
            ).group(1)
        except ci.SmokeFailure as exc:
            ci.announce(f"idle face {n} not reached ({exc})")
            break
        if intent != composed:
            ci.error(
                f"BTN4 press {n} selected idle face {intent} but the ui task "
                f"composed {composed} — state::IDLE_VIEW did not reach the composer"
            )
        previous = shots.take(
            sim,
            f"idle-{composed}",
            f"Idle {composed}",
            "idle, BTN4 face walk",
            must_differ_from=previous,
        )

    mark = sim.tail.mark()
    sim.monitor().send("runMacro $btn5")
    try:
        sim.wait(
            MENU_LINE,
            ci.PAGE_STEP_TIMEOUT,
            "BTN5 to open the §351 settings menu",
            start=mark,
        )
    except ci.SmokeFailure as exc:
        ci.announce(f"settings menu did not open ({exc})")
        return
    shots.take(
        sim,
        "idle-settings",
        "Settings menu",
        "idle, §351 settings menu",
        must_differ_from=previous,
    )


# The bezel labels mirror the §81 Garmin-Fenix button positions the sim model
# draws and `docs/custom_watch/navigation.md` prices: BTN5 upper-left, BTN2
# mid-left, BTN3 lower-left, BTN1 upper-right, BTN4 lower-right.
BEZEL_LEFT = [("BTN5", "lap"), ("BTN2", "stop"), ("BTN3", "◀ page")]
BEZEL_RIGHT = [("BTN1", "start"), ("BTN4", "page ▶")]

STYLE = """
:root {
  --bg: #10131a; --fg: #e8ecf4; --dim: #99a3b5; --line: #2a3040;
  --card: #171b25; --accent: #7ad1a8;
  --mip-paper: #cfd8cc; --mip-ink: #22261f;
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #f5f6f8; --fg: #14171d; --dim: #5b6474; --line: #d7dbe3;
    --card: #ffffff; --accent: #1d7a52;
  }
}
:root[data-theme="dark"] {
  --bg: #10131a; --fg: #e8ecf4; --dim: #99a3b5; --line: #2a3040;
  --card: #171b25; --accent: #7ad1a8;
}
:root[data-theme="light"] {
  --bg: #f5f6f8; --fg: #14171d; --dim: #5b6474; --line: #d7dbe3;
  --card: #ffffff; --accent: #1d7a52;
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2rem 1.5rem 4rem;
  background: var(--bg); color: var(--fg);
  font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
}
header { max-width: 62rem; margin: 0 auto 2rem; }
h1 { font-size: 1.45rem; margin: 0 0 .4rem; letter-spacing: -.01em; }
.sub { color: var(--dim); margin: 0 0 1.2rem; }
.sub code { font-size: .92em; }
.controls { display: flex; flex-wrap: wrap; gap: 1.25rem; align-items: center;
  padding: .85rem 1rem; border: 1px solid var(--line); border-radius: .6rem;
  background: var(--card); }
.controls label { display: flex; gap: .45rem; align-items: center; cursor: pointer;
  user-select: none; font-size: .92rem; }
.grid { max-width: 82rem; margin: 0 auto; display: grid; gap: 1.5rem;
  grid-template-columns: repeat(auto-fill, minmax(19rem, 1fr)); }
section.group { max-width: 82rem; margin: 2.5rem auto .9rem; }
section.group h2 { font-size: 1rem; text-transform: uppercase; letter-spacing: .09em;
  color: var(--dim); margin: 0 0 .3rem; }
section.group p { margin: 0; color: var(--dim); font-size: .9rem; }
figure { margin: 0; background: var(--card); border: 1px solid var(--line);
  border-radius: .7rem; padding: 1rem; }
figcaption { margin-top: .8rem; }
.name { font-weight: 600; }
.meta { color: var(--dim); font-size: .85rem; font-variant-numeric: tabular-nums; }
/* The device shell: bezel strips flanking the panel, mirroring the sim model. */
.watch { display: grid; grid-template-columns: auto 1fr auto; gap: .4rem;
  align-items: stretch; }
.bezel { display: flex; flex-direction: column; justify-content: space-around;
  gap: .35rem; }
.bezel.right { align-items: flex-end; }
.key { font-size: .6rem; line-height: 1.1; color: var(--dim); white-space: nowrap;
  border: 1px solid var(--line); border-radius: .25rem; padding: .12rem .3rem; }
.key b { color: var(--fg); font-weight: 600; }
.panel { background: #fff; border-radius: .2rem; overflow: hidden;
  display: flex; box-shadow: 0 0 0 1px var(--line); }
.panel img { width: 100%; height: auto; display: block;
  image-rendering: pixelated; }
/* Reflective-panel approximation. A viewing aid, not the captured pixels:
   the PNG is pure black/white; this recolours it toward the silver-green a
   Sharp MIP actually reads as under daylight. */
body.mip .panel { background: var(--mip-paper); }
body.mip .panel img { mix-blend-mode: multiply; filter: sepia(.18) saturate(.55); }
body.grid-off .grid { grid-template-columns: 1fr; max-width: 34rem; }
/* The shell shot is already a rendered device in colour — no bezel, no tint. */
figure.shell { grid-column: 1 / -1; max-width: 40rem; }
figure.shell img { width: 100%; height: auto; display: block;
  image-rendering: pixelated; border-radius: .4rem; }
footer { max-width: 62rem; margin: 3rem auto 0; padding-top: 1.2rem;
  border-top: 1px solid var(--line); color: var(--dim); font-size: .88rem; }
"""

SCRIPT = """
const body = document.body;
function bind(id, cls) {
  const el = document.getElementById(id);
  el.addEventListener('change', () => body.classList.toggle(cls, el.checked));
  body.classList.toggle(cls, el.checked);
}
bind('mip', 'mip');
bind('single', 'grid-off');
const zoom = document.getElementById('zoom');
function applyZoom() {
  document.querySelectorAll('.watch').forEach((w) => {
    w.style.maxWidth = (168 * zoom.value / 100) + 'px';
  });
  document.getElementById('zoomv').textContent = zoom.value + '%';
}
zoom.addEventListener('input', applyZoom);
applyZoom();
"""


def contact_sheet(groups, out: Path, generated: str):
    """One self-contained HTML file: PNGs inlined, no external requests."""
    parts = [
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
        "<title>custom_watch — sim screens</title>",
        f"<style>{STYLE}</style></head><body>",
        "<header>",
        "<h1>custom_watch — every screen the sim can arm</h1>",
        f"<p class=\"sub\">Captured from the Renode sim by "
        f"<code>bin/watch-shots.sh</code> on {html.escape(generated)}. "
        "Each image is the panel's true 168&times;144 output from "
        "<code>DumpFrame</code>, pure 1-bit, unretouched.</p>",
        "<div class=\"controls\">",
        "<label><input type=\"checkbox\" id=\"mip\"> Reflective-panel tint "
        "<span class=\"meta\">(viewing aid)</span></label>",
        "<label><input type=\"checkbox\" id=\"single\"> One per row</label>",
        "<label>Zoom <input type=\"range\" id=\"zoom\" min=\"100\" max=\"400\" "
        "step=\"50\" value=\"200\"> <span class=\"meta\" id=\"zoomv\"></span></label>",
        "</div></header>",
    ]

    shell = next((s.shell for _, _, s in groups if s.shell), None)
    if shell:
        b64 = base64.b64encode(shell["png"].read_bytes()).decode("ascii")
        parts.append(
            "<section class=\"group\"><h2>The device</h2>"
            f"<p>{html.escape(shell['note'])}</p></section>"
            "<div class=\"grid\"><figure class=\"shell\">"
            f"<img alt=\"{html.escape(shell['title'])}\" "
            f"src=\"data:image/png;base64,{b64}\">"
            f"<figcaption><div class=\"name\">{html.escape(shell['title'])}</div>"
            "<div class=\"meta\">DumpCanvas &middot; the whole --gui window, in "
            "colour</div></figcaption></figure></div>"
        )

    total = 0
    for title, blurb, shots in groups:
        if not shots.items:
            continue
        parts.append(
            f"<section class=\"group\"><h2>{html.escape(title)}</h2>"
            f"<p>{html.escape(blurb)}</p></section><div class=\"grid\">"
        )
        for item in shots.items:
            total += 1
            b64 = base64.b64encode(item["png"].read_bytes()).decode("ascii")
            keys_l = "".join(
                f"<span class=\"key\"><b>{k}</b> {v}</span>" for k, v in BEZEL_LEFT
            )
            keys_r = "".join(
                f"<span class=\"key\"><b>{k}</b> {v}</span>" for k, v in BEZEL_RIGHT
            )
            parts.append(
                "<figure>"
                "<div class=\"watch\">"
                f"<div class=\"bezel left\">{keys_l}</div>"
                f"<div class=\"panel\"><img alt=\"{html.escape(item['title'])} panel\" "
                f"src=\"data:image/png;base64,{b64}\"></div>"
                f"<div class=\"bezel right\">{keys_r}</div>"
                "</div>"
                f"<figcaption><div class=\"name\">{html.escape(item['title'])}</div>"
                f"<div class=\"meta\">{html.escape(item['note'])} &middot; "
                f"{item['ink']:.1f}% ink</div></figcaption></figure>"
            )
        parts.append("</div>")

    parts.append(
        f"<footer><p>{total} screens. A capture proves the named page composed "
        "and inked pixels &mdash; not that its glyphs are correct. Layout and "
        "value correctness are host-test claims "
        "(<code>render/src/preview.rs</code>, <code>core/</code>); see "
        "<code>docs/custom_watch/quality_standards.md</code> for what each "
        "verification rung may claim.</p></footer>"
        f"<script>{SCRIPT}</script></body></html>"
    )
    out.write_text("".join(parts), encoding="utf-8")


SESSIONS = ("run", "idle")


def run(args):
    for tool in ("renode", "defmt-print", "cargo", "magick"):
        if shutil.which(tool) is None:
            raise ci.SmokeFailure(f"{tool} is not on PATH — cannot capture")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + args.budget
    wanted = SESSIONS if args.session == "all" else (args.session,)
    groups = []

    for index, name in enumerate(wanted):
        print(f"\n=== session {name} ===", flush=True)
        shots = Shots(out_dir / name)
        shots.out_dir.mkdir(parents=True, exist_ok=True)
        # --no-alerts on both: a banner is a solid inverse-video band over the two
        # hero rows, so a page photographed under one is a photograph of the
        # banner. The re-shoot loop below can only wait a banner out if there are
        # gaps to wait for, and past ~100 s the sim's shortened cadences overlap
        # into a continuous one — which cost six of twenty-one run screens on the
        # first sheet, CLMB and the Dashboard among them. Dropping the cadences is
        # the fix; dropping `sim-autostart` would have worked too and would also
        # have taken the demo settings that arm most of the pages.
        launcher = ("--no-alerts",) if name == "run" else ("--no-autostart", "--no-alerts")
        fixture = RUN_FIXTURE if name == "run" else IDLE_FIXTURE
        try:
            with ci.sim_session(
                args, name, deadline, args.phone_port + index, fixture, launcher
            ) as sim:
                (capture_run if name == "run" else capture_idle)(sim, shots)
        except ci.SmokeFailure as exc:
            ci.error(f"session {name}: {exc}")
        if name == "run":
            groups.append(
                (
                    "Run view — the BTN4 page cycle",
                    f"One full lap on the {RUN_FIXTURE} fixture, with the climb "
                    "and waypoint arming that puts the terrain pages in it.",
                    shots,
                )
            )
        else:
            groups.append(
                (
                    "Idle — faces and the settings menu",
                    "Booted --no-autostart, so the pre-run faces BTN4 walks and "
                    "the BTN5 settings menu are reachable.",
                    shots,
                )
            )

    sheet = out_dir / "index.html"
    generated = time.strftime("%Y-%m-%d %H:%M %Z")
    contact_sheet(groups, sheet, generated)
    shot_count = sum(len(s.items) for _, _, s in groups)
    if not shot_count:
        raise ci.SmokeFailure("no screens were captured — see the session logs")
    print(f"\n{shot_count} screens captured. Open {sheet}", flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default=os.environ.get("RUNNER_TEMP", "/tmp") + "/watch-shots",
        help="where the PNGs and index.html land, one subdirectory per session",
    )
    parser.add_argument(
        "--session",
        choices=SESSIONS + ("all",),
        default="all",
        help="which session to boot",
    )
    parser.add_argument("--phone-port", type=int, default=7808)
    parser.add_argument("--boot-timeout", type=float, default=420)
    parser.add_argument("--budget", type=float, default=1500)
    args = parser.parse_args()

    try:
        return run(args)
    except ci.SmokeFailure as exc:
        ci.error(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
