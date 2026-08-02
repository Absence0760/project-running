#!/usr/bin/env python3
"""Boot the custom_watch firmware under Renode and assert on observable output.

The manual `bin/watch-sim.sh` session is the reference harness; this driver
wraps it so a CI runner can prove the sim still works end to end instead of
waiting for someone to run it by hand. It reuses the launcher rather than
re-implementing the boot sequence, so a regression in watch-sim.sh itself
(pty, defmt drain, monitor port, cleanup) also fails here.

Nine scenarios, selected with `--scenario` (default `all`). The five below are
the ones whose framing does not fit on a function docstring; `screens`, `idle`,
`workout` and `storm` each carry theirs on their own `scenario_*`.

`smoke` — the end-to-end pass. In order, each assertion grounded in the manual
evidence under sim/verification-2026-07-19/, except the two marked below:

  1. the flash run store arms at boot            run_flash: run store armed
  2. the canned NMEA parses into an accepted fix gps: fix ... sats=N (N>=4)
  3. the optical-HR driver reads the AFE model   hr: bpm N          (new)
  4. that fix starts a recording                 record: sim-autostart
  5. distance accumulates past a floor           record: recording dist=<m>
  6. the same fix reaches the PHONE link         tcp status frames  (new)
  7. the run face actually renders on the panel  DumpFrame -> non-blank PPM
  8. two BTN2 presses stop the run and commit    run_flash: stored run
  9. nothing panicked along the way

(3) and (6) are folded in here rather than given scenarios of their own because
neither needs anything this boot is not already doing, and a scenario costs a
whole emulator. Both cover a rail that had no assertion at all:

  - The MAX86177 model has existed since 2026-07-19 and was built to take the
    optical-HR path off the bench gate, but no scenario ever read a BPM off it.
    The whole chain — TWIM EasyDMA master, the model's tagged MEAS1/MEAS2 sample
    stream, the driver's AGC and pulse detector — could break and every scenario
    would still pass.
  - The phone link is the sim's SECOND rail and the one the mobile app consumes
    (`emulation CreateServerSocketTerminal` in watch.resc -> the dev-only Sim
    watch link screen). Nothing here had ever opened that socket, so the panel
    could be perfect while the link emitted nothing, and the only way to find out
    was for a human to run the mobile screen against it.

`alerts` — the on-run alert engine reaches the panel. The sim arms its own
shortened cadences under `sim-autostart` (drink 30 s / eat 45 s of moving time,
a 100 m distance arm, a 60 s elapsed arm, and a 5:00-5:20/km band the ~5:33/km
bench_jog fixture sits outside), so this asserts what that arming makes
inevitable and nothing more — see `scenario_alerts`. Boots `--no-course`: the
§380/§381 course-driven arms would otherwise hold the slot through the opening
quiet window the baseline dump depends on.

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

`terrain` — the two pages the flat fixture cannot arm. Runs on mountain_loop
with the BMP581 model's triangle profile started, marks a waypoint with the
BTN5 hold (`$btn5h`, §357), waits for the baro's cumulative gain to pass the
20 m a climb opens at (§359), then walks the cycle and asserts BOTH pages are
now in it and render. `pages` proves these two stay OUT of an unarmed cycle;
this proves they come INTO an armed one, which is the half a mis-wired
data-presence bit would pass silently. Note the baro profile is load-bearing:
`feed_gap` prefers baro altitude over the fix's, so the fixture's GPS ramp
alone is shadowed by the model's static default.

`dropout` — the recorder across a signal void, on the gps_dropout fixture. The
one scenario here whose subject is a bug that has actually happened: the fixture
was written for the 2026-07-19 manual pass and caught the un-ported
`run_recorder` #330 gap re-anchor, which froze distance for the REST of a run
after any 1 Hz dropout that displaced the runner past `MAX_JUMP_M`. It was fixed
that day and has been guarded by two host tests and nothing else since — the
fixture itself stayed manual, so the end-to-end path that surfaced it had no
regression guard at all. This is that guard. See `scenario_dropout`.

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

Sessions: one boot per scenario, which is what CI has always done (one step
each) and what `--scenario all` now does too. `alerts` and `pages` shared a boot
until 2026-07-29 on the grounds that neither disturbed the other; `alerts` in
fact consumed the quiet window `pages` needs, because past ~100 s the sim's
overlapping alert cadences never let a banner expire with nothing behind it and
`record: alert cleared` stops firing — see `plan_sessions`. Each session gets
its own phone port (`--phone-port` + session index) because watch.resc binds
that port at a FIXED number and watch-sim.sh aborts if it is still held — a
sequential re-launch must not race the previous Renode's teardown. `--budget` is
a cap on the WHOLE process, shared across sessions, so a per-scenario invocation
gets all of it and `--scenario all` splits it across every boot.

Determinism: the altitude and NMEA sources are virtual-time driven with no
randomness, so a given firmware + fixture replays identically. Every wait here
is on a specific decoded log line with a deadline, never a fixed sleep — the
exceptions are the two-press guards, which must land inside the firmware's 4 s
confirm window and so cannot wait on the "armed" line (a block-buffered decoder
could delay observing it past the window): the ~1.5 s gap between the two BTN2
presses (`smoke` and `workout` both stop a run), and the same gap between the
two BTN1 presses of `idle`'s factory erase, whose guard is that same window.
Each is delivered as a retried PAIR rather than a single press pair, because a
press that misses a poll is indistinguishable from one the guard rejected.

Usage:
  apps/custom_watch/sim/ci_smoke.py [--out-dir DIR] [--fixture NAME]
                                    [--phone-port N] [--budget SECONDS]
                                    [--scenario NAME]   (see SCENARIO_ORDER)

Requires: renode + defmt-print on PATH, and the sim-feature ELF already built
(the launcher builds it if not, but pre-building it in a separate step keeps a
compile failure distinguishable from a sim failure). `DEFMT_LOG=debug` is set
for the build the launcher does — the distance, fix and page assertions all
read debug-level lines, and defmt filters at compile time.
"""

import argparse
import itertools
import json
import math
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

# The band a BPM off the MAX86177 model has to land in. Max86177.cs synthesizes
# one synthetic beat every `PulsePeriodSamples` at its 100 Hz frame rate and
# defaults to 83, which is 6000/83 = ~72.3 BPM. The band is wide enough that the
# detector's own smoothing and the AGC's opening settle do not have to be pinned,
# and narrow enough that it is a claim: a detector that emitted a constant, a
# zero, or an ambient-driven 200 fails it. Widen this only by changing the
# model's period with it.
HR_BPM_MIN = 55
HR_BPM_MAX = 95
HR_TIMEOUT = 120

# The phone link's frame schema — `watch_core::link`, "v": 1. These key names are
# the contract the mobile decoder (`sim_watch_link.dart`) reads off the same
# bytes, so they are asserted by name rather than by count.
LINK_PROTOCOL_VERSION = 1
LINK_FRAME_KEYS = ("v", "uptime_s", "fix", "elev")
# Enough frames to see the uptime clock advance across several of them. The link
# emits one per second of virtual time, so this is a handful of seconds of run —
# and since watch.resc sets flushOnConnect, they are the CURRENT seconds rather
# than the first ones of the boot.
LINK_FRAMES_WANTED = 6
LINK_TIMEOUT = 90
# How far the link's fix may sit from the one the decoded log reported before they
# are different positions rather than the same one seen twice. defmt prints the
# f32 lat/lon with fewer digits than the link's %.6f, so byte equality is not
# available, and the two rails sample at different instants — a few seconds of
# skew is ~10 m at the fixture's ~3 m/s. 0.001 deg is ~110 m: loose enough to
# absorb that, tight enough that a fix from a different part of the ~350 m
# fixture, or a fabricated 0,0, fails it.
LINK_FIX_TOLERANCE_DEG = 0.001
# How far behind the run's own clock the first frame off a fresh connection may
# be before the link is replaying its backlog rather than reporting the present.
#
# This is the assertion that pins `flushOnConnect` in watch.resc. Without it the
# provider queues every frame written while no client was attached and replays
# the lot, so the first frame a client reads is the one from uptime_s = 1 — ten
# minutes stale on a ten-minute-old sim, on a surface (the mobile dev screen)
# whose entire job is to show what the watch is doing NOW. The window is wide
# because it only has to separate "the present" from "the beginning of the run".
LINK_LIVE_SKEW_S = 20.0

SCENARIO_ORDER = (
    "smoke",
    "alerts",
    "pages",
    "terrain",
    "dropout",
    "screens",
    "idle",
    "workout",
    "storm",
)

# The NMEA fixture each scenario was written against, and a property OF the
# scenario rather than of the invocation: `terrain` asserts a climb, which the
# flat bench_jog fixture cannot produce, so running it against the default
# would fail in a way that reads like a firmware regression. `--fixture`
# overrides all of them for a manual poke.
SCENARIO_FIXTURES = {
    "smoke": "bench_jog",
    "alerts": "bench_jog",
    "pages": "bench_jog",
    "terrain": "mountain_loop",
    "dropout": "gps_dropout",
    "screens": "bench_jog",
    # Idle-only: it never starts a run, so the fixture is just something for the
    # receiver to chew on while the thumb works the menu.
    "idle": "bench_jog",
    # The sim demo workout's steps are sized against THIS fixture: its ~1.5 m/s
    # of CREDITED distance (consecutive fixes step ~2.97 m against the 3.0 m
    # TRACK_THRESHOLD_M, so about half are absorbed) settles the 50-60 m steps
    # in ~33-40 s each. A slower fixture, or one whose min-move filter thins
    # harder, stretches the same five steps past this scenario's budget.
    "workout": "bench_jog",
    # Flat ground and a constant GPS altitude, which is what makes the scripted
    # weather the ONLY thing moving the reduced pressure — see `scenario_storm`.
    "storm": "bench_jog",
}

# Extra `bin/watch-sim.sh` flags a scenario needs to boot the firmware it
# asserts against: the composed data screens (§364) seat immediately after
# the Dashboard, so building them into every session would shift the page
# walk `pages` and `terrain` assert on; `idle` needs the run never to start;
# `workout` and `storm` need the alert slot to themselves; and `alerts`
# needs a course-free opening window for its quiet baseline.
SCENARIO_LAUNCHER_ARGS = {
    # `--no-alerts` as well: the shortened sim fuel cadences overlap into a
    # continuous banner past ~100 s, and a banner OWNS the hero band — it would
    # cover slot 0 of every screen and make the render assertions below vacuous.
    # The same reason `bin/watch-shots.sh` boots that way.
    "screens": ("--screens", "--no-alerts"),
    # The whole point of this one: no `sim-autostart`, so the watch stays on the
    # idle faces instead of paging a run view. `--no-workout` keeps the boot
    # exactly what it was when the demo workout rode `sim-autostart` (before
    # `sim-workout` split out): nothing here records, so an armed workout could
    # only ever be noise.
    "idle": ("--no-autostart", "--no-workout"),
    # `--no-alerts` drops the sim's shortened fuel / distance / time / pace
    # arms, leaving the hardware defaults (900 s drink, 1500 s eat of MOVING
    # time) — an order of magnitude past this scenario's ~180 s of run. The
    # workout's own edges are unconditional (they ride `sim-workout`, which the
    # launcher keeps on by default, not `sim-alerts`), so what is left in the
    # alert slot is exactly and only the
    # workout rail. That is what makes the COUNTING assertion possible: "one
    # end-of-step warning across the plan, and one only" is a claim about the
    # `ENDING_MIN_STEP_*` gate solely while nothing else can take the slot.
    # It also keeps a fuel banner off the two Workout page dumps, which a
    # banner would otherwise own (it covers the hero band). Arbitration between
    # a workout banner and a fuel one is `alerts`' surface, not this one's.
    # `--no-course` beside it since the §380/§381 cutoff + off-course arms:
    # those alert on DATA PRESENCE (the canned course's legs and cutoff
    # schedule), not on a sim setter, so `--no-alerts` cannot silence them —
    # and bench_jog leaves the course each lap, so an OffCourse banner
    # ping-pongs with the workout edges (each displacement re-queues it) and
    # the slot never reads `cleared` inside `wait_for_no_alert`'s window.
    "workout": ("--no-alerts", "--no-course"),
    # `--storm` compresses the § 376 trend window from three hours to 60 s, so a
    # front is readable inside a scenario's budget, and arms the banner through
    # the same setter a phone push feeds. `--no-alerts` for the same reason
    # `workout` takes it: the COUNT assertion below is a claim about the storm
    # arm's once-per-front hysteresis, and it only means that while nothing else
    # can take the single banner slot.
    # `--no-course` for the same §380/§381 reason as `workout` — this is the
    # scenario that caught it: the OffCourse / workout-edge handoff chain
    # never let the slot clear before the Storm page dump.
    # `--no-workout` closed the remaining leak (CI run 30709260463): the demo
    # workout's step banners are alerts too, each one displaces the storm
    # banner, and a displaced storm RE-QUEUES (§376 — no later reminder
    # exists), so the slot went banner-to-banner — Storm at 79 s,
    # WorkoutEnding at 86 s, Storm again at 94 s, WorkoutStep at 96 s, Storm
    # again at 104 s — and neither the once-per-front COUNT below nor
    # `wait_for_no_alert` could hold. With every non-storm arm unarmed, one
    # front is one banner and the TTL clear is deterministic.
    "storm": ("--storm", "--no-alerts", "--no-course", "--no-workout"),
    # `--no-course` for the same §380/§381 reason — the off-course arm rides
    # data presence, so it fires within the opening quiet window and the
    # baseline dump never lands on a bannerless frame. This scenario keeps
    # `sim-alerts` (the fuel / distance / time / pace arms ARE its subject);
    # none of its assertions read the course, and the course-driven kinds are
    # host-tested (`core/src/alerts.rs`), not sim-asserted.
    "alerts": ("--no-course",),
}

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

# `terrain`'s two pages. Both are absent from the bench_jog cycle by design —
# nothing marks a point there and the ground is flat — so they get their own
# scenario on mountain_loop rather than being bolted onto the walk above.
TERRAIN_PAGES = ("Waypoint", "Climb")

# The BMP581 triangle profile `terrain` arms. These are the rates BMP581.cs
# documents as tracking the mountain_loop fixture's own GPS altitude ramp
# (measured: ~417 mm/s over its 481 s climb, ~634 mm/s over its 316 s descent),
# so baro and GPS co-vary through the elevation complementary filter.
TRIANGLE_LOW_M = 1600
TRIANGLE_HIGH_M = 1800
TRIANGLE_UP_MM_S = 400
TRIANGLE_DOWN_MM_S = 600
# `watch_core::climb` opens a climb past 20 m of gain above the last low point
# (at >= 2% grade, which this fixture clears by an order of magnitude). The
# floor here carries a margin over that: the baro task's accumulator and the
# detector's low-point-relative gain are two different sums over the same ramp
# (the detector only samples on an accepted fix, which the min-move filter
# thins), so waiting for exactly 20 m can start the walk a few samples before
# the climb opens — which costs a whole extra lap of the cycle to notice. At
# TRIANGLE_UP_MM_S the margin is ~12 s of virtual time.
CLIMB_OPEN_GAIN_M = 25.0
BARO_GAIN_TIMEOUT = 240

# `dropout`'s numbers. The gps_dropout fixture is 40 clean 1 Hz fixes, then 40 s
# of void (fix-quality-0 GGA + void RMC), then 40 s of reacquire 122 m downrange
# of the last good fix — 122 m past `watch_core::record::MAX_JUMP_M` over a gap
# past `GPS_REANCHOR_AFTER_S`, which is precisely the #330 case.
#
# The void floor is the detection threshold, NOT the fixture's 40 s: the gap the
# firmware experiences is measured on the EMULATOR's clock, and virtual time
# drifts against the host's under load (the same reason watch.resc times its
# button holds on `ElapsedVirtualTime`). A loaded runner can compress the void,
# so the floor sits well above the ~4 s ordinary publish cadence and well below
# 40 — and the scenario reports a compressed void as a compressed void rather
# than as a frozen recorder.
DROPOUT_VOID_MIN_S = 12.0
# What the pre-void leg has to bank before the void is worth measuring. The
# fixture steps 2.98 m per fix against the 3.0 m TRACK_THRESHOLD_M, so about
# half of each pair is absorbed into the next and the leg credits ~113 m of its
# ~116 m of ground truth; this floor is a third of that, so it pins "the leg
# accrued" without pinning the filter's exact arithmetic.
DROPOUT_PRE_VOID_M = 40.0
# Growth after the reacquire that a stale anchor cannot produce. Set to
# `watch_core::record::TRACK_THRESHOLD_M`, because that is the smallest credit
# the recorder can make at all — anything under it was absorbed into the next
# hop and moved nothing. So a single accepted fix clears this by construction
# (on this fixture the first one credits ~5.97 m), and the claim stays the
# minimal one: distance moved AT ALL again, which is the bit #330 broke.
DROPOUT_RESUME_M = 3.0
# How long after the void's far edge the resume has to land, in the firmware's
# own clock. A real re-anchor credits on the FIRST accepted fix past the void —
# the rebase itself banks nothing, so the credit lands one accepted hop later,
# measured at 4.0 s. This bound says the resume is prompt rather than eventual,
# and it makes a broken firmware fail in seconds instead of at a wall-clock
# timeout. It is a secondary guard: DROPOUT_FIXTURE_RESTART_M below is the one
# that has to hold, because it does not depend on any clock.
DROPOUT_RESUME_WITHIN_S = 60.0
# A jump between consecutive published fixes big enough to be the NMEA feed
# restarting the fixture rather than a runner moving.
#
# This is the load-bearing bound on the resume search, and it exists because the
# first version of this scenario PASSED against a firmware with the re-anchor
# deliberately disabled. `bin/watch-sim.sh` loops the fixture; the loop teleports
# the runner ~354 m back to the start, and from there they walk toward the anchor
# a broken recorder is still holding, until the delta falls back under
# `MAX_JUMP_M` over a dt of minutes and is accepted — crediting ~98 m in one
# lump. Distance resumes, late and for entirely the wrong reason, and an
# unbounded resume check reads that as the re-anchor working. Measured at
# t=220.7 s against a void ending at t=126.9 s.
#
# 200 m sits between the two jumps this fixture actually contains: the ~354 m
# restart, and the 122 m the runner covered during the void (which is the
# reacquire the scenario is FOR, and lands at the void's far edge, before the
# window opens). Ordinary steps are ~3 m.
DROPOUT_FIXTURE_RESTART_M = 200.0
DROPOUT_TIMEOUT = 360
# A backstop only. The resume verdict comes from the firmware's clock passing
# DROPOUT_RESUME_WITHIN_S, not from wall time running out — this is here so a
# wedged emulator that stops producing snapshots altogether still fails.
DROPOUT_RESUME_TIMEOUT = 120
# Mirrors `watch_core::record::GPS_REANCHOR_AFTER_S`. Named here so the failure
# message can say which constant the observed gap has to clear.
GPS_REANCHOR_AFTER_S = 10
# Mirrors `Recorder::fix_stale_budget_s` — `max(fix_interval_s * 3, 10)`, which
# is 10 at the sim's 1 Hz cadence — and `fix_stale` compares STRICTLY past it.
# The recorder therefore cannot be paused at the instant the fixes stop, and the
# first seconds of a void legitimately still read `recording`. Equal to
# GPS_REANCHOR_AFTER_S today by coincidence, not by derivation: they answer
# different questions and are named apart so a change to one cannot silently
# move the other.
FIX_STALE_BUDGET_S = 10
# How far past the budget the flip may honestly land, derived from the
# firmware's clocks rather than measured and rounded up. `fix_stale` compares
# WHOLE seconds (`now_s` and the fix anchor are both `Instant::as_secs`
# truncations), so `> 10` first holds at an integer delta of 11 — up to one
# second past the budget (runs 30706635377 and 30712529705 each caught
# `recording` inside that second, at 10.3 s and 10.9 s). The anchor adds up to
# one more: `void_start` is the decoded stamp of the last `gps: fix` line,
# while the recorder stamps its whole-second anchor when it CONSUMES that fix
# off the channel, which can cross the next second boundary. Assertions about
# the settled state start after budget + slack; the frozen-distance check above
# them still covers the void from its first snapshot.
FIX_STALE_FLIP_SLACK_S = 2

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
# carries ~12-18 of the 38 pages, and the full cycle is 38.
MAX_PAGE_PRESSES = 48

# `record: alert <Kind>` on a raise, `record: alert cleared` when its TTL runs
# out. The kind carries its payload for the parameterised arms (`Distance(100)`,
# `Time(60)`).
# The idle settings menu (§351). Every one of these is the BUTTON task's own
# statement, which is what makes the pair with `ui: idle` worth asserting: the
# menu covers the idle face while open, so intent and composition are separate
# claims here exactly as they are for the run-view page cycle.
MENU_OPENED = re.compile(r"button: BTN5 -> settings menu")
MENU_CURSOR = re.compile(r"button: menu cursor -> (\w+)")
MENU_CLOSED = re.compile(r"button: settings menu closed \(([\w ]+)\)")
# The GNSS row's edit, and the one menu edit with a cross-checkable payload:
# the ladder is ordered by projected battery hours, so an edit right has to
# move the fix interval and the estimate the same way.
GNSS_MODE_SET = re.compile(r"button: gnss mode -> (\w+) \(fix interval (\d+)s, ~(\d+)h\)")
# The ui task's idle face, the BTN4 walk's observable (§291 + §358).
IDLE_VIEW = re.compile(r"ui: idle (\w+)")
# `face::IdleView` in BTN4 order, starting from the boot face. Hard-coded for
# the same reason as MENU_ROWS: the order is what the thumb learns.
IDLE_FACES = ("Home", "Diagnostics", "Ice")

# `settings_menu::ITEMS` order. Hard-coded rather than derived because the
# ORDER is the contract the runner's thumb learns — a reordering that both the
# firmware and a derived expectation followed would assert nothing.
MENU_ROWS = (
    "GnssMode",
    "HideEmpty",
    "Profile",
    "Backyard",
    "PairPhone",
    "Erase",
    "QnhRezero",
    "Ice",
)
# The §378 factory erase's two-press guard, both halves of it. The arm and the
# wipe are DIFFERENT lines on purpose: a scenario that matched one pattern for
# both could not tell an erase that fired on the first press from one that
# waited, which is the entire safety claim.
MENU_ERASE_ARMED = re.compile(r"button: menu -> factory erase armed")
MENU_ERASE_DONE = re.compile(r"button: FACTORY ERASE confirmed \(flash (\w+)\)")
# The RAM half, from the task that owns the recorder — the waypoints, the
# biometrics, the ICE card and the composed screens.
RECORD_ERASED = re.compile(r"record: factory erase")
# A menu press lands in well under a second (the button task polls at 50 Hz);
# 10 s is an order of magnitude of headroom for a loaded runner without making
# an expected-silent press — a ladder clamped at its end — cost half a minute.
MENU_STEP_TIMEOUT = 10
# `GnssMode`'s rungs (Performance / Balanced / Expedition). Only the COUNT is
# used — enough lefts to park at the end, then one fewer right to walk back —
# so this survives a rung being renamed but not one being added, which is the
# right sensitivity: a fourth rung should make someone re-read this scenario.
GNSS_LADDER_RUNGS = 3

# The §376 storm rail. The tracker's own defmt line, which is the only thing
# that can speak to a NUMBER — a page dump proves a frame was drawn, never that
# the tendency in it is right.
STORM_LINE = re.compile(
    r"baro: storm (\w+) delta=(-?[\d.]+)hPa qnh=(-?[\d.]+)hPa span=(\d+)s"
)
STORM_UNMEASURED = re.compile(r"baro: storm (Building|NoReference)")
STORM_RAISED = re.compile(
    r"baro: storm Storm delta=(-?[\d.]+)hPa qnh=(-?[\d.]+)hPa span=(\d+)s"
)
# The sea-level reference is dropped this many Pa per virtual second. Under
# `--storm` the trend window is 60 s, so this is -8 x 60 = -480 Pa = -4.8 hPa
# over the window — 20% past `watch_core::storm::STORM_FALL_HPA`, which is the
# margin that keeps the scenario off the threshold rather than on it.
STORM_FALL_PA_PER_S = 8
# The threshold the sim arms (watch_core::storm::STORM_FALL_HPA). Mirrored here
# because the assertion is about the FIRMWARE's constant, so a change to it
# reads as a scenario that needs re-thinking rather than one that quietly still
# passes.
STORM_FALL_HPA = 4.0
# A quiet atmosphere's residual. The BMP581 model serves a scripted pressure
# with no noise and bench_jog's GGA altitude is constant, so the only movement
# in the reduced pressure is float rounding — an order of magnitude under the
# steady band, and more than this means something is feeding the tracker an
# altitude it should not have.
STORM_QUIET_HPA = 0.5
# Two windows plus the minimum span, in seconds, is the least a 60 s-window
# tracker needs to have banked a full window of a scripted fall. Generous
# against emulator time drift, for the same reason `dropout`'s floor is.
STORM_TIMEOUT = 300

# The §359 climb rail. Two independent halves, so two patterns: the detector's
# own output (baro-fed, works with no course) and the crest read off the pushed
# course profile. A page dump can show neither — it proves a frame was drawn,
# never that a number in it is right.
CLIMB_ACTIVE = re.compile(r"climb: active gain=([\d.]+)m dist=([\d.]+)m grade=(-?[\d.]+)%")
CLIMB_CREST = re.compile(r"climb: crest dist=([\d.]+)m gain=([\d.]+)m grade=(-?[\d.]+)%")
# Enough of the approach to see it close rather than to see it exist: a frozen
# read looks identical to a live one over two samples.
CLIMB_CREST_MIN_SAMPLES = 5
CLIMB_TIMEOUT = 180

# The §354 / §356 structured-workout rail. Every one of these is a task's own
# statement rather than a reading of the panel: `record: workout armed` is the
# step list reaching the recorder over the same `state::WORKOUT` channel a
# phone's `WKT1` push lands on, and the three alert lines are the runner's own
# edges as the record task reports them (`WorkoutRunner`'s `transition_seq` /
# `ending_seq` / `complete`). A Workout page dump can show none of this — it
# says a frame was drawn, never which step it names.
WORKOUT_ARMED = re.compile(r"record: workout armed \((\d+) steps\)")
WORKOUT_STEP = re.compile(
    r"record: alert WorkoutStep \{ kind: (\w+), rep_index: (\d+), rep_total: (\d+) \}"
)
WORKOUT_ENDING = re.compile(r"record: alert WorkoutEnding\b")
WORKOUT_DONE = re.compile(r"record: alert WorkoutDone\b")
# The flush at stop: the summary that attributes the whole trail to the pushed
# frame (§356 — without it the phone deliberately discards the step records),
# and every way the v4 write can lose part of that trail while the run still
# commits. The loss pattern is asserted ABSENT, which is the only form the
# claim can take: the happy path of `push_step_result` is silent by design.
WORKOUT_STORED = re.compile(
    r"record: run (\d+) workout results stored \((\d+) planned steps\)"
)
WORKOUT_STORE_LOSS = re.compile(
    r"record: run \d+ workout (?:step \d+ dropped from storage"
    r"|summary (?:already stored|dropped)"
    r"|trail has no frame CRC)"
)
# The button task's own statement that it classified a BTN5 press as the lap
# command and is sending it (§357's tap tier; §354 makes the recorder double it
# as the step skip). The "intent" half of the same split `press_page` asserts,
# and what makes a press LOST between the button task's polls distinguishable
# from a skip that did not happen — only the first is safe to repeat.
LAP_PRESS = re.compile(r"button: Lap -> Lap\b")

# The demo workout `app/src/tasks/record.rs` queues under `sim-autostart`, in
# the order the alert engine reports its transitions: (kind, rep_index,
# rep_total). Hard-coded rather than derived for the same reason `MENU_ROWS`
# is — the sequence IS the contract, and an expectation derived from the same
# source as the behaviour asserts nothing.
#
# Note which end axis each step ends on, because the walk below covers both:
# warmup / reps / cooldown are DISTANCE steps (60 / 50 / 50 / 60 m), the
# recovery is a DURATION step (30 s). A runner that only ever settles distance
# steps advances three times and then stalls forever on the recovery.
WORKOUT_PLAN = (
    ("Warmup", 0, 0),
    ("Rep", 1, 2),
    ("Recovery", 1, 1),
    ("Rep", 2, 2),
    ("Cooldown", 0, 0),
)
# How much of the plan the recorder's own auto-advance carries before the
# scenario takes the lap key to the rest. Four transitions means three settled
# steps — two on distance, one on duration — so both end axes are exercised
# unaided; the last transition and the completion are then driven by BTN5,
# which is the §354 claim.
WORKOUT_AUTO_STEPS = 4
# Per auto-advanced step. The widest gap the demo workout produces on bench_jog
# is the ~40 s warmup, so this is several times the observed worst case — loose
# enough to absorb a loaded runner's virtual-time drift, and irrelevant to a
# broken firmware, which fails on the WRONG STEP the moment it reports one
# rather than on this deadline.
WORKOUT_STEP_TIMEOUT = 180
# The gap, in the FIRMWARE's own virtual seconds, inside which a lap press has
# to produce its edge for the press to be what caused it. Deliberately far
# under the steps BTN5 skips here: 50 m and 60 m, which the fixture's ~1.5 m/s
# of credited distance settles in ~33 s and ~40 s. Measured on the decoded
# stream's timestamps rather than on wall clock, because Renode's virtual clock
# runs at a ratio to wall time that swings with host load — a wall-clock bound
# would say nothing about how much of the step was left to run.
WORKOUT_SKIP_MAX_GAP_S = 15.0
# How long to wait for the edge a lap press produced. Deliberately LONGER than
# the step the press displaces, which is the opposite of what a deadline
# usually wants: a firmware whose lap press does nothing still ends the step on
# schedule, and the run that measured this wants that edge in hand so the gap
# assertion above can name the cause. Cut to 30 s the same broken firmware
# fails on a bare "no line matched" timeout instead, which says only that
# something did not arrive.
WORKOUT_EDGE_TIMEOUT = 90
# A lap press's own wait. Short on purpose, unlike `PAGE_STEP_TIMEOUT`: a lost
# press retried after 30 s would consume the very step window the gap above is
# measured against. The button task polls at 50 Hz, so the line lands in well
# under a second and 10 s is an order of magnitude of headroom — the same
# reasoning `MENU_STEP_TIMEOUT` carries.
WORKOUT_LAP_TIMEOUT = 10

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

# `dropout`'s two lines. The published-fix line is what marks the void's edges —
# its ABSENCE is the void, so the gap between consecutive matches is the signal —
# and the recorder's own snapshot line carries the distance the void must freeze.
# The snapshot line is emitted whenever the snapshot changes, and elapsed_s
# changes every second, so the void is densely sampled rather than inferred from
# two endpoints.
FIX_PUBLISHED = re.compile(r"gps: fix lat=(-?[\d.]+) lon=(-?[\d.]+)")
RECORD_SNAPSHOT = re.compile(r"record: (\w+) dist=([\d.]+)m")
# The virtual timestamp defmt-print puts at the head of every decoded line, in
# seconds. Virtual, not wall: every gap `dropout` reasons about is a gap the
# FIRMWARE saw, and the two clocks drift apart under host load.
LINE_STAMP = re.compile(r"^\s*([\d.]+)\s")

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

    def __init__(
        self,
        args,
        label,
        out_dir,
        deadline,
        phone_port,
        fixture,
        launcher_args=(),
    ):
        self.args = args
        self.label = label
        self.out_dir = out_dir
        self.deadline = deadline
        self.phone_port = phone_port
        self.fixture = fixture
        # Extra flags for bin/watch-sim.sh. No scenario here passes any — this
        # exists so screenshots.py can boot `--no-autostart` and reach the idle
        # faces, which every scenario in this file skips past by design.
        self.launcher_args = list(launcher_args)
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
            self.fixture,
            "--phone-port",
            str(self.phone_port),
            *self.launcher_args,
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
def sim_session(args, label, deadline, phone_port, fixture, launcher_args=()):
    sim = Sim(
        args,
        label,
        Path(args.out_dir) / label,
        deadline,
        phone_port,
        fixture,
        launcher_args,
    )
    try:
        sim.boot()
        yield sim
    finally:
        sim.shutdown()


def stamped(tail, pattern):
    """Every match of `pattern` so far, paired with its line's virtual timestamp.

    The other scenarios only ever need the newest match, which `LogTail.wait`
    gives them. `dropout` needs the WHOLE series and the times between its
    entries — a void is a hole in the fix stream, which no single line reports.
    A line whose stamp will not parse is dropped rather than guessed at: a
    timestamp is the evidence here, so a missing one must not become a 0.0 that
    reads as an enormous gap.
    """
    tail.poll()
    out = []
    for line in tail.lines:
        m = pattern.search(line)
        if m is None:
            continue
        stamp = LINE_STAMP.match(line)
        if stamp is not None:
            out.append((float(stamp.group(1)), m))
    return out


def read_link_frames(sim, wanted, timeout):
    """Read `wanted` newline-terminated status frames off the phone-link socket.

    These are the run's CURRENT seconds, not its first: Renode's server-socket
    provider queues everything UARTE1 wrote while no client was attached, and
    `watch.resc` passes `flushOnConnect` so that queue is dropped when a client
    arrives. `assert_link_frames` pins that, because it is the difference between
    a live view and a replay of the boot.

    A short read is not an error on its own; running out of time with fewer than
    `wanted` frames is, and says how many arrived.
    """
    deadline = time.monotonic() + timeout
    frames = []
    pending = ""
    with socket.create_connection(("127.0.0.1", sim.phone_port), timeout=10) as sock:
        sock.settimeout(1.0)
        while len(frames) < wanted:
            sim.alive()
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                chunk = b""
            except OSError as exc:
                raise SmokeFailure(
                    f"the phone-link socket on port {sim.phone_port} dropped after "
                    f"{len(frames)} frames: {exc}"
                ) from exc
            if chunk:
                pending += chunk.decode("utf-8", errors="replace")
                *complete, pending = pending.split("\n")
                frames.extend(line for line in complete if line.strip())
            elif time.monotonic() >= deadline:
                raise SmokeFailure(
                    f"the phone link produced {len(frames)} of {wanted} status "
                    f"frames on port {sim.phone_port} within {timeout:.0f}s. "
                    "watch.resc bridges UARTE1 to that port and the `phone` task "
                    "writes one watch_core::link frame per second, so either the "
                    "task is not running (it is compiled out under `--features "
                    "ble`, which the sim build must not carry) or the bridge is "
                    "not wired"
                )
    return frames[:wanted]


def assert_link_frames(sim, frames, log_fix, connected_at_s):
    """The four claims a batch of status frames carries.

    Schema, freshness, clock, payload. The payload one is why the others are worth
    making: it cross-checks the SAME fix against the decoded log, so the assertion
    is that one parsed fix reached both the panel rail and the phone rail — not
    merely that each rail produced something.

    `connected_at_s` is the run's own clock read just BEFORE the socket was
    opened, which is what makes the freshness claim checkable: a link honouring
    `flushOnConnect` opens on a frame from about then, and one replaying its
    backlog opens on the frame from uptime_s = 1.
    """
    decoded = []
    for raw in frames:
        try:
            decoded.append(json.loads(raw))
        except ValueError as exc:
            raise SmokeFailure(
                f"a phone-link frame is not valid JSON ({exc}): {raw[:120]!r} — the "
                "frame is built by `write!` into a fixed heapless::String, so a "
                "truncated one means it overflowed"
            ) from exc

    for frame in decoded:
        missing = [k for k in LINK_FRAME_KEYS if k not in frame]
        if missing:
            raise SmokeFailure(
                f"a phone-link frame is missing {', '.join(missing)}: {frame} — "
                "those key names are what the mobile decoder reads, so dropping "
                "or renaming one breaks the phone side silently"
            )
        if frame["v"] != LINK_PROTOCOL_VERSION:
            raise SmokeFailure(
                f"a phone-link frame declares schema v{frame['v']}, not "
                f"v{LINK_PROTOCOL_VERSION} — a version bump has to land on the "
                "mobile decoder in the same change"
            )
    passed(
        f"{len(decoded)} phone-link frames carry the v{LINK_PROTOCOL_VERSION} "
        f"schema ({', '.join(LINK_FRAME_KEYS)})"
    )

    uptimes = [frame["uptime_s"] for frame in decoded]
    behind = connected_at_s - uptimes[0]
    if behind > LINK_LIVE_SKEW_S:
        raise SmokeFailure(
            f"the first frame off a fresh connection reports uptime_s="
            f"{uptimes[0]}, {behind:.0f}s behind the run's clock at the moment "
            f"the socket was opened (t={connected_at_s:.0f}s) — the link is "
            "replaying the frames it queued while nothing was attached instead "
            "of reporting the present. watch.resc passes flushOnConnect to "
            "CreateServerSocketTerminal for exactly this; without it the mobile "
            "dev screen opens on the frame from the first second of the boot"
        )
    passed(
        f"a fresh connection opens on the present: first frame uptime_s="
        f"{uptimes[0]} against a run clock of t={connected_at_s:.0f}s "
        f"({behind:+.0f}s), so the backlog was flushed"
    )

    if any(b <= a for a, b in itertools.pairwise(uptimes)):
        raise SmokeFailure(
            f"the link's uptime_s is not strictly increasing: {uptimes} — it is "
            "`Instant::now().as_secs()`, so a repeat or a step backward is the "
            "monotonic clock breaking, which is what sim/NRF52840_RTC_Overflow.cs "
            "exists to prevent (the stock rtc1 model wrapped it every 512 s)"
        )
    passed(f"uptime_s advances monotonically across the batch ({uptimes[0]} -> {uptimes[-1]})")

    fixed = [frame for frame in decoded if frame["fix"] is not None]
    if not fixed:
        raise SmokeFailure(
            f"none of the {len(decoded)} frames carried a fix, though the log "
            f"reported one at lat={log_fix[0]} lon={log_fix[1]} — the link's "
            "`fix` is fed from state::FIX, so a null through a live fix means the "
            "phone task is not seeing that watch"
        )
    live = fixed[-1]["fix"]
    for key in ("lat", "lon", "speed_mps", "sats", "age_s"):
        if key not in live:
            raise SmokeFailure(
                f"the link's fix object is missing {key}: {live} — the mobile "
                "decoder reads it by name"
            )
    # The newest of each rail, not the first: the frames are live now, and the
    # two rails sample at different instants, so the pair that can agree is the
    # pair taken at about the same moment.
    drift = max(abs(live["lat"] - log_fix[0]), abs(live["lon"] - log_fix[1]))
    if drift > LINK_FIX_TOLERANCE_DEG:
        raise SmokeFailure(
            f"the link's newest fix is at {live['lat']},{live['lon']} but the "
            f"decoded log's newest was {log_fix[0]},{log_fix[1]} — {drift:.6f} deg "
            f"apart, past the {LINK_FIX_TOLERANCE_DEG} deg that the two rails' "
            "print precisions and their few seconds of sampling skew can account "
            "for. The two rails are reading different fixes"
        )
    if live["sats"] < MIN_SATS:
        raise SmokeFailure(
            f"the link's newest fix reports sats={live['sats']}, under the "
            f"{MIN_SATS} the same fixture carries on the log rail"
        )
    passed(
        f"the live fix reached the phone rail too: lat={live['lat']} "
        f"lon={live['lon']} sats={live['sats']} age_s={live['age_s']}, within "
        f"{LINK_FIX_TOLERANCE_DEG} deg of the log rail's newest"
    )


def fixture_restart_at(tail, after):
    """Virtual timestamp of the first published fix past `after` that jumps
    further than a runner could have moved — the NMEA feed replaying the fixture
    from its first sentence. None while the feed is still on its first pass.

    Equirectangular, like `watch_core::record`'s own projection and for the same
    reason: over a few hundred metres it is exact enough, and the number only has
    to separate ~354 m from ~3 m.
    """
    fixes = stamped(tail, FIX_PUBLISHED)
    for (_, a), (t, b) in zip(fixes, fixes[1:]):
        if t <= after:
            continue
        lat_a, lon_a = float(a.group(1)), float(a.group(2))
        lat_b, lon_b = float(b.group(1)), float(b.group(2))
        north = (lat_b - lat_a) * 111_320.0
        east = (lon_b - lon_a) * 111_320.0 * math.cos(math.radians(lat_a))
        if math.hypot(north, east) >= DROPOUT_FIXTURE_RESTART_M:
            return t
    return None


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
        f"a parsed GPS fix from the {sim.fixture} NMEA fixture "
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

    # The optical-HR rail. Asserted in two steps for the reason `terrain` splits
    # the baro the same way: the hr task parks itself on a probe timeout, and a
    # parked task produces no BPM for a reason that has nothing to do with the
    # pulse detector. Asking for the streaming line first makes those two
    # failures say different things.
    sim.wait(
        re.compile(r"hr: MAX86177 streaming"),
        HR_TIMEOUT,
        "the hr task to reach the MAX86177 model ('hr: MAX86177 streaming') — a "
        "parked task means the TWIM EasyDMA master never completed the presence "
        "probe, not that the pulse detector is wrong",
    )
    bpm = int(
        sim.wait(
            re.compile(r"hr: bpm (\d+)"),
            HR_TIMEOUT,
            "a trusted pulse off the MAX86177 model ('hr: bpm N') — the model "
            "synthesizes a beat every PulsePeriodSamples frames, so a driver that "
            "reads the tagged MEAS1/MEAS2 stream correctly has to find it",
        ).group(1)
    )
    if not HR_BPM_MIN <= bpm <= HR_BPM_MAX:
        raise SmokeFailure(
            f"the driver read {bpm} BPM off a model synthesizing ~72 (6000 / its "
            f"default 83-frame pulse period), outside the {HR_BPM_MIN}-"
            f"{HR_BPM_MAX} band — the pulse detector is locking onto something "
            "other than the model's beat (the ambient channel, the AGC's own "
            "steps, or a half/double-rate harmonic)"
        )
    passed(f"the optical-HR driver read {bpm} BPM off the MAX86177 model")

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

    # The phone rail. Read here rather than at boot for two reasons: the claim is
    # a CROSS-CHECK against the log rail, which needs a fix to have happened
    # first; and the connection has to open well into the run for the freshness
    # assertion to mean anything — a link replaying its backlog and a link
    # reporting the present are indistinguishable in the first seconds.
    log_fixes = stamped(sim.tail, FIX_PUBLISHED)
    connected_at_s = log_fixes[-1][0]
    newest = log_fixes[-1][1]
    assert_link_frames(
        sim,
        read_link_frames(sim, LINK_FRAMES_WANTED, LINK_TIMEOUT),
        (float(newest.group(1)), float(newest.group(2))),
        connected_at_s,
    )

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

    # The sim demo workout is always armed under sim-autostart, so the stop
    # must have flushed its planned-vs-actual trail into the blob before the
    # commit (run-store v4, decisions §356) — the summary log is the tell.
    workout_stored = sim.tail.search(
        re.compile(r"record: run \d+ workout results stored \((\d+) planned steps\)")
    )
    if workout_stored is None:
        raise SmokeFailure(
            "the run committed but 'record: run N workout results stored' "
            "never appeared — the armed demo workout's trail was not flushed"
        )
    passed(
        f"workout trail flushed into the blob "
        f"({workout_stored.group(1)} planned steps) before the commit"
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

    # A dump taken under a banner proves only that something was on the panel.
    # The pair is what carries the claim: the same page with no banner, then
    # with one. The banner is a solid inverse-video band over the two hero rows,
    # so it has to add far more ink than the hero it replaces.
    #
    # The baseline is taken FIRST, in the run's opening quiet window, because
    # that is the only stretch in which the alert slot going idle is something
    # the sim's arming makes INEVITABLE rather than something to race for.
    # `record: alert cleared` is logged solely on the record task's Some -> None
    # transition, so a slot handed straight from one alert to the next never
    # emits it; once the sim's cadences overlap (30 s drink / 45 s eat / 60 s
    # time / 100 m distance / the workout's own step alerts) the chain is
    # unbroken and the line stops firing altogether — the regime this module's
    # header already describes. Sampling AFTER waiting on two arbitrary alerts
    # therefore demanded a guarantee the alert engine does not make, and lost
    # whenever the second arm to fire was a late one: a run whose arms landed
    # Drink then Distance never saw another clear inside the timeout.
    #
    # The opening window is different in kind. The armed workout raises its
    # warm-up step within a millisecond of the first fix, that single alert is
    # the only thing holding the slot, and the earliest competing cadence is
    # 30 s of MOVING time — so its TTL expiry is due with nothing behind it and
    # leaves a wide bannerless stretch after it. That is the one `cleared` the
    # scenario can count on, so it is the one the baseline is taken against.
    #
    # Both halves of the pair still race the PANEL the same way, and the
    # baseline is the half that fails silently: the record task's line leads the
    # screen task's repaint, so a dump can still carry the banner it is meant to
    # be the baseline for. Sample a few times and keep the LOWEST — a stale
    # quiet frame can only ever read too inky, never too clean, so the minimum
    # is the one that cannot be the lagging one. Sampling stops early if a new
    # alert takes the slot mid-window, so a late sample cannot quietly inflate
    # the baseline and blunt the delta the banner assertion below demands.
    wait_for_no_alert(sim)
    quiet = None
    for attempt in range(1, ALERT_QUIET_ATTEMPTS + 1):
        if latest_alert(sim.tail) not in (None, "cleared"):
            break
        shot = sim.dump(
            f"alert-quiet-{attempt}.ppm", "a panel frame with no alert on screen"
        )
        if latest_alert(sim.tail) not in (None, "cleared"):
            break
        assert_rendered(shot, "the run face between alerts")
        if quiet is None or shot.dark < quiet.dark:
            quiet = shot
    if quiet is None:
        raise SmokeFailure(
            "no panel frame could be dumped in the run's opening quiet window — "
            "an alert took the slot again between the first one clearing and the "
            "first dump landing, so there is no baseline to measure a banner's "
            "ink against"
        )
    announce(f"quiet baseline: {quiet.dark} dark pixels (lowest of {ALERT_QUIET_ATTEMPTS})")

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


def scenario_terrain(sim):
    """Arm the two pages that need terrain and prove they enter the cycle.

    `pages` walks the cycle on bench_jog, where Waypoint and Climb are
    LEGITIMATELY absent — nothing marks a point and the ground is flat — so
    until now both were verified only negatively: the harness proved they stay
    out of an unarmed cycle, never that they come into an armed one. A page can
    fail that way silently (a data-presence bit wired to the wrong field reads
    exactly like "no data"), which is the gap this closes.

    Two arming steps, and neither is incidental:

    **The baro ramp.** `Recorder::feed_gap` takes `baro_alt_m.or(fix.alt_m)` —
    baro FIRST. The BMP581 model defaults to a static 1600 m, so mountain_loop's
    GGA altitude ramp is shadowed by a flat baro and the climb detector sees
    level ground however steep the fixture is. Starting the model's triangle
    profile is therefore load-bearing, not scene-setting: without it this
    scenario fails while the firmware is correct. The rates (400 mm/s up,
    600 mm/s down between 1600 m and 1800 m) are the ones BMP581.cs documents as
    tracking this fixture's GPS ramp, so baro and GPS co-vary through the
    elevation complementary filter instead of fighting it.

    **The BTN5 hold.** §357's mark is the only way a waypoint exists, and it is
    a gesture no other scenario makes — `$btn5h` was added for this.

    What this proves and what it does not: the pages enter `Snapshot::pages_mask`
    and render non-blank. As everywhere else here, nothing reads a glyph — the
    page identity is the firmware's own `ui: page <Name>` line, and the mark is
    the record task's `run_flash: persisted waypoints`. That the WPT page shows
    the RIGHT bearing, or the CLMB page the right metres-remaining, is a
    host-test claim (`core/src/climb.rs`, `core/src/record.rs`), not a sim one.
    """
    # Assert the model is actually being read before leaning on it. The baro
    # task parks itself on a probe timeout, and a parked baro would leave the
    # climb detector on GPS altitude — a different code path, silently.
    sim.wait(
        re.compile(r"baro: BMP581 streaming"),
        120,
        "the baro task to reach the BMP581 model ('baro: BMP581 streaming') — "
        "a parked task would leave the climb detector reading GPS altitude "
        "instead, which is not what this scenario means to exercise",
    )
    passed("the baro task is streaming from the BMP581 model")

    require_recording(sim)

    # Armed AFTER the run starts, deliberately. The baro task's cumulative gain
    # accumulates from boot, while `ClimbDetector` is reset by `Recorder::start`
    # — so a ramp armed first banks gain the detector never sees, and the poll
    # below would clear its floor while the detector was still short of it. Same
    # start line for both, and the two track each other.
    sim.monitor().send(
        f"sysbus.twi1.bmp581 StartTriangleProfile {TRIANGLE_LOW_M} "
        f"{TRIANGLE_HIGH_M} {TRIANGLE_UP_MM_S} {TRIANGLE_DOWN_MM_S}"
    )
    announce(
        f"BMP581 triangle profile armed ({TRIANGLE_LOW_M}-{TRIANGLE_HIGH_M} m, "
        f"up {TRIANGLE_UP_MM_S} mm/s, down {TRIANGLE_DOWN_MM_S} mm/s)"
    )

    # §357: the mark takes the recorder's distance anchor, so it needs a run
    # that has actually accepted a fix — which `require_recording` just proved.
    mark = sim.tail.mark()
    sim.monitor().send("runMacro $btn5h")
    sim.wait(
        re.compile(r"button: Lap -> MarkWaypoint"),
        PAGE_STEP_TIMEOUT,
        "the BTN5 hold to be classified as the §357 mark tier "
        "('button: Lap -> MarkWaypoint') rather than as a manual lap",
        start=mark,
    )
    stored = sim.wait(
        re.compile(r"run_flash: persisted waypoints \((\d+)\)"),
        PAGE_STEP_TIMEOUT,
        "the marked waypoint to reach the config page "
        "('run_flash: persisted waypoints (N)') — a mark refused for want of a "
        "position anchor warns instead and writes nothing",
        start=mark,
    )
    passed(f"BTN5's hold marked and persisted {stored.group(1)} waypoint(s)")

    # The climb detector opens past CLIMB_OPEN_GAIN_M above the last low point.
    # Polled on the baro task's own cumulative gain rather than on the page
    # appearing, so a stalled ramp reports as a stalled ramp instead of as a
    # missing page 200 lines later.
    gain_re = re.compile(r"baro: alt=(-?[\d.]+)m gain=([\d.]+)m")
    deadline = time.monotonic() + BARO_GAIN_TIMEOUT
    best = 0.0
    while True:
        sim.alive()
        sim.tail.poll()
        for line in sim.tail.lines:
            m = gain_re.search(line)
            if m:
                best = max(best, float(m.group(2)))
        if best >= CLIMB_OPEN_GAIN_M:
            break
        if time.monotonic() >= deadline:
            raise SmokeFailure(
                f"the baro gain reached only {best:.1f} m in "
                f"{BARO_GAIN_TIMEOUT}s, short of the {CLIMB_OPEN_GAIN_M:.0f} m "
                "a climb opens at — the triangle profile is not advancing (or "
                "the elevation filter is rejecting it), so the Climb page below "
                "would be absent for a reason that is not the page's fault"
            )
        time.sleep(0.5)
    passed(f"baro gain accumulated to {best:.1f} m — past the climb-open floor")

    # The detector's OWN output, which the gain above does not stand in for:
    # gain is the baro accumulator, and a climb opening is `ClimbDetector`
    # deciding the accumulated rise is a climb. The Climb page's presence in the
    # cycle below does not separate them either — the page opens on a live
    # ascent OR a crest ahead.
    active = sim.wait(
        CLIMB_ACTIVE,
        CLIMB_TIMEOUT,
        "the climb detector to open a climb ('climb: active gain=<N>m ...')",
    )
    passed(
        f"the detector opened a climb: {float(active.group(1)):.1f} m gained over "
        f"{float(active.group(2)):.0f} m at {float(active.group(3)):.0f}% average grade"
    )

    # The crest read off the pushed course profile — the ClimbPro headline, and
    # the one number on the page a runner acts on. Asserted as a TREND, not a
    # value: `record.rs`'s own doc warns that a position frozen by a lost signal
    # keeps reporting the crest from where the runner was, so the metres
    # remaining stop falling while they climb. A single sample cannot tell that
    # apart from a live read; a falling series can.
    deadline = time.monotonic() + CLIMB_TIMEOUT
    while True:
        sim.alive()
        crests = [
            (float(m.group(1)), float(m.group(2)))
            for _, m in stamped(sim.tail, CLIMB_CREST)
        ]
        if len(crests) >= CLIMB_CREST_MIN_SAMPLES:
            break
        if time.monotonic() >= deadline:
            raise SmokeFailure(
                f"only {len(crests)} crest reading(s) in {CLIMB_TIMEOUT}s, short of "
                f"the {CLIMB_CREST_MIN_SAMPLES} needed to see one close — either "
                "the course profile never reached the recorder, or the runner's "
                "along-course position did, which is what the crest is measured "
                "from"
            )
        time.sleep(0.5)
    for (prev_d, prev_g), (dist, gain) in itertools.pairwise(crests):
        if dist >= prev_d:
            raise SmokeFailure(
                f"the crest stopped closing: {prev_d:.1f} m then {dist:.1f} m "
                "while the runner climbed toward it — a stale along-course "
                "position reports the crest from where they WERE, which leaves "
                "the one number on the page they act on stuck"
            )
        if gain > prev_g:
            raise SmokeFailure(
                f"the metres still to climb ROSE, {prev_g:.0f} m to {gain:.0f} m, "
                "on an approach to a fixed summit"
            )
    passed(
        f"the crest closes as the runner climbs: {len(crests)} readings from "
        f"{crests[0][0]:.0f} m / {crests[0][1]:.0f} m to climb, down to "
        f"{crests[-1][0]:.0f} m / {crests[-1][1]:.0f} m"
    )

    walk = []
    dumps = {}
    presses = 0
    while presses < MAX_PAGE_PRESSES and len(dumps) < len(TERRAIN_PAGES):
        presses += 1
        page = press_page(sim, "$btn4", f"BTN4 press {presses}")
        walk.append(page)
        if page in TERRAIN_PAGES and page not in dumps:
            wait_for_no_alert(sim)
            dumps[page] = sim.dump(f"page-{page}.ppm", f"the {page} page's panel frame")
            assert_rendered(dumps[page], f"the {page} page")
            announce(f"{page} rendered ({dumps[page].dark} dark pixels)")

    missing = [p for p in TERRAIN_PAGES if p not in dumps]
    if missing:
        raise SmokeFailure(
            f"{', '.join(missing)} never appeared in the BTN4 cycle over "
            f"{presses} presses (walked: {' -> '.join(walk)}). Both are armed by "
            "this scenario and by nothing else: Waypoint needs the BTN5 hold "
            "above to have marked a point (Snapshot::waypoint_count > 0), Climb "
            "needs a live ascent or a crest ahead (!ClimbView::is_empty). Both "
            "arming steps asserted green above, so a page missing HERE is a "
            "data-presence bug, not an unarmed fixture — do not widen the walk"
        )
    passed(
        f"the BTN4 cycle reached both terrain pages in {presses} presses "
        f"({' -> '.join(walk)})"
    )


def scenario_dropout(sim):
    """Cross a GPS signal void and prove the recorder comes back from it.

    The gps_dropout fixture is three legs: 40 clean 1 Hz fixes, a 40 s void of
    fix-quality-0 GGA and void RMC, then 40 s of reacquire 122 m downrange of the
    last good fix. Those numbers are the point. 122 m clears
    `watch_core::record::MAX_JUMP_M`, so the reacquire fix fails the one-hop cap;
    the gap clears `GPS_REANCHOR_AFTER_S`, so it is a real signal gap rather than
    a corrupt teleport and the anchor must REBASE to it. Before that re-anchor was
    ported from `run_recorder` (its #330), the stale anchor only ever receded and
    distance was frozen for the rest of the run.

    That bug is why this scenario exists. It was found by running this exact
    fixture by hand on 2026-07-19, fixed the same day, and guarded since by two
    host tests over `Recorder` — never by anything that drives the whole path from
    NMEA bytes through the parser and the publish cadence into the recorder. The
    fixture stayed a manual poke. So the class of regression that would slip past
    the host tests — a parser that stops emitting through the void, a publish
    cadence that swallows the reacquire, a fix-quality gate that lets the void's
    empty GGA through as a fix at 0,0 — had no guard at all.

    Three claims, in the order the run produces them:

      1. the pre-void leg banks distance
      2. the void freezes it, and every sample inside the void reads `paused` —
         an auto-pause is the honest read of "no fixes", and a recorder that kept
         crediting distance through a void would be inventing it
      3. the reacquire moves it again

    (3) is the #330 guard. (2) is what makes (3) mean something: distance that
    never stopped growing would satisfy (3) trivially.

    **Why the void is measured and not assumed.** The void's length in the
    FIRMWARE's clock is not the fixture's 40 s — the NMEA feeder is wall-clock
    driven while the emulator's virtual clock drifts against the host's under
    load, the same skew `watch.resc` times its button holds around. A host slow
    enough to compress the void under `GPS_REANCHOR_AFTER_S` would leave the
    anchor legitimately held and distance legitimately frozen, and reporting that
    as a frozen recorder would be a lie. So the gap is read off the decoded
    stream's own timestamps and reported when it is too short.

    **The resume search stops where the fixture restarts.** `watch-sim.sh` loops
    the NMEA file, and the loop teleports the runner ~354 m back to its start —
    from where they walk toward the anchor a broken recorder is still holding,
    until the delta falls back under `MAX_JUMP_M` over a dt of minutes and
    credits ~98 m in one lump. Distance resumes, for entirely the wrong reason.
    The first version of this scenario passed against a firmware with the
    re-anchor disabled on exactly that. The restart is found in the published-fix
    stream itself (`fixture_restart_at`) rather than timed around, because
    Renode's virtual clock runs at a ratio to wall time that swings with host
    load and the loop is paced by the wall.
    """
    require_recording(sim)

    # The pre-void leg. Not `MIN_DISTANCE_M`: the freeze below is only meaningful
    # against a distance that was visibly moving, and this fixture's leg banks
    # ~113 m before the void, so the floor can sit well clear of the first hop.
    deadline = time.monotonic() + DROPOUT_TIMEOUT
    best = 0.0
    while True:
        sim.alive()
        for _, m in stamped(sim.tail, RECORD_SNAPSHOT):
            best = max(best, float(m.group(2)))
        if best >= DROPOUT_PRE_VOID_M:
            break
        if time.monotonic() >= deadline:
            raise SmokeFailure(
                f"the recorder banked only {best:.1f} m before the void, short of "
                f"the {DROPOUT_PRE_VOID_M:.0f} m floor — the fixture's clean "
                "opening leg is not reaching the recorder, so nothing below can "
                "distinguish a freeze from a run that never moved"
            )
        time.sleep(0.5)
    passed(f"the pre-void leg banked {best:.1f} m")

    # The void, found as a hole in the published-fix stream. Polled rather than
    # waited on a line, because the evidence is the ABSENCE of lines: the gap only
    # becomes visible once a fix arrives on the far side of it.
    void = None
    while void is None:
        sim.alive()
        fixes = stamped(sim.tail, FIX_PUBLISHED)
        for (start, _), (end, _) in itertools.pairwise(fixes):
            if end - start >= DROPOUT_VOID_MIN_S:
                void = (start, end)
                break
        if void is not None:
            break
        if time.monotonic() >= deadline:
            widest = max(
                (b[0] - a[0] for a, b in itertools.pairwise(fixes)), default=0.0
            )
            raise SmokeFailure(
                f"no gap of {DROPOUT_VOID_MIN_S:.0f}s or more appeared in the "
                f"published-fix stream within {DROPOUT_TIMEOUT}s (widest seen: "
                f"{widest:.1f}s of virtual time over {len(fixes)} fixes). Either "
                "the fixture's 40 s void never arrived, or the void's empty "
                "fix-quality-0 GGA sentences are being accepted as fixes — which "
                "would be the honest-staleness bug, not a missing void — or the "
                "emulator compressed the void below the floor because the host is "
                "too slow to run this fixture"
            )
        time.sleep(0.5)
    void_start, void_end = void
    span = void_end - void_start
    if span < GPS_REANCHOR_AFTER_S:
        raise SmokeFailure(
            f"the void spanned only {span:.1f}s of the firmware's clock, under "
            f"the {GPS_REANCHOR_AFTER_S}s GPS_REANCHOR_AFTER_S floor — the "
            "emulator ran the fixture's 40 s void short, so the recorder is right "
            "to hold its anchor and the re-anchor below cannot be exercised. This "
            "is a host-speed report, not a firmware verdict"
        )
    passed(
        f"the fixture's void reached the firmware as a {span:.1f}s hole in the "
        f"published-fix stream (t={void_start:.1f}s to t={void_end:.1f}s), past "
        f"the {GPS_REANCHOR_AFTER_S}s re-anchor floor"
    )

    # The freeze. Every snapshot strictly inside the void, not just its endpoints:
    # a recorder that credited the void's displacement in one lump at the far edge
    # would pass an endpoint-only check.
    inside = [
        (t, m) for t, m in stamped(sim.tail, RECORD_SNAPSHOT) if void_start < t < void_end
    ]
    if not inside:
        raise SmokeFailure(
            f"the recorder published no snapshot inside the {span:.1f}s void — it "
            "publishes on every change and elapsed_s changes every second, so a "
            "void with no snapshots in it means the record task stopped ticking "
            "when the fixes stopped, which is a stall and not a pause"
        )
    frozen = float(inside[0][1].group(2))
    moved = [(t, float(m.group(2))) for t, m in inside if float(m.group(2)) != frozen]
    if moved:
        t, d = moved[0]
        raise SmokeFailure(
            f"distance moved from {frozen:.1f} m to {d:.1f} m at t={t:.1f}s, "
            "inside a void with no fixes in it — the recorder is crediting "
            "distance it cannot have measured"
        )
    # The pause is owed once the fix-stale budget has elapsed, not at the instant
    # the fixes stop: `fix_stale` compares strictly past `fix_stale_budget_s`, so
    # the opening seconds of a void honestly still read `recording` and the frozen
    # distance above is what holds them to account. Asserting this from void_start
    # made the verdict depend on where the first snapshot happened to land against
    # the last fix — it passed locally and failed on a CI runner from that alone.
    # The deadline carries FIX_STALE_FLIP_SLACK_S on top of the budget for the
    # same reason one comment block up: the strict `>` runs on whole-second
    # clocks, so a bare `void_start + budget` deadline re-created that lottery
    # one second later and lost it twice in one day (runs 30706635377,
    # 30712529705).
    pause_deadline = void_start + FIX_STALE_BUDGET_S + FIX_STALE_FLIP_SLACK_S
    settled = [(t, m) for t, m in inside if t > pause_deadline]
    if not settled:
        raise SmokeFailure(
            f"the {span:.1f}s void produced no snapshot past the "
            f"{FIX_STALE_BUDGET_S}s fix-stale budget plus its "
            f"{FIX_STALE_FLIP_SLACK_S}s whole-second flip slack (deadline t="
            f"{pause_deadline:.1f}s), so the auto-pause this scenario exists to "
            "prove was never observable"
        )
    running = [(t, m.group(1)) for t, m in settled if m.group(1) != "paused"]
    if running:
        t, state = running[0]
        raise SmokeFailure(
            f"the recorder read '{state}' at t={t:.1f}s, {t - void_start:.1f}s into "
            f"a void with no fixes and past the {FIX_STALE_BUDGET_S}s fix-stale "
            f"budget plus the {FIX_STALE_FLIP_SLACK_S}s the whole-second clocks "
            "can honestly add, not 'paused' — a stretch with no fixes has to "
            "auto-pause, or the run view is telling the runner it is still "
            "tracking them"
        )
    passed(
        f"distance held at {frozen:.1f} m across all {len(inside)} snapshots in the "
        f"void, and every one of the {len(settled)} past the "
        f"{FIX_STALE_BUDGET_S}s(+{FIX_STALE_FLIP_SLACK_S}s) fix-stale budget "
        "read paused"
    )

    # The re-anchor. Growth after the far edge of the void, and before the NMEA
    # feed restarts the fixture — see DROPOUT_FIXTURE_RESTART_M for why that
    # second bound is the one that has to hold. This is the single bit #330
    # broke, and the one a host test over `Recorder` alone cannot place at the
    # end of a real NMEA pipeline.
    resumed = None
    window_end = void_end + DROPOUT_RESUME_WITHIN_S
    resume_deadline = time.monotonic() + DROPOUT_RESUME_TIMEOUT
    while resumed is None:
        sim.alive()
        restart = fixture_restart_at(sim.tail, after=void_end)
        horizon = min(window_end, restart) if restart is not None else window_end
        samples = stamped(sim.tail, RECORD_SNAPSHOT)
        for t, m in samples:
            if void_end < t <= horizon and float(m.group(2)) - frozen >= DROPOUT_RESUME_M:
                resumed = (t, float(m.group(2)))
                break
        if resumed is not None:
            break
        # The verdict is the run's own evidence passing the horizon, not the
        # host's patience running out: once a snapshot lands past it the answer
        # is in, whatever the emulator's speed.
        latest_t = samples[-1][0] if samples else 0.0
        if latest_t > horizon:
            held = float(samples[-1][1].group(2))
            why = (
                f"the fixture restarted at t={restart:.1f}s"
                if restart is not None and restart <= window_end
                else f"the {DROPOUT_RESUME_WITHIN_S:.0f}s after it"
            )
            raise SmokeFailure(
                f"distance stayed at {held:.1f} m from the void's end at "
                f"t={void_end:.1f}s until {why}, never clearing the frozen "
                f"{frozen:.1f} m by the {DROPOUT_RESUME_M:.0f} m a single credited "
                "hop would add. The reacquire fix is 122 m from the last good one "
                f"over a {span:.1f}s gap, so `Recorder::on_fix` must rebase the "
                "anchor to it (GPS_REANCHOR_AFTER_S) instead of holding a stale "
                "one. This is run_recorder's #330 — with the anchor held, every "
                "later delta only grows and distance is frozen for the rest of the "
                "run"
            )
        if time.monotonic() >= resume_deadline:
            raise SmokeFailure(
                f"no recorder snapshot reached t={horizon:.1f}s within "
                f"{DROPOUT_RESUME_TIMEOUT}s of wall clock — the emulator stopped "
                "advancing, so neither a resume nor its absence can be read"
            )
        time.sleep(0.5)
    t, dist = resumed
    passed(
        f"distance resumed {t - void_end:.1f}s after the void: {frozen:.1f} m -> "
        f"{dist:.1f} m, so the reacquire rebased the anchor rather than freezing "
        "behind a stale one (run_recorder #330)"
    )

    panics = [ln for ln in sim.tail.text().splitlines() if "panicked" in ln.lower()]
    if panics:
        raise SmokeFailure("the firmware panicked during the run: " + panics[0].strip())
    passed("no firmware panic across the void")


def scenario_screens(sim):
    """Walk to the runner's own composed data screens and prove they render.

    The seam this closes: everything about `SCR1` up to here is host-tested —
    the frame, the flash record, the slot renders, the placement arithmetic —
    but nothing had put a Duo or a Trio on a panel. Two claims that only the
    emulated display can make: the pages are actually IN the cycle (the gate
    admits exactly the screens the sim seeded), and their multi-value layouts
    draw without one slot erasing another.

    `--screens` seeds three (Duo / Trio / Single) through `state::SCREENS`, the
    same channel a phone push feeds, so this exercises the real publish → gate →
    render path rather than a shortcut into the face.

    What it does NOT prove: that a tired runner can read them at 45 cm. That is
    a step-4 bench claim by our own quality_standards.md, and no simulator
    settles it — see decisions § 364.
    """
    require_recording(sim)

    anchor = sim.wait(
        PAGE_LINE, 60, "the ui task's boot-time page anchor ('ui: page <Name>')"
    ).group(1)
    if anchor != START_PAGE:
        raise SmokeFailure(
            f"the ui task's first page line reports {anchor}, not {START_PAGE}"
        )

    # The three seeded screens seat immediately after the Dashboard (§364), so
    # they are the first three pages a forward tap reaches. That ordering IS the
    # feature — a runner's own screen one press from home — so assert the
    # sequence, not merely that the pages exist somewhere in the cycle.
    want = ["Screen1", "Screen2", "Screen3"]
    dumps = {}
    for expected in want:
        got = press_page(sim, "$btn4", "the BTN4 tap")
        if got != expected:
            raise SmokeFailure(
                f"a forward tap landed on {got}, not {expected} — the composed "
                "screens are not seated immediately after the Dashboard, so a "
                "runner's own screen is not one press from home"
            )
        panel = sim.dump(f"page-{expected}.ppm", f"the {expected} panel dump")
        if panel.dark == 0:
            raise SmokeFailure(f"{expected} rendered a blank panel")
        dumps[expected] = panel
        announce(f"{expected} rendered ({panel.dark} dark pixels)")
    passed(
        "the three composed screens are the first three pages after the "
        "Dashboard, and each renders a non-blank panel"
    )

    # A Duo draws two 32x48 values, a Trio one plus two 16x32 — different
    # amounts of ink. Byte-identical frames would mean a DumpFrame never landed
    # and the assertions above read a stale file.
    for a, b in itertools.pairwise(want):
        if dumps[a].data == dumps[b].data:
            raise SmokeFailure(
                f"the {a} and {b} dumps are byte-identical — DumpFrame did not "
                "write a fresh frame, so the per-screen render assertions above "
                "prove nothing"
            )
    passed("the three screen dumps are distinct frames — each DumpFrame landed fresh")

    # The fourth screen was never composed, so its page must not be in the
    # cycle: a fourth tap has to leave the composed block for the live-metric
    # cluster rather than opening a blank Screen4.
    after = press_page(sim, "$btn4", "the BTN4 tap")
    if after == "Screen4":
        raise SmokeFailure(
            "a fourth tap opened Screen4, which the runner never composed — the "
            "cycle is carrying a blank seat"
        )
    passed(f"the uncomposed fourth screen is not in the cycle (tap landed on {after})")


def press_menu(
    sim,
    macro,
    what,
    pattern=MENU_CURSOR,
    timeout=MENU_STEP_TIMEOUT,
    required=True,
):
    """One settings-menu press, resolved by the line the button task emits.

    Retries a silent press exactly like `press_page` does, and for the same
    reason: a macro drives the GPIO low for a fixed window and the button task
    samples on a poll, so an injected press can land between polls and be lost.
    Writing this without the retry made the scenario flaky — the first run
    passed and the next lost the second BTN3 of the walk. Only a press that
    produced NOTHING is repeated, so a retry can never double-count a move.

    `required=False` returns None instead of raising, for presses whose whole
    point is that they may legitimately do nothing (a ladder clamped at its
    end). Those are not retried: silence is the expected answer, so a retry
    only doubles the wait for it.

    Unlike `press_page` there is no second task to cross-check: the menu's rows
    are the button task's own model. What the panel does with them is asserted
    separately, by the dumps.
    """
    attempts = PAGE_PRESS_ATTEMPTS if required else 1
    for attempt in range(1, attempts + 1):
        mark = sim.tail.mark()
        sim.monitor().send(f"runMacro {macro}")
        try:
            return sim.wait(pattern, timeout, what, start=mark)
        except SmokeFailure:
            if attempt < attempts:
                announce("no menu line seen — the injected press likely missed a poll")
                continue
            if not required:
                return None
            raise
    raise AssertionError("unreachable")


def scenario_idle(sim):
    """The idle surfaces: the settings menu (§351) and the faces BTN4 walks (§358).

    Boots `--no-autostart`, which is the point: every other scenario in this
    file starts a run on the first fix and pages the RUN view, so the idle
    surfaces — the settings menu here, the faces BTN4 walks — had no scenario
    at all. The `Sim` docstring says as much ("every scenario in this file skips
    past by design"); this is the one that does not.

    Three rails share one boot. The menu: BTN5 opens it and it reaches the
    panel, BTN3 walks all seven rows in their documented order and wraps, BTN2
    walks back, an edit on the GNSS row moves the ladder, BTN4 closes it. Then
    the three faces BTN4 walks — Home, Diagnostics, and the §358 ICE card a
    responder reads off a collapsed runner's wrist — each rendering a distinct
    frame, plus the menu's own MEDICAL ID row as the card's second route in.
    Then §378's factory erase, last because it resets the ladder the middle
    rail spent its presses walking.

    The erase's assertions are about the GUARD as much as the wipe. One press
    has to emit the ARM line and change the panel; stepping off the row and
    back has to leave the next press arming again rather than confirming; only
    then does the second adjacent press wipe. A row wired straight through
    would fail the first of those, and a guard that armed but never cancelled
    would fail the second — which is the whole safety claim, since neither is
    visible in a scenario that just presses twice and looks for the wipe.

    That the wipe DID something is read off the GNSS mode falling back to its
    factory rung — a setting this scenario itself walked to the far end of the
    ladder minutes earlier, so a reset can only be a leftward move and cannot
    be another edit press misread. It is the one erased thing the sim can
    observe from outside the firmware's own claim about itself.

    The edit is the claim with teeth. A menu that renders and scrolls but whose
    edits go nowhere passes every other assertion here, so the GNSS row is read
    back off the button task's own `gnss mode ->` line, including the
    direction: the ladder is ordered by projected battery hours, so an edit
    right must not come back with fewer. It is parked at its left end first, so
    the ordering has two samples to compare and does not depend on whatever
    mode the build defaults to.

    The faces are folded in here rather than given a scenario of their own
    because they need exactly this boot and nothing more, and a scenario costs
    an emulator — the same call § 362 made for the HR and phone-link rails.

    What it does NOT prove: that an edit SURVIVES A REBOOT. `CFG1` persistence
    is a flash claim and this scenario never power-cycles the emulator; the
    menu's own writes are best-effort / L4 by design (a flash error warns and
    the edit still applies), so a green run here says nothing about what comes
    back after a brown-out. Nor legibility — seven rows on a 168x144 1-bit
    panel read at 45 cm is a step-4 bench claim, per quality_standards.md.

    **And it proves nothing about bytes leaving flash — read the reported
    `flash cleared` narrowly.** Renode's flash is plain memory behind an
    SVD-derived NVMC model: `READY` answers 1, so the store arms itself at boot
    and the erase path runs to completion, but the `ERASEPAGE` write lands on an
    "unimplemented register" and is swallowed. The firmware therefore reports
    success over an emulator that changed nothing. What this scenario earns is
    the guard, the fan-out, the RAM half, and that the erase path executes and
    reports rather than silently no-opping. That four run slots and a config
    page actually read back 0xFF is a bench item (quality_standards.md step 7)
    — and it is the half that matters for a watch that has left its owner's
    hands.
    """
    # No `require_recording` — the opposite. The idle face only exists because
    # this scenario boots without `sim-autostart`, so confirm that is the build
    # actually running rather than trusting the flag: a scenario that silently
    # got an autostarting binary would page the run view and every assertion
    # below would fail in a way that reads like a menu regression.
    home = sim.wait(
        IDLE_VIEW, 90, "the ui task to compose an idle face ('ui: idle <View>')"
    ).group(1)
    if home != "Home":
        raise SmokeFailure(
            f"the watch booted onto the {home} idle face, not Home — the BTN4 "
            "walk starts from Home and the presses below are counted from it"
        )
    idle_panel = sim.dump("idle-home.ppm", "the idle home face")
    if idle_panel.dark == 0:
        raise SmokeFailure("the idle home face rendered a blank panel")

    press_menu(sim, "$btn5", "BTN5 to open the settings menu", MENU_OPENED)
    menu_panel = sim.dump("menu-open.ppm", "the settings menu")
    if menu_panel.data == idle_panel.data:
        raise SmokeFailure(
            "the panel is byte-identical with the menu open and closed — the "
            "menu opened in the button task but never reached the composer, so "
            "the runner pressed BTN5 and nothing happened on the glass"
        )
    if menu_panel.dark == 0:
        raise SmokeFailure("the settings menu rendered a blank panel")
    passed(
        f"BTN5 opened the settings menu and it reached the panel "
        f"({menu_panel.dark} dark pixels against {idle_panel.dark} on the idle face)"
    )

    # The cursor opens on row 0, so a full lap is one press per remaining row
    # plus one more to wrap back onto the first.
    walk = [MENU_ROWS[0]]
    for _ in range(len(MENU_ROWS)):
        walk.append(press_menu(sim, "$btn3", "BTN3 to step the cursor down").group(1))
    if walk != [*MENU_ROWS, MENU_ROWS[0]]:
        raise SmokeFailure(
            f"BTN3 walked {' -> '.join(walk)}, not "
            f"{' -> '.join([*MENU_ROWS, MENU_ROWS[0]])} — the row order or the "
            "wrap is not what §351 documents, and the order is the part a "
            "runner's thumb learns"
        )
    passed(f"BTN3 walked all {len(MENU_ROWS)} rows in order and wrapped: {' -> '.join(walk)}")

    # BTN2 is the opposite slot; one press from the wrapped-to-first row has to
    # land on the last. A menu whose up and down both stepped the same way would
    # pass the walk above.
    back = press_menu(sim, "$btn2", "BTN2 to step the cursor up").group(1)
    if back != MENU_ROWS[-1]:
        raise SmokeFailure(
            f"BTN2 from {MENU_ROWS[0]} landed on {back}, not {MENU_ROWS[-1]} — "
            "the cursor does not walk back the way it walked forward"
        )
    passed(f"BTN2 stepped the cursor back the other way ({MENU_ROWS[0]} -> {back})")

    # Back onto the GNSS row for the edit. One press down from the last row
    # wraps onto the first, which is GnssMode.
    row = press_menu(sim, "$btn3", "BTN3 to return to the GNSS row").group(1)
    if row != "GnssMode":
        raise SmokeFailure(f"expected to be back on GnssMode, cursor reads {row}")

    # Park the ladder at its left-hand end first (BTN5 = edit left, §351), so
    # the rights below are measured from a KNOWN rung rather than from whatever
    # mode the build happens to default to. Clamping at the end is the expected
    # outcome of the last of these, so a silent press is not a failure here.
    # Stops at the first silent press, which IS the clamp — the build defaults
    # to the leftmost rung, so this is usually one press and out. Pressing the
    # full ladder blindly cost ~2 min of expected silence.
    for _ in range(GNSS_LADDER_RUNGS):
        if (
            press_menu(
                sim,
                "$btn5",
                "BTN5 to edit the GNSS row left",
                GNSS_MODE_SET,
                required=False,
            )
            is None
        ):
            break

    # ...then walk it back up. From the left end at least two rights must move
    # it, which is what makes the ordering assertion below possible at all: a
    # single sample cannot show a direction.
    edits = []
    for _ in range(GNSS_LADDER_RUNGS - 1):
        m = press_menu(sim, "$btn1", "BTN1 to edit the GNSS row right", GNSS_MODE_SET)
        edits.append((m.group(1), int(m.group(2)), int(m.group(3))))
    for (prev_mode, prev_s, prev_h), (mode, interval_s, hours) in itertools.pairwise(edits):
        if hours < prev_h or interval_s < prev_s:
            raise SmokeFailure(
                f"editing right moved the ladder {prev_mode} -> {mode}, but the "
                f"projection fell from {prev_s}s / ~{prev_h}h to {interval_s}s / "
                f"~{hours}h — right is meant to buy battery, so the row is wired "
                "backwards"
            )
    if len({mode for mode, _, _ in edits}) != len(edits):
        raise SmokeFailure(
            f"the rights landed on {[m for m, _, _ in edits]} — the ladder "
            "reported an edit without actually changing rung"
        )
    mode, interval_s, hours = edits[-1]
    passed(
        f"the GNSS row edits both ways and stays ordered: left to the end, then "
        f"{' -> '.join(m for m, _, _ in edits)} on the way back "
        f"(now {interval_s}s fixes, ~{hours}h projected)"
    )

    why = press_menu(sim, "$btn4", "BTN4 to exit the menu", MENU_CLOSED).group(1)
    if why != "btn4":
        raise SmokeFailure(
            f"the menu closed for '{why}' rather than the BTN4 press — something "
            "else (the inactivity timeout, a run starting) got there first, so "
            "this is not an assertion about the exit key"
        )
    closed_panel = sim.dump("menu-closed.ppm", "the idle face after the menu closed")
    if closed_panel.data == menu_panel.data:
        raise SmokeFailure(
            "the panel still shows the menu after BTN4 — it closed in the button "
            "task but the composer never took it down, so the runner is left "
            "looking at a menu they exited"
        )
    passed("BTN4 closed the menu and the idle face came back")

    # --- the three idle faces BTN4 walks (§291, widened to three by §358) ---
    #
    # Folded in here rather than given a scenario of its own: it needs exactly
    # the `--no-autostart` boot the menu above needs and nothing more, and a
    # scenario costs an emulator. Same call §362 made for the HR and phone-link
    # rails inside `smoke`.
    walk = []
    faces = {}
    for _ in range(len(IDLE_FACES)):
        view = press_menu(sim, "$btn4", "BTN4 to walk to the next idle face", IDLE_VIEW).group(1)
        walk.append(view)
        panel = sim.dump(f"idle-{view}.ppm", f"the {view} idle face")
        if panel.dark == 0:
            raise SmokeFailure(f"the {view} idle face rendered a blank panel")
        faces.setdefault(view, panel)
    if walk != [*IDLE_FACES[1:], IDLE_FACES[0]]:
        raise SmokeFailure(
            f"BTN4 walked {' -> '.join(walk)} from {IDLE_FACES[0]}, not "
            f"{' -> '.join([*IDLE_FACES[1:], IDLE_FACES[0]])} — the idle faces "
            "are not the cycle §358 documents"
        )
    passed(f"BTN4 walked the idle faces and wrapped: {IDLE_FACES[0]} -> {' -> '.join(walk)}")

    # Three faces that render identically would pass the walk above while a
    # responder reads the wrong card off the wrist.
    for a, b in itertools.combinations(sorted(faces), 2):
        if faces[a].data == faces[b].data:
            raise SmokeFailure(
                f"the {a} and {b} idle faces are byte-identical — the view "
                "changed in the button task but the composer drew the same card"
            )
    passed(f"the {len(faces)} idle faces are distinct frames")

    # The ICE card's second route, and the one a responder never uses but the
    # runner does: the menu's own MEDICAL ID row (§358) is an action row, so it
    # fires and hands the screen over rather than staying open on a value.
    press_menu(sim, "$btn5", "BTN5 to reopen the settings menu", MENU_OPENED)
    # The cursor opens on row 0, so reaching the row takes exactly its index in
    # presses — one more would wrap past it and back onto GnssMode.
    row = None
    for _ in range(MENU_ROWS.index("Ice")):
        row = press_menu(sim, "$btn3", "BTN3 to step toward the MEDICAL ID row").group(1)
    if row != "Ice":
        raise SmokeFailure(f"expected the cursor on Ice, it reads {row}")
    # Marked before the press so the idle line read below is the one this press
    # produced — an unanchored wait finds the boot-time `ui: idle Home` and
    # reports the face never changed.
    fired = sim.tail.mark()
    why = press_menu(
        sim, "$btn1", "BTN1 to fire the MEDICAL ID row", MENU_CLOSED
    ).group(1)
    if why != "medical id":
        raise SmokeFailure(
            f"firing the MEDICAL ID row closed the menu for '{why}' — the row is "
            "meant to hand the screen to the card, which is the only confirmation "
            "the runner gets that it did anything"
        )
    view = sim.wait(
        IDLE_VIEW,
        MENU_STEP_TIMEOUT,
        "the ui task to compose the ICE card after the MEDICAL ID row fired",
        start=fired,
    ).group(1)
    if view != "Ice":
        raise SmokeFailure(
            f"the MEDICAL ID row closed the menu but the face went to {view}, not "
            "Ice — the row fired and left the runner somewhere else"
        )
    passed("the menu's MEDICAL ID row fires and hands the screen to the ICE card")

    # --- the §378 factory erase, and the guard in front of it ---
    #
    # Last, because it resets the GNSS ladder this scenario spent its middle
    # walking — which is what makes the wipe checkable at all under a sim with
    # no NVMC. See the docstring for what this rung does and does not earn.
    press_menu(sim, "$btn5", "BTN5 to reopen the settings menu", MENU_OPENED)
    row = None
    for _ in range(MENU_ROWS.index("Erase")):
        row = press_menu(sim, "$btn3", "BTN3 to step toward the FACTORY ERASE row").group(1)
    if row != "Erase":
        raise SmokeFailure(f"expected the cursor on Erase, it reads {row}")
    resting_panel = sim.dump("menu-erase-resting.ppm", "the menu on the erase row")

    # One press must NOT wipe. Waiting on the armed line is the assertion: a
    # row wired straight through would emit the confirm line here and this
    # would fail naming it.
    press_menu(sim, "$btn1", "BTN1 to arm the factory erase", MENU_ERASE_ARMED)
    armed_panel = sim.dump("menu-erase-armed.ppm", "the armed factory erase")
    if armed_panel.data == resting_panel.data:
        raise SmokeFailure(
            "the panel is byte-identical armed and un-armed — the guard armed in "
            "the button task and never reached the glass, so the runner's next "
            "press would wipe the watch with nothing on screen having changed"
        )
    passed("BTN1 arms the factory erase instead of firing it, and the panel says so")

    # Step off the row and back. The arm must not survive that: a confirm has
    # to be the very next thing the runner does, or a brush minutes earlier
    # turns a later deliberate press into a wipe.
    press_menu(sim, "$btn3", "BTN3 to step off the armed erase row")
    back = press_menu(sim, "$btn2", "BTN2 to step back onto the erase row").group(1)
    if back != "Erase":
        raise SmokeFailure(f"expected to be back on Erase, cursor reads {back}")
    press_menu(sim, "$btn1", "BTN1 on the re-entered erase row", MENU_ERASE_ARMED)
    passed("stepping off the row cancels the arm — the next press arms again, it does not wipe")

    # Now the wipe. The arm asserted just above may already have LAPSED by the
    # time we get here: that press_menu waits on the armed line, and a
    # block-buffered decoder can surface it past the guard's window — the hazard
    # the module docstring records for the BTN2 stop pair, and the same window,
    # since ERASE_CONFIRM_WINDOW_S is STOP_CONFIRM_WINDOW_S. Gating the
    # confirming press on having SEEN the arm is therefore a race, and it is the
    # one that failed in CI while passing on a faster local decoder.
    #
    # So put the guard back into a known un-armed state, then deliver both
    # presses ungated on a fixed gap and retry the pair if one misses a poll,
    # exactly as `smoke` delivers its stop pair.
    press_menu(sim, "$btn3", "BTN3 off the erase row before the timed pair")
    staged = press_menu(sim, "$btn2", "BTN2 back onto the erase row").group(1)
    if staged != "Erase":
        raise SmokeFailure(f"expected to be back on Erase, cursor reads {staged}")

    flash = None
    for attempt in range(1, STOP_ATTEMPTS + 1):
        announce(f"BTN1 erase pair, attempt {attempt}/{STOP_ATTEMPTS}")
        # Marked inside the loop so the lines read below belong to THIS pair.
        fired = sim.tail.mark()
        sim.monitor().send("runMacro $btn1")
        # Inside the guard's confirm window; see the module docstring for why
        # this gap is not gated on a log line.
        time.sleep(1.5)
        sim.monitor().send("runMacro $btn1")
        try:
            flash = sim.wait(
                MENU_ERASE_DONE,
                MENU_STEP_TIMEOUT,
                "BTN1 to confirm the factory erase",
                start=fired,
            ).group(1)
            break
        except SmokeFailure as exc:
            if attempt == STOP_ATTEMPTS:
                raise SmokeFailure(
                    f"{exc} — {STOP_ATTEMPTS} BTN1 press pairs were injected and "
                    "none produced a confirmed erase"
                ) from exc
            announce("no erase yet — the injected press likely missed a poll")
    sim.wait(
        RECORD_ERASED,
        MENU_STEP_TIMEOUT,
        "the record task to drop the RAM the erase covers",
        start=fired,
    )
    # The claim with teeth. Everything above is a state machine talking to
    # itself; this is the erase reaching a setting the scenario itself moved.
    # The ladder was walked RIGHT to its clamp earlier, so a reset can only be
    # a leftward move and cannot be confused with another edit press.
    mode, interval_s, hours = (
        lambda m: (m.group(1), int(m.group(2)), int(m.group(3)))
    )(
        sim.wait(
            GNSS_MODE_SET,
            MENU_STEP_TIMEOUT,
            "the GNSS mode to fall back to its factory rung",
            start=fired,
        )
    )
    if hours >= edits[-1][2]:
        raise SmokeFailure(
            f"the erase left the GNSS mode at {mode} (~{hours}h) against the "
            f"{edits[-1][0]} (~{edits[-1][2]}h) the ladder was walked to — the "
            "wipe reported success without resetting a setting it owns"
        )
    passed(
        f"the confirming press wipes (flash {flash}) and the watch falls back to "
        f"factory values: GNSS {edits[-1][0]} ~{edits[-1][2]}h -> {mode} "
        f"{interval_s}s ~{hours}h"
    )


def press_lap(sim, what):
    """One BTN5 tap, resolved by the button task's own `button: Lap -> Lap`.

    Returns the log cursor taken BEFORE the press, so the caller can wait for
    the workout edge THIS press produced without matching an earlier one.

    Retried like `press_page` and `press_menu`, and the retry is only safe
    because of the line it waits on. A macro drives the GPIO low for a fixed
    window and the button task samples on a poll, so an injected press can land
    between polls and vanish. The button task logs BEFORE it sends the command,
    so an absent line means the press never became a command at all — nothing
    was skipped and repeating cannot skip twice. Waiting on the workout edge
    instead would confuse a slow edge with a lost press and skip two steps on
    the retry, which is exactly the bug this scenario exists to catch.
    """
    for attempt in range(1, PAGE_PRESS_ATTEMPTS + 1):
        mark = sim.tail.mark()
        sim.monitor().send("runMacro $btn5")
        try:
            sim.wait(
                LAP_PRESS,
                WORKOUT_LAP_TIMEOUT,
                f"the button task to classify {what} as the lap command "
                "('button: Lap -> Lap') — a press that came back as "
                "MarkWaypoint was read as the §357 HOLD tier instead",
                start=mark,
            )
            return mark
        except SmokeFailure:
            if attempt == PAGE_PRESS_ATTEMPTS:
                raise
            announce("no lap line seen — the injected press likely missed a poll")
    raise AssertionError("unreachable")


def workout_transitions(tail):
    """Every step transition the alert engine has reported so far, in order,
    each paired with the virtual timestamp of the line that carried it.

    The whole series rather than the newest match, for the reason `dropout`
    reads its fix stream the same way: the claims are about the SEQUENCE and
    about the times between its entries, and no single line carries either.
    """
    return [
        (t, (m.group(1), int(m.group(2)), int(m.group(3))))
        for t, m in stamped(tail, WORKOUT_STEP)
    ]


def assert_lap_skipped(label, started_at, edge, edge_at):
    """The one claim that separates a §354 skip from a step ending by itself.

    `started_at` is when the step the press displaced began, `edge_at` when the
    edge the press produced landed — both in the FIRMWARE's virtual seconds.
    The steps BTN5 skips in this scenario need ~33 s and ~40 s of that clock to
    settle on their own, so an edge inside `WORKOUT_SKIP_MAX_GAP_S` cannot be
    the auto-advance arriving on schedule. Without this the scenario would pass
    on a firmware whose lap press does nothing at all: wait long enough and the
    step ends regardless.
    """
    gap = edge_at - started_at
    if gap > WORKOUT_SKIP_MAX_GAP_S:
        raise SmokeFailure(
            f"{label} landed {gap:.1f}s of virtual time after the step it was "
            f"meant to cut short began, past the {WORKOUT_SKIP_MAX_GAP_S:.0f}s "
            "a press can account for — a 50-60 m step on this fixture settles "
            "by itself in ~33-40 s, so this is the auto-advance arriving on "
            "schedule and the lap press did nothing. §357 re-tiered BTN5 (tap "
            "laps, hold marks a waypoint), and a mis-tiered tap is invisible to "
            "every host test over the runner"
        )
    passed(
        f"{label} {gap:.1f}s in — {edge}, far short of the ~33-40 s that step "
        f"needed to end by itself, so the advance is the press (§354)"
    )


def scenario_workout(sim):
    """Run a structured workout end to end and prove each edge reaches a task.

    The last major run-view rail without a scenario. Everything about
    `watch_core::workout` up to here is host-tested against the mobile runner's
    own vectors, and the demo workout had been walked BY HAND in the sim — but
    nothing automated had ever driven a step list through the recorder, the
    alert engine and into flash on a booted emulator, so the whole seam between
    the ported state machine and the firmware around it was unguarded.

    Six claims, in the order the run produces them:

      1. the pushed step list ARMS the recorder (`state::WORKOUT`, the same
         channel the ble task's `WKT1` decode publishes on)
      2. the Workout page enters the cycle and renders
      3. the runner auto-advances through the plan IN ORDER, over both end axes
      4. the end-of-step warning fires on the one step long enough to earn it,
         and on no other
      5. a BTN5 lap press skips the active step (§354) and, on the last one,
         completes the workout
      6. the completed trail flushes into the run blob with nothing dropped

    (3) and (4) are the two with the most reach. The plan mixes distance steps
    (60 / 50 / 50 / 60 m) with a duration one (30 s recovery), so a runner that
    settles only one axis stalls partway and reports a SHORT sequence rather
    than a wrong one. And the ending window is gated — `ENDING_MIN_STEP_M` is
    100 m so none of the distance steps qualify, `ENDING_MIN_STEP_S` is 20 s so
    the recovery alone does — which makes "exactly one warning, inside the
    recovery" a claim about the gate itself. A runner that warned on every step
    passes a mere "a warning fired" check and fails this one.

    (5) is the button half, and it is asserted on the FIRMWARE's clock rather
    than on the harness's: see `assert_lap_skipped`.

    **What this does NOT prove.** Nothing here reads a glyph, so `NOT SYNCED`
    and `WORKOUT DONE` are not verified as TEXT — the page's presence in the
    cycle is `Snapshot::pages_mask`'s `workout.is_some()` bit and its content is
    a host-test claim (`core/src/face.rs`). Nor the real `WKT1` transport: the
    sim arms over the channel the ble task publishes on, but the GATT
    characteristic and its chunked reassembly need a SoftDevice, which Renode
    does not run (decisions §314). And not the negative half — every boot in
    this file that starts a run also arms the demo workout, so "the Workout page
    stays OUT of a cycle with no workout" has no session to be asserted in.
    """
    require_recording(sim)

    steps = int(
        sim.wait(
            WORKOUT_ARMED,
            120,
            "the pushed step list to reach the recorder "
            "('record: workout armed (N steps)') — 'record: sim demo workout "
            "queued' is the SEND on state::WORKOUT, this line is the receive, "
            "and only the second one says Recorder::set_workout accepted it",
        ).group(1)
    )
    if steps != len(WORKOUT_PLAN):
        raise SmokeFailure(
            f"the recorder armed {steps} steps, not the {len(WORKOUT_PLAN)} the "
            "sim demo workout queues — `WorkoutRunner::new` truncated or "
            "rejected part of the list, and every sequence assertion below "
            "would then be checking a different workout"
        )
    passed(f"the pushed step list armed the recorder ({steps} steps)")

    # The page, walked to now rather than at the end: it stays where the walk
    # leaves it for the rest of the scenario (BTN5 laps, it does not page), so
    # the second dump after DONE is the same page in a later state and needs no
    # second walk.
    walk = []
    page = None
    presses = 0
    while presses < MAX_PAGE_PRESSES and page != "Workout":
        presses += 1
        page = press_page(sim, "$btn4", f"BTN4 press {presses}")
        walk.append(page)
    if page != "Workout":
        raise SmokeFailure(
            f"the Workout page never appeared in the BTN4 cycle over {presses} "
            f"presses (walked: {' -> '.join(walk)}). The cycle is "
            "`Snapshot::pages_mask`, whose Workout bit is `s.workout.is_some()` "
            "— and the arm above is green, so the runner IS armed and the bit "
            "is reading the wrong field. That failure is silent on the wrist: "
            "an absent page is indistinguishable from a page with no data"
        )
    wait_for_no_alert(sim)
    active = sim.dump("page-Workout-active.ppm", "the Workout page under a live workout")
    assert_rendered(active, "the Workout page")
    passed(
        f"the Workout page is in the BTN4 cycle and renders "
        f"({active.dark} dark pixels, reached in {presses} presses)"
    )

    # The auto-advance. Checked as a growing PREFIX rather than waited out and
    # compared at the end: a runner that reports the wrong step should say so on
    # the step it gets wrong, not after the timeout for a step that will never
    # come.
    deadline = time.monotonic() + WORKOUT_STEP_TIMEOUT * WORKOUT_AUTO_STEPS
    while True:
        sim.alive()
        got = workout_transitions(sim.tail)
        for index, (_, step) in enumerate(got[:WORKOUT_AUTO_STEPS]):
            if step != WORKOUT_PLAN[index]:
                raise SmokeFailure(
                    f"transition {index + 1} reported {step}, not "
                    f"{WORKOUT_PLAN[index]} — the runner is not walking the "
                    "pushed plan. A wrong KIND means the step list decoded into "
                    "the wrong order; wrong rep numbering means the banner tells "
                    "the runner they are on a different rep than they are"
                )
        if len(got) >= WORKOUT_AUTO_STEPS:
            break
        if time.monotonic() >= deadline:
            raise SmokeFailure(
                f"the workout advanced {len(got)} of {WORKOUT_AUTO_STEPS} steps "
                f"unaided ({' -> '.join(k for _, (k, _, _) in got) or 'none'}) "
                "before the deadline. Each step ends on ONE axis — the reps and "
                "the warmup on distance, the recovery on its 30 s — so a stall "
                "at transition 3 is a runner that never settles a duration step "
                "and a stall at transition 1 one that never settles a distance "
                "step"
            )
        time.sleep(0.5)
    passed(
        "the runner auto-advanced through "
        + " -> ".join(
            f"{k}{f' {i}/{n}' if n else ''}"
            for k, i, n in WORKOUT_PLAN[:WORKOUT_AUTO_STEPS]
        )
        + " over both end axes"
    )

    # The end-of-step warning, and the reason `--no-alerts` is on this session:
    # nothing else can take the slot, so the COUNT is the assertion. Exactly one
    # of the plan's steps clears a gate — the 30 s recovery against
    # ENDING_MIN_STEP_S = 20, where every distance step is 50-60 m against
    # ENDING_MIN_STEP_M = 100 — so a warning per step and a warning for none
    # both fail here, where "at least one fired" would let the first through.
    stamps = [t for t, _ in workout_transitions(sim.tail)]
    endings = [t for t, _ in stamped(sim.tail, WORKOUT_ENDING)]
    recovery_at, next_at = stamps[2], stamps[3]
    if len(endings) != 1:
        raise SmokeFailure(
            f"{len(endings)} end-of-step warnings fired across the plan's first "
            f"{WORKOUT_AUTO_STEPS} transitions, not 1 — only the 30 s recovery "
            "clears a warning gate (ENDING_MIN_STEP_S = 20 s; the 50-60 m "
            "distance steps are all under ENDING_MIN_STEP_M = 100 m). More means "
            "the gate is not being applied; none means the window never opens "
            "and the runner gets no notice before a step changes under them"
        )
    if not recovery_at < endings[0] <= next_at:
        raise SmokeFailure(
            f"the end-of-step warning landed at t={endings[0]:.1f}s, outside the "
            f"recovery step (t={recovery_at:.1f}s to t={next_at:.1f}s) — it is "
            "warning about a step other than the one that earned a warning"
        )
    passed(
        f"exactly one end-of-step warning fired, {endings[0] - recovery_at:.0f}s "
        f"into the 30 s recovery — the only step in the plan that clears a gate"
    )

    # The §354 skip. Two presses: one to leave the step the auto-advance just
    # entered, one to run off the end of the plan.
    before = workout_transitions(sim.tail)
    if len(before) != WORKOUT_AUTO_STEPS:
        raise SmokeFailure(
            f"{len(before)} transitions had already fired when the lap press was "
            f"about to be injected, not {WORKOUT_AUTO_STEPS} — the auto-advance "
            "settled the step before the harness could reach it, so the press "
            "below would be skipping a step nobody chose. This is a host-speed "
            "report, not a firmware verdict"
        )
    mark = press_lap(sim, "the BTN5 tap on the last rep")
    m = sim.wait(
        WORKOUT_STEP,
        WORKOUT_EDGE_TIMEOUT,
        "the lap press to skip the active step ('record: alert WorkoutStep …')",
        start=mark,
    )
    skipped_to = (m.group(1), int(m.group(2)), int(m.group(3)))
    if skipped_to != WORKOUT_PLAN[WORKOUT_AUTO_STEPS]:
        raise SmokeFailure(
            f"the lap press advanced to {skipped_to}, not "
            f"{WORKOUT_PLAN[WORKOUT_AUTO_STEPS]} — the skip left the plan"
        )
    after = workout_transitions(sim.tail)
    assert_lap_skipped(
        "a BTN5 lap press skipped the active step",
        before[-1][0],
        f"landing on {skipped_to[0]}",
        after[WORKOUT_AUTO_STEPS][0],
    )

    mark = press_lap(sim, "the BTN5 tap on the final step")
    sim.wait(
        WORKOUT_DONE,
        WORKOUT_EDGE_TIMEOUT,
        "skipping the final step to complete the workout "
        "('record: alert WorkoutDone')",
        start=mark,
    )
    done_stamps = [t for t, _ in stamped(sim.tail, WORKOUT_DONE)]
    assert_lap_skipped(
        "skipping the final step completed the workout",
        after[WORKOUT_AUTO_STEPS][0],
        "raising DONE",
        done_stamps[0],
    )

    # A sixth transition would mean the runner walked off the end of its own
    # step list and kept going, which the page would render as a step that does
    # not exist.
    got = workout_transitions(sim.tail)
    if len(got) != len(WORKOUT_PLAN):
        raise SmokeFailure(
            f"{len(got)} transitions fired for a {len(WORKOUT_PLAN)}-step plan "
            f"({' -> '.join(k for _, (k, _, _) in got)}) — a completed runner "
            "must raise no further step edge"
        )
    passed(
        f"the runner raised exactly {len(got)} transitions for a "
        f"{len(WORKOUT_PLAN)}-step plan"
    )

    wait_for_no_alert(sim)
    done = sim.dump("page-Workout-done.ppm", "the Workout page after the workout completed")
    assert_rendered(done, "the Workout page's completed state")
    if done.data == active.data:
        raise SmokeFailure(
            "the Workout page's live and completed dumps are byte-identical — "
            "DumpFrame did not write a fresh frame for one of them (the elapsed "
            "clock alone changes pixels between two frames a minute apart), so "
            "neither render assertion above proves anything"
        )
    passed(
        f"the page still renders after DONE ({done.dark} dark pixels) — this "
        "says a frame was drawn, NOT that it reads WORKOUT DONE; no assertion "
        "here reads a glyph"
    )

    # The v4 persistence half. `smoke` already asserts this line exists, but it
    # stops ~20 m into the run with the workout still on its first step, so the
    # trail it flushes is one in-progress step. This one flushes a COMPLETE
    # five-step trail plus the summary, which is the shape that can actually run
    # the stored-step budget out.
    stored = None
    for attempt in range(1, STOP_ATTEMPTS + 1):
        announce(f"BTN2 stop pair, attempt {attempt}/{STOP_ATTEMPTS}")
        sim.monitor().send("runMacro $btn2")
        # Inside the firmware's 4 s stop-confirm window, for the same reason
        # `smoke`'s pair is — see the module docstring.
        time.sleep(1.5)
        sim.monitor().send("runMacro $btn2")
        try:
            stored = sim.wait(
                WORKOUT_STORED,
                25,
                "the stopped run to flush its workout trail "
                "('record: run N workout results stored (M planned steps)')",
            )
            break
        except SmokeFailure as exc:
            if attempt == STOP_ATTEMPTS:
                raise SmokeFailure(
                    f"{exc} — {STOP_ATTEMPTS} BTN2 press pairs were injected and "
                    "none produced a workout flush"
                ) from exc
            announce("no flush yet — the injected press likely missed a poll")

    planned = int(stored.group(2))
    if planned != len(WORKOUT_PLAN):
        raise SmokeFailure(
            f"the flushed summary claims {planned} planned steps, not "
            f"{len(WORKOUT_PLAN)} — the phone reconciles the step records "
            "against this count, so a wrong one mis-attributes the trail"
        )
    loss = sim.tail.search(WORKOUT_STORE_LOSS)
    if loss is not None:
        raise SmokeFailure(
            f"part of the completed trail was lost on the way to flash: "
            f"{loss.group(0)} — the write is best-effort by design (the run "
            "still commits), so this never fails the run and is invisible until "
            "the phone gets a trail with a hole in it"
        )
    passed(
        f"the completed {planned}-step trail flushed into run {stored.group(1)}'s "
        "blob with no step or summary dropped"
    )

    panics = [ln for ln in sim.tail.text().splitlines() if "panicked" in ln.lower()]
    if panics:
        raise SmokeFailure("the firmware panicked during the run: " + panics[0].strip())
    passed("no firmware panic across the workout")


def scenario_storm(sim):
    """Drive a front past the barometer and prove the watch names it.

    The § 376 rail end to end: the BMP581 model's SEA-LEVEL reference is ramped
    down while its altitude stays put, which is a weather change and not a
    movement one — the station pressure falls, the GPS altitude the firmware
    reduces against does not, and the reduced pressure therefore falls with it.
    That is the signal the whole module exists to isolate.

    Four claims, in order, and each grounded in the baro task's own line rather
    than in a panel:

    1. **The tracker refuses before it can measure.** A window is three hours on
       hardware and 60 s under `--storm`; until a third of it is banked the
       answer is `Building`, not a tendency extrapolated from a minute of air.
    2. **A quiet atmosphere is quiet.** Before the ramp starts, the tendency
       reads `Steady` with a residual under `STORM_QUIET_HPA`. This is the
       assertion a false positive would fail, and it is worth more than the
       storm one: a watch that cries wolf on a calm day is worse than one with
       no storm page at all.
    3. **A scripted fall reaches `Storm`,** with a delta past the armed
       threshold and the right sign.
    4. **The banner fires exactly once,** which is a claim about the arm's
       once-per-front hysteresis and only holds because `--no-alerts` leaves it
       alone in the single banner slot.

    Then the page: it enters the BTN4 cycle (its presence bit is "a reduced
    pressure can be stated") and renders non-blank.

    **What this scenario deliberately does NOT prove.** The separation of a
    climb from a front — the module's entire reason for existing — cannot be
    scripted here: the firmware's altitude reference comes from the NMEA
    fixture, which the harness cannot ramp independently of the barometer, so a
    "climb" in-sim is a baro ramp against a flat GPS altitude, which IS weather
    as far as any correct implementation can tell. That separation is
    host-tested instead (`core/src/storm.rs`:
    `a_climb_at_constant_weather_is_not_a_storm` and
    `a_falling_front_while_climbing_still_reads_the_front`), and this scenario
    guards the rail those tests cannot reach: sensor to reduction to trend to
    alert slot to page.
    """
    sim.wait(
        re.compile(r"baro: BMP581 streaming"),
        120,
        "the baro task to reach the BMP581 model ('baro: BMP581 streaming') — a "
        "parked task publishes no tendency at all, so every assertion below "
        "would be waiting on a task that is not running",
    )
    passed("the baro task is streaming from the BMP581 model")

    sim.wait(
        re.compile(r"record: sim storm alert armed at"),
        60,
        "the record task to arm the storm banner through the same setter a "
        "phone push feeds ('record: sim storm alert armed at <N> hPa')",
    )
    passed("the storm banner is armed")

    # (1) The refusal. It has to be observed BEFORE the window fills, so it is
    # waited on rather than searched for after the fact.
    sim.wait(
        STORM_UNMEASURED,
        60,
        "the tracker to report an unmeasured tendency ('baro: storm Building') "
        "before a third of its window is banked — a verdict this early would "
        "mean the minimum-span gate is not gating",
    )
    passed("the tracker withholds a tendency until its window is deep enough")

    require_recording(sim)

    # The precondition every slot assertion below rests on, checked as early as
    # it can be checked reliably so a regression fails HERE with a name instead
    # of downstream as a timing lottery: this session boots with every
    # non-storm alert arm unarmed (`--no-alerts --no-course --no-workout`). The
    # demo workout is the one that leaked before (CI run 30709260463) — its
    # step banners displaced the storm banner, each displacement re-queued it
    # (§376, no later reminder exists), and the slot went banner-to-banner, so
    # "one front, one banner" and the TTL clear both depended on phase
    # alignment. The queued line logs at boot, well before the first accepted
    # fix the wait above decoded past, so by now it is either present or never
    # coming.
    if sim.tail.search(re.compile(r"record: sim demo workout queued")):
        raise SmokeFailure(
            "the demo workout is armed in the storm session — its step banners "
            "share the single alert slot with the storm banner, which re-queues "
            "on every displacement, so the once-per-front count and the "
            "TTL-clear wait below stop meaning anything. The storm session "
            "boots with --no-workout (`sim-workout` off); if the workout is "
            "back, the feature gate in app/src/tasks/record.rs regressed"
        )
    passed("the storm session booted with the demo workout unarmed")

    # (2) The quiet atmosphere. Wait for the first MEASURED line, then check it
    # is a calm one — the scripted pressure carries no noise and the fixture's
    # altitude is constant, so anything past the residual is the reduction
    # picking up something it should not.
    quiet = sim.wait(
        STORM_LINE,
        STORM_TIMEOUT,
        "the tracker's first measured tendency ('baro: storm <Trend> delta=...') "
        "on a quiet atmosphere",
    )
    quiet_delta = float(quiet.group(2))
    if quiet.group(1) != "Steady" or abs(quiet_delta) > STORM_QUIET_HPA:
        raise SmokeFailure(
            f"a still atmosphere read {quiet.group(1)} at {quiet_delta:+.2f} hPa "
            f"over {quiet.group(4)}s, past the {STORM_QUIET_HPA} hPa a scripted "
            "constant pressure can produce. Something is moving the reduction "
            "that is not weather — which is the false alarm this feature must "
            "not have"
        )
    passed(
        f"a still atmosphere reads Steady at {quiet_delta:+.2f} hPa "
        f"(QNH {float(quiet.group(3)):.0f} hPa)"
    )

    # (3) The front. The altitude source is untouched, so nothing about the
    # runner changes — only the air.
    mark = sim.tail.mark()
    sim.monitor().send(f"sysbus.twi1.bmp581 StartSeaLevelTrend -{STORM_FALL_PA_PER_S}")
    announce(f"sea-level reference falling {STORM_FALL_PA_PER_S} Pa/s (the front)")

    stormy = sim.wait(
        STORM_RAISED,
        STORM_TIMEOUT,
        f"the tendency to reach Storm under a {STORM_FALL_PA_PER_S} Pa/s fall "
        "('baro: storm Storm delta=...') — the reduction, its window and the "
        "classifier all have to be right for this line to exist",
        start=mark,
    )
    delta = float(stormy.group(1))
    if delta > -STORM_FALL_HPA:
        raise SmokeFailure(
            f"the trend was classified Storm at {delta:+.2f} hPa, which is "
            f"inside the {STORM_FALL_HPA} hPa threshold it was armed at — the "
            "classifier and the threshold disagree"
        )
    passed(
        f"the front reads Storm at {delta:+.2f} hPa over {stormy.group(3)}s "
        f"(QNH now {float(stormy.group(2)):.0f} hPa)"
    )

    # (4) One front, one banner. The arm disarms itself on firing and re-arms
    # only on a MEASURED recovery, and nothing here recovers.
    sim.wait(
        re.compile(r"record: alert Storm"),
        STORM_TIMEOUT,
        "the storm banner to take the alert slot ('record: alert Storm')",
        start=mark,
    )
    banners = [ln for ln in sim.tail.text().splitlines() if "record: alert Storm" in ln]
    if len(banners) != 1:
        raise SmokeFailure(
            f"the storm banner fired {len(banners)} times for one front. It is "
            "raised once per front and re-arms only on a MEASURED recovery, so "
            "more than one here means either the hysteresis or the re-arm "
            "condition is wrong — and a banner that repeats is a banner a "
            "runner stops reading"
        )
    passed("one front raised exactly one banner")

    # The page. Its presence bit is "a reduced pressure can be stated", which
    # every step above has already proved the watch had.
    wait_for_no_alert(sim)
    walk = []
    presses = 0
    frame = None
    while presses < MAX_PAGE_PRESSES and frame is None:
        presses += 1
        page = press_page(sim, "$btn4", f"BTN4 press {presses}")
        walk.append(page)
        if page == "Storm":
            wait_for_no_alert(sim)
            frame = sim.dump("page-Storm.ppm", "the Storm page's panel frame")
            assert_rendered(frame, "the Storm page")
    if frame is None:
        raise SmokeFailure(
            f"the Storm page never appeared in the BTN4 cycle over {presses} "
            f"presses (walked: {' -> '.join(walk)}). Its data-presence bit is a "
            "statable reduced pressure, which the measured tendencies above "
            "prove the watch had — so a page missing HERE is a data-presence "
            "bug and not an unarmed fixture"
        )
    passed(
        f"the Storm page is in the cycle and renders ({frame.dark} dark pixels, "
        f"{presses} presses: {' -> '.join(walk)})"
    )

    panics = [ln for ln in sim.tail.text().splitlines() if "panicked" in ln.lower()]
    if panics:
        raise SmokeFailure("the firmware panicked during the run: " + panics[0].strip())
    passed("no firmware panic across the front")


SCENARIOS = {
    "smoke": scenario_smoke,
    "alerts": scenario_alerts,
    "pages": scenario_pages,
    "terrain": scenario_terrain,
    "dropout": scenario_dropout,
    "screens": scenario_screens,
    "idle": scenario_idle,
    "workout": scenario_workout,
    "storm": scenario_storm,
}


def selected_scenarios(choice):
    return list(SCENARIO_ORDER) if choice == "all" else [choice]


def plan_sessions(selected, fixture_override=None):
    """Group the selected scenarios into booted sessions — one each.

    `alerts` and `pages` used to share a boot on the grounds that "both need a
    live recording and neither disturbs the other". The second half was wrong.
    `pages` refuses to dump under a banner (a dump taken under one is a dump OF
    the banner), so it waits for `record: alert cleared` — and the engine only
    emits that when a banner expires with nothing behind it. Past roughly 100 s
    the sim's shortened cadences overlap: drink at 30 s, eat at 45 s, and since
    § 354 a WorkoutStep alert on every rep boundary, each raised inside the
    previous one's 8 s TTL. The engine then goes banner-to-banner and `cleared`
    never fires, so `alerts` — which runs ~100 s — was handing `pages` a boot
    with no quiet window left in it. Sharing did not just cost time, it consumed
    the exact resource the other scenario needed.

    So each scenario now gets its own boot, which is also how CI has always run
    them (one step per scenario, one process each). `--scenario all` and the CI
    job finally agree about what is being executed.

    `smoke` and `workout` additionally have to be alone — each stops the run the
    others need in progress — `terrain` and `dropout` are each on a different
    fixture and a boot has exactly one, and `screens`, `idle` and `workout` each
    need their own launcher flags (`SCENARIO_LAUNCHER_ARGS`), which are a
    property of the BUILD a session boots and so cannot be shared either.

    Each session carries its scenario's own fixture. An explicit `--fixture`
    overrides every one of them, which is how a manual session points an
    existing scenario at new terrain.
    """
    return [
        (name, [name], fixture_override or SCENARIO_FIXTURES[name])
        for name in SCENARIO_ORDER
        if name in selected
    ]


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
    plan = plan_sessions(selected_scenarios(args.scenario), args.fixture)
    for index, (label, names, fixture) in enumerate(plan):
        print(
            f"\n=== session {label} ({', '.join(names)}) on {fixture} ===", flush=True
        )
        try:
            with sim_session(
                args,
                label,
                deadline,
                args.phone_port + index,
                fixture,
                launcher_args=SCENARIO_LAUNCHER_ARGS.get(names[0], ()),
            ) as sim:
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
    parser.add_argument(
        "--fixture",
        default=None,
        help="override the NMEA fixture for every selected scenario; by "
        "default each runs on the one it was written against "
        f"({', '.join(f'{k}={v}' for k, v in SCENARIO_FIXTURES.items())})",
    )
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
        # Derived from SCENARIO_ORDER rather than restated: the restated list
        # had already drifted out of step with the scenarios that exist, which
        # is the same failure mode as a CI job that never learns about one.
        choices=(*SCENARIO_ORDER, "all"),
        default="all",
        help="which scenario to run; 'all' boots each of "
        f"{', '.join(SCENARIO_ORDER)} in that order, one emulator each",
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
