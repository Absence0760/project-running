# Navigation map — every state, page, and button edge

The complete navigation graph of the tier-1 watch firmware: which surfaces
exist, every button edge between them, and the computed press-cost of getting
anywhere. Sources of truth: `watch_core::button` (press grammar),
`watch_core::page` (cycle order, §286), `watch_core::page_grid` (the grid
modal, §288/§289/§333), `watch_core::record` (run states), `watch_core::face`
(what each surface renders). Every edge below is host-tested; the flows are
sim-verified (see `apps/custom_watch/local_testing.md` for the macros).

## Mode-level graph

```mermaid
stateDiagram-v2
    direction LR
    Idle: Idle face (home)
    Idle: clock hero + HR / ALT
    Idle: GPS glance + GNSS mode
    Diag: Diagnostics face
    Diag: LAT / LON / SPD
    Diag: seconds clock / vert
    Run: Run view
    Run: 33 pages (filtered mask)
    Grid: Page grid (modal)
    Grid: button legend + cursor page name
    Grid: one screenful of enabled pages + cursor

    [*] --> Idle
    Idle --> Idle: BTN3 tap — GNSS mode cycle
    Idle --> Idle: BTN3 hold — QNH re-zero
    Idle --> Diag: BTN4 — diagnostics view (§291)
    Diag --> Idle: BTN4 — back to home
    Diag --> Run: BTN1 — start run
    Idle --> Run: BTN1 — start run
    Run --> Run: BTN1 — pause / resume (REC / PAU / AUTO tag)
    Run --> Run: BTN2 — arm stop ("STOP? BTN2" banner, 4 s)
    Run --> Run: BTN2 x2 — stop (FIN)
    Run --> Run: BTN4 — lap (REC / PAU), page prev (FIN)
    Run --> Run: BTN3 tap / long — page next / prev
    Run --> Run: BTN3 held 0.5 s — "GRID? HOLD" banner while held
    Run --> Grid: BTN3 hold (1.5 s)
    Grid --> Grid: BTN3 tap / hold — cursor +1 / +4
    Grid --> Grid: BTN1 tap / hold — cursor -1 / -4
    Grid --> Run: BTN4 — jump to cursor
    Grid --> Run: 3 s inactivity — auto-jump to cursor
    Grid --> Run: BTN2 — cancel (swallowed)
    Run --> Idle: BTN1 from FIN — dismiss home
```

Run sub-states (the tag top-right of every run page): `REC` blinking while
recording (steady through the min-move sampling artifact on slow climbs),
`AUTO` steady during a speed-derived auto-pause (resumes itself), `PAU`
steady only for a manual pause (owes a BTN1 press), `FIN` once stopped
(decisions §287). `BTN1` from `FIN` returns home and the next run opens on
the Dashboard (§289) — before §289, `Finished` was a dead end that held the
run view until reboot. In `FIN` the dead lap key becomes a tap page-back
(§290): the post-run review pages both ways on taps, BTN3 forward and BTN4
backward, with the long-press back still available everywhere. Dismissing
also resets the idle face to the home view, wherever a pre-run BTN4 toggle
left it (§291).

## The page cycle (§286 order, §284 filter)

BTN3 walks this ring — forward on tap, backward on long-press — filtered to
`pages_mask` (data-present ∩ curated, Dashboard always enabled). Clusters
are ordered by mid-run glance frequency; `GUID` (the scripted coach run) closes
the live cluster as the virtual partner's sibling, and `BACK` (Back-to-start)
sits last so the safety page is exactly one long-press from home. The curation
half of the mask reaches only the first 32 pages: the `SET1` wire field is 32
bits, so `BACK` — discriminant 32 — is the one page the phone cannot curate out,
and `mask_from_wire` leaves it *enabled* rather than hiding it invisibly on every
push (§333). Data presence still gates it.

```mermaid
flowchart LR
    subgraph live [live run]
        DASH --> DIST --> PACE --> LAP --> ZONE --> SPLT --> PACR --> GUID
    end
    subgraph course [course / race ops]
        NAV --> TURN --> CUT --> ROAD --> FUEL
    end
    subgraph effort [effort analysis]
        ELEV --> PRED --> LOAD --> BAND
    end
    subgraph synced [synced training]
        GEAR --> TPCE --> FITN --> REDY --> GOAL --> RDAY --> PLAN --> ADPT
    end
    subgraph summaries [synced summaries]
        RCAP --> STRK --> STAT --> PR --> SMPL --> RELV --> AEFF
    end
    GUID --> NAV
    FUEL --> ELEV
    BAND --> GEAR
    ADPT --> RCAP
    AEFF --> BACK
    BACK --> DASH
```

The page grid (hold BTN3) shows this same ring as a 4-column map — codes in
cycle order, cursor box on the current page — and moves over it with
`±1` (taps) and `±4` (holds). Above the map sit two chrome rows: row 0 is the
**button legend** (`B2 EXIT` … `B4 GO`) and row 1 the **cursor page's full
name** (`Page::name`, longest `ELEVATION PROFILE` at 17 of 21 cells). The body
therefore seats `GRID_CAPACITY` = 4 × 7 = 28 cells against a 33-page ring, so it
is a **window** that scrolls in whole rows to keep the cursor's row on screen
rather than truncating the tail (§333) — scroll depth 2 at the full mask. Under
the everyday filtered mask (~12 pages, 3 rows) the whole enabled set fits and
nothing scrolls.

The chrome is what makes the modal honest about itself. 33 codes need
`ceil(33/4)` = 9 rows and the panel has exactly 9 (144 px / 16 px), so there was
never a spare row — every chrome row is bought from body capacity, which only
§333's window makes affordable (before it the body was a hard 32-cell `const`
assert). Row 0 names BTN2 and BTN4 and deliberately **not** BTN1/BTN3: a BTN1 or
BTN3 press moves the visible cursor and commits nothing, so it is discovered for
free, whereas BTN2 — which arms the stop everywhere else and cancels in here —
is a *safety* remap the closing grid cannot reveal (§337).

## Press cost — computed, from the Dashboard, full 33-page mask

Actions counted: each tap, long-press, or hold is one action; the grid's
open-hold is one; the auto-select close is free (BTN4 costs one to jump
immediately). `linear` = tap-forward / long-back only. The grid rows are
**additive**: the bidirectional walk does not go away when the grid arrives, so
a page costs the cheaper of the two routes — which is why no grid row can be
worse than the linear row, and why the grid's own worst *cell* is not the worst
*page*.

| Mechanism | Worst page | Average |
|---|---|---|
| Linear walk only (pre-§288) | 16 | 8.2 |
| + grid, forward-only movement (§288 as first built) | 9 | 4.8 |
| + grid, symmetric ±1/±4 (§289, shipped) | **6** | **3.8** |

Every figure is **computed from the cycle and cursor rules, not hand-measured**:
a breadth-first search over the cursor's move set on the enabled cycle
(`{+1, +4}` forward-only, `{±1, ±4}` symmetric, `GRID_COLS` the row stride),
each page then taking `min(walk, 1 + grid moves)` with `walk = min(k, n-k)`, and
the average over all `n` pages with the current page at zero. The model is
validated by reproducing the pre-page-33 table exactly at `n = 32` — 16 / 8.0,
9 / 4.7188, 6 / 3.7188 — so the table above re-derives the original measurement
at the new page count rather than replacing it with a fresh estimate. Both grid
worsts survive page 33 unchanged; the averages move 4.7188 → 4.8182 and
3.7188 → 3.7576. The linear worst stays 16 because the page 17 steps forward is
16 long-presses back.

**§333's row-scrolling window does not enter this table.** `window_origin_row`
decides which cells are on screen; it never changes what a cursor move does, so
an off-window cell costs exactly what an on-window one costs. Nor does the wider
`u64` mask. What *had* looked like a stale grid row was a modelling gap: treat
the grid as *replacing* the walk rather than joining it and the forward-only row
comes out at worst 11, because the runner is denied the single long-press that
reaches the tail. The walk was the missing term.

Under a typical filtered mask (~12 pages), same model: worst 4, average ~2.2
(26/12). The navigation-graph analysis is what motivated §289's symmetric
movement: with forward-only cursor moves, the cells just *behind* the cursor
were the most expensive on the whole grid (near-full lap), which the `±` grammar
removes.

## Invariants (each pinned by a host test)

- **The grid modal swallows every button.** No press inside it can pause,
  stop-arm, or lap the recording; BTN2 cancels, BTN4 confirms, BTN1/BTN3
  move the cursor. The recorder is unreachable from the modal.
- **The grid states its own button map** (§337). Row 0 carries `B2 EXIT` and
  `B4 GO` — the two presses that leave the modal — so BTN2's loss of the stop is
  read, not discovered; the run view's `STOP? BTN2` banner picks the chain up on
  the other side. The legend is static, so it can never dirty a panel line.
- **No jump commits off a code alone** (§337). Row 1 spells out the cursor
  page's full name, because four glyphs cannot separate 33 pages: `LOAD`/`ROAD`
  and `PACE`/`PACR` are one Levenshtein edit apart and `REDY`/`RDAY` and
  `PACR`/`RCAP` are transpositions (computed over all 528 code pairs; 24 more sit
  at distance 2). Both the 3 s auto-select and BTN4 therefore commit on
  something the runner has read.
- **No cell can land on the chrome rows** — the cursor box is drawn from
  `GRID_TOP_ROW`, and `window_origin_row` derives from `GRID_BODY_ROWS`, so
  spending a row on chrome shortens the window and never displaces the cursor.
- **§286's safety contract stands**: Back-to-start is one long-press from
  the Dashboard, grid or no grid.
- **Dashboard is always enabled** — no mask can empty the cycle or the grid.
- **The page-position thumb partitions the top edge.** `statusbar::page_thumb`
  gives the active page the half-open segment
  `[active * 168 / total, (active + 1) * 168 / total)`, so the enabled pages own
  every track column between them exactly once: the Dashboard's thumb is flush
  left and the ring's last page flush right at *every* page count, which is the
  glanceable "the next tap wraps". Deriving the width from a separately
  truncated `168 / total` stranded the remainder columns — at 33 pages that was
  55, 111 and 167, so the last page fell a pixel short of the edge while every
  count dividing 168 (12, 3, 2) tiled correctly and hid it.
- **Auto-select, not auto-cancel**: an abandoned grid jumps to its cursor
  (the one-handed flow); the worst outcome is landing on a page you were
  looking at.
- **Alert banners defer while the grid is open** (their TTL outlives it and
  fuel reminders latch into the persistent row-1 marker); the armed-stop
  banner outranks alerts but yields to the grid, where BTN2 means cancel.
- **Idle gestures are duration-stable**: a BTN3 hold of any length while
  idle is the QNH re-zero — duration never changes an idle gesture
  mid-press. Which is also why the idle face shows no hold prompt: there is
  no second tier there to warn about, so naming one would be a lie.
- **A timed press tier announces itself before it fires.** Once a run-view
  BTN3 hold passes 0.5 s the hero band carries the inverse-video
  `GRID? HOLD` banner for as long as the button is down, so the runner can
  read where they are in the gesture and choose — release for the page back
  they have already earned, or keep holding for the grid — instead of
  learning the answer only once the modal has taken pause off BTN1 and stop
  off BTN2 (§334). The prompt is driven entirely by the hold's own
  escalation timer: it costs two `Watch` sends per hold that reaches the
  tier, nothing at all for a tap, and it carries no TTL, so it never puts a
  timed refresh into the screen task. It outranks an alert banner (whose
  TTL outlives the hold) and yields to the armed-stop banner and to the
  grid. On Distance / Pace the three-row numeral hero stands down under it,
  the same way it does under the armed stop.
- **The home face always tells the time** — the 32x48 clock hero
  extrapolates `HH:MM` from the last fix's wall clock plus uptime, and shows
  an honest `--:--` before any fix. Local time once a settings push has
  carried the phone's auto-sourced timezone offset (§293), UTC until then —
  the row-7 label (`UTC` / `LOCAL`) derives from the same input as the hero,
  so it always says which. The seconds clock and the GPS-less-bench vert row
  live on the diagnostics view (§291), deliberately unshifted: raw receiver
  UTC is a feature on the bench.
- **The home clock is minute-resolution** so an idle watch owes the panel
  zero per-second redraws; `draw_bignum_band` compare-writes whole lines, so
  a resting clock flushes zero lines (pinned by a `sharp_mip` test).

## Known gaps (deliberate, tier-1)

- The grid's 3 s auto-select still commits the cursor with no countdown on
  screen — the one timed wait left without pre-fire feedback. The hold
  prompt's mechanism does not reach it: the prompt rides a timer the press
  already owns, whereas a countdown inside the grid would need a per-second
  wake for as long as the modal is open, which §328 rules out.

- The timezone offset is static between pushes: a DST transition or a border
  crossing shifts the home clock only after the phone's next settings push
  (§293) — the watch has no zoneinfo of its own.
- `FIN` retains the last run's stats until dismissed — there is no summary
  page beyond the frozen dashboard.
- The home face's battery icon is a rest-voltage estimate off the SAADC's
  internal VDD channel (§294), not a fuel gauge: a loaded cell sags below the
  curve anchors, and it yields the title row's mid-band to the post-press
  BTN3 hint and the re-zero banner. The numeric `BAT n%` is diagnostics-only.
  A rail the plausibility band can't read as a 1S LiPo — the USB-powered DK
  at ~3.0 V — shows nothing at all rather than a confident 0 %.

## Driving it in the sim

`pnpm watch:sim:gui:idle` boots to the home face (no auto-started run). Via
`bin/watch-monitor.sh`: `runMacro $btn1` start / pause / dismiss-home,
`$btn2` twice stop (watch the `STOP? BTN2` banner), `$btn3` page, `$btn3l`
page back (0.8 s — long enough to flash the `GRID? HOLD` banner before it
resolves), `$btn3h` page grid (1.7 s — the banner stands for a second, then
the grid replaces it), then `$btn3`/`$btn3l`/`$btn1` to move the cursor and
`$btn4` to jump. Once stopped (`FIN`), `$btn4` pages back. While
idle, `$btn4` toggles the home face against the diagnostics face.
