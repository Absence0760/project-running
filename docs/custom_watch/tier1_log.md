# Tier-1 development log — custom_watch

The dated milestone record of the tier-1 bench-prototype firmware effort. Tier 1's stated deliverable is "knowledge + a credible technical story for ODM conversations" ([roadmap.md § Tier 1](roadmap.md#tier-1--bench-prototype-active-owner-personal)); this log is that story in writing — what was built, when, and where the evidence lives — so the knowledge doesn't stay in one person's head. One entry per milestone, newest last. Current per-step status lives in [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md); this file is the history, not the status.

**Photos / video:** every entry gains a photo or short clip slot once parts arrive (dev kit, breakouts, bench setup, first wearable jog). Everything to date is simulator work, so the visual record so far is Renode captures: since [§ 360](../architecture/decisions.md) `bin/watch-shots.sh` walks every screen the sim can arm and writes one PNG each plus an HTML contact sheet, which is the record to reach for; `bin/watch-sim.sh --gui` shows the live emulated panel for a one-off look.

## 2026-05-28 — Workspace scaffold (step 2)

Cargo workspace landed at [`apps/custom_watch/`](../../apps/custom_watch/README.md): Embassy executor + blink stub on the nRF52840 DK target, `no_std` driver-crate stubs (`sharp_mip`, `ublox_nmea`, `max86177`), board crate with DK pin assignments, probe-rs runner config, VS Code debug wiring. Same day as the planning sweep that locked the stack ([decisions.md § 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance), § 81–§ 92) and this roadmap. Deps bumped to Embassy 0.10 + lockfile committed 2026-05-29. No parts ordered.

## 2026-07-08 — Renode simulator bring-up

`bin/watch-sim.sh` boots the exact release ELF the flash script would program, on Renode's emulated nRF52840 DK — no dev kit needed. defmt logs drain via a custom RTT poller + host-side `defmt-print`; a canned NMEA fixture feeds the emulated UART at a realistic 1 Hz fix rate; the Sharp MIP panel is emulated at the wire-protocol level (`sim/SharpMipDisplay.cs`, `--gui` opens the live screen); and the phone-link frames bridge over TCP to a dev-gated Sim Watch screen in the mobile app. [decisions.md § 208](../architecture/decisions.md#208-firmware-simulation-runs-the-unmodified-elf-on-renode-with-a-custom-defmt-rtt-drain) + § 209. This unblocked every subsequent milestone pre-parts.

## 2026-07-08 — GNSS bring-up (step 3), sim-verified

`ublox_nmea` streaming RMC/GGA parser (checksummed, 10 host tests) + the `gps` task on UARTE0 publishing merged fixes through `watch_core::fix`. Fixes flow end-to-end from the sim's `bench_jog.nmea` fixture. Bench verification pending parts.

## 2026-07-08 — Display bring-up (step 4), sim-verified

`sharp_mip` driver (framebuffer, dirty-line tracking, generated 8x16 font, 16x16 icon table, Sharp line-update wire protocol; 13 host tests) on SPIM3, plus the host-tested `watch_core::face` layouts: an idle status face and a paged run dashboard (2x elapsed-time hero, per-metric gutter icons, BTN3-cycled Dashboard / Distance-glance / Pace-glance pages). Icons are SVG-authored and rasterised to a committed 1-bit table by `scripts/gen_icons.py`. Three ~1 Hz animations (REC blink, heart pulse, GPS search arcs) ride the render tick as pure functions of uptime. Bench verification pending parts.

## 2026-07-08 — Optical HR driver + peak detector (step 5), sim-verified wiring

`max86177` register driver (soft-reset → PPG channel → FIFO drain) + a float-free integer PPG→BPM peak detector (10 host tests). The `hr` task drives it over TWISPI0 and publishes to the face's HR row; an async timeout-bounded presence probe parks the task cleanly when the sensor is absent (the sim, an unwired bench) instead of stalling the executor. The licensed Maxim algorithm stays post-tier-1. Bench verification pending parts.

## 2026-07-08 — Barometer + elevation (BMP581)

`bmp581` register driver (5 host tests) on TWISPI1 through the same probe guard, feeding `watch_core::elevation` (barometric altitude + cumulative-vert accumulator). Surfaced end-to-end: the face's ALT row prefers baro altitude and gains a VERT line; the phone-link frame carries an additive optional `elev` object the Sim Watch screen decodes. Per the [§ 90 BOM refresh](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified).

## 2026-07-08 — Recorder port with auto-pause (step 7 core), sim-verified

`watch_core::record` ports the Dart `run_recorder` state machine (Idle → Recording → Paused → Finished) to host-tested `no_std` Rust: haversine distance, elapsed/moving time, pace, the point-acceptance filter (min-move 3 m, max-jump 100 m, max-speed 10 m/s), and the derived moving-time **auto-pause** (0.5 m/s gate); 7 host tests. The `record` task selects over tick / fix / command and publishes snapshots the face renders. Sim run shows distance accruing and auto-pause holding moving time.

## 2026-07-08 — Button control

The `button` task debounces the DK buttons and feeds the host-tested `watch_core::button` press→command logic (4 host tests): BTN1 start/pause/resume, BTN2 stop, BTN3 page cycle. On hardware BTN1 is the only start path; the sim's fix-triggered auto-start lives behind the default-OFF `sim-autostart` feature.

## 2026-07-08 — Flash run store

The record task captures the GPS *track*, not just totals: each accepted fix is staged through a `run_store::RunWriter` (compact binary wire format — 16-byte points, CRC32, golden-vector host tests) stamped with the latest HR + baro altitude, and committed to internal flash on stop. `app/src/run_flash.rs` drives the NVMC over the host-tested `watch_core::flash_store` slot layout: **4 slots × one 4 KiB erase page** reserved at the top of flash, a **253-point-per-run cap** — a bench-prototype foundation, not shipping capacity (a real ultra needs the tier-2 external QSPI flash). Best-effort / L4: flash errors only warn, recording is never blocked on storage. [decisions.md § 211](../architecture/decisions.md#211-owner-override-build-the-full-watchphonesupabase-run-sync-vertical-now-despite-the-tier-2-gate).

## 2026-07-08 — BLE GATT + run-sync protocol (step 6 + step 7 sync), compile-verified only

Behind the default-OFF `ble` feature: the S140 SoftDevice via `nrf-softdevice`, a custom 128-bit "Threkir" GATT service notifying the same link frames the UART/sim transport emits, a ~1 s connection interval for idle-radio power, and the `run_manifest` / `run_chunk` characteristics implementing the chunked run-sync protocol from [`firmware.md`](firmware.md). The Renode sim cannot run the proprietary SoftDevice and there is no dev kit, so this whole path is **compile-and-link-verified only** — deliberately, per [§ 210](../architecture/decisions.md#210-tier-1-ble-s140-softdevice-is-a-compile-verified-feature-gated-build--mutually-exclusive-with-the-sim-off-by-default): it proves the dependency stack is viable and leaves only on-hardware validation.

## 2026-07-08 — Phone-side sim watch sync

The mobile app's half of the § 211 vertical: `sim_watch_sync.dart` mirrors `run_store` (manifest pull, chunk reassembly, CRC verify — pinned to the same golden vector as the Rust test so the decoders can't drift), reshapes the blob into the payload the existing `WatchIngestQueue` → `api.saveRun` path already uploads, behind an injectable transport seam over the sanctioned `flutter_reactive_ble` ([§ 212](../architecture/decisions.md#212-watch-run-sync-phone-ble-stack-is-flutter_reactive_ble-and-the-blob-crc-covers-headerpoints-footer-totals-recomputable)). A dev-gated "Sync runs" action drives it; the pull→decode→verify→deliver path is unit-tested without a radio.

## 2026-07-08 — Power-discipline pass

Tier-1's power job is architecture, not measured numbers ([`performance_path.md`](performance_path.md)); this pass landed the firmware-side levers: partial display updates (dirty lines only), burst-buffered GPS UART reads (one wake per ~32 bytes), face animations gated to an ~8 s post-interaction window, the liveness LED behind a default-OFF `dev-blink` feature, hardware EXTCOMIN VCOM (a clean framebuffer flushes zero SPI), an event-driven screen task + gated record tick (idle CPU sleeps seconds apart), and GPS fix-publication de-rate while no run is active. Each sim-verified where the sim can observe it; the EXTCOMIN wiring itself is bench-gated. Detail in [`apps/custom_watch/README.md` § Power discipline](../../apps/custom_watch/README.md).

## 2026-07-09 — Sim button injection + page-render fix

Renode's nRF52840 GPIO model doesn't implement the SENSE/DETECT path the low-power hardware button task rides, so buttons were bench-only. A default-OFF `sim-buttons` feature swaps in a level-polling variant driven from `sim/watch.resc` monitor macros (`runMacro $btn1/2/3`), leaving the hardware SENSE path byte-for-byte untouched ([§ 213](../architecture/decisions.md#213-sim-button-injection-uses-a-poll-in-the-sim-feature-not-a-firmware-wide-change--renode-doesnt-model-the-nrf-gpio-sense-path)). Exercising BTN3 in the sim immediately surfaced and fixed a real render bug: the screen task's `select(...changed())` wait consumed one-shot page-state changes before the render loop could apply them, so pages never switched on screen. Page cycling and sim-driven stop (BTN2 → `Finished` → flash commit path) are now sim-verified. A clippy (`is_multiple_of`) + rustfmt sweep closed out the day.

## 2026-07-09 — Auto-lap + manual lap

`watch_core::record` grows lap counters: a **1 km auto-lap** closes on the accepted fix that carries the current lap past `AUTO_LAP_DISTANCE_M`, and a **manual lap** (`Recorder::lap`, driven by **BTN4** — the Fenix layout's lower-right Lap per [§ 81](../architecture/decisions.md#81-custom-watch-input-is-5-physical-buttons-in-the-garmin-fenix-layout-no-touchscreen)) closes through the same `close_lap` path and resets the auto countdown, so the next kilometre measures from the press rather than from multiples of the run total. Each lap carries index / distance / split (elapsed) / moving time; the in-progress lap's number, time, and distance ride the published `Snapshot`. Laps are **RAM display state only** — the flash run-store wire format is deliberately unchanged (it and its Dart mirror are pinned to a golden vector; persisting laps is a v2 blob-format decision for later). The run view gains a fourth page (BTN3: Dashboard → Distance → Pace → Lap) putting the current lap time up large with lap number, last-lap split, lap distance, HR, and GPS as context. Recorder tests grow 8 → 13, button 4 → 5, face 22 → 25; sim-verified end to end — `runMacro $btn4` lands `button: Lap -> Lap` → `record: command Lap`, and the Lap page renders on the emulated panel. Bench verification pends parts, like everything else.

## 2026-07-09 — Grade-adjusted pace (fourth parity port)

`watch_core::grade_adjusted_pace` ports the Minetti GAP helper as the **fourth parity surface** (web `grade_adjusted_pace.ts` canonical → Dart twin → Connect IQ `GradeAdjustedPaceView.mc` → Rust firmware): the identical `grade_factor` polynomial + ±45% clamp, the whole-track batch helper with the same `None` edge cases (too few points / no timestamps / no elevation), and its test suite mirrored case-for-case against the TS/Dart oracles (flat = 200 s/km, uphill faster, descent slower, mixed-elevation still computes). On top sits a streaming `GapEstimator` in the Garmin field's on-watch shape — grade rolled forward only per ≥5 m covered (altitude jitter can't manufacture a grade), a 0.4 m/s walk gate, and the field's runaway-pace guard. The `Recorder` feeds it each accepted fix with the **baro-preferred altitude** (`set_baro_altitude` from `state::ELEVATION`, GPS `alt_m` fallback — the same preference the flash store's point stamping uses), publishes `Snapshot.gap_s_per_km`, and the Pace glance page renders a `GAP` row under HR so raw and effort-equivalent pace read together on a hill; with no altitude signal the grade stays 0 and GAP reads as raw pace, matching the field's no-altimeter behaviour. Flash run-store wire format untouched. GAP module 17 host tests, recorder 13 → 17, face 25 → 26 (watch_core 101 total); sim-verified on a synthetic 10% climb fed as a custom NMEA fixture — the emulated panel's Pace glance shows `GAP 1:41 /KM` against a raw `NOW 2:46 /KM`, the exact Minetti factor at that grade. Bench verification pends parts.

## 2026-07-09 — HR zones + in-zone time

`watch_core::hr_zones` mirrors the main app's default zone model rather than inventing one (§ 24 — pioneering happens on web): web `training/hr_zones.ts` is canonical (Dart + Wear OS twins) — Z1..Z5 upper bounds at 60/70/80/90/100 % of max HR rounded half-up like `Math.round`, the same inclusive boundary rule (`bpm <= cutoffs[0]` is Z1, past `cutoffs[3]` is Z5), and the same legacy **190 bpm fallback**; the explicit-`hr_zones` / Tanaka-from-age precedence stays a phone/web concern, with `Recorder::set_max_hr` a plausibility-guarded (80..=240, the web override window) hook for a future settings sync. The recorder banks **per-zone moving time exactly where `moving_s` accrues** — a manual pause, an auto-pause, and a missing or dropped pulse (`set_hr(None)` when the peak detector loses it) bank nothing, and `start()` zeroes the accumulators. The `Snapshot` carries the ladder + accumulators, every run-view HR row gains the live zone (`152 BPM Z3`; the idle status face keeps its plain BPM), and BTN3 gains a **fifth Zones glance page** after Lap: the live BPM as the 2x hero, the current zone beside the label, and one row per zone — split-format time plus a bar scaled to the fullest zone — over the usual GPS glance. Flash run-store wire format untouched. New `hr_zones` module 5 host tests (boundary values pinned against the web fixtures), recorder 17 → 22, face 26 → 30 (watch_core 115 total); sim-verified via `runMacro $btn3` ×4 to the Zones page — the sim has no HR sensor, so the honest check is the panel's `--` hero, `ZONE --`, and all-zero zone rows while distance/moving time accrue (the no-HR gating end-to-end). Bench verification (a real pulse driving zone accrual + the live `Z` tag) pends parts.

## 2026-07-10 — On-run alerts: drink / eat reminders + HR-zone ceiling

`watch_core::alerts` lands the roadmap backlog's T1 alert slice ("drink / eat / nutrition reminders — the ultra-critical one" + the HR-zone alert; pace / distance / time alerts stay T2). Per § 24 the cadences are reduced from the main app's `fuel_plan` defaults rather than invented: 60 g carbs/hr ÷ 25 g per gel → **eat every 1500 s**, 500 ml fluid/hr ÷ a ~125 ml soft-flask sip → **drink every 900 s** — banked against `Snapshot::moving_s` (the same bank as the zone-time accumulators), so a manual pause, an auto-pause, or an aid-station stop accrues nothing. The **HR-zone ceiling alert** (`set_zone_ceiling`, off by default, guarded to 1..=4 the way `set_max_hr` guards its window) fires once per excursion above the ceiling, re-arms only when the zone drops back, and carries a 60 s cooldown against boundary flapping. One alert holds the screen at a time for an ~8 s TTL; zone outranks fuel and supersedes it, the superseded reminder re-queues rather than drops, and queued reminders promote eat-before-drink. The record task drives the pure engine after each recorder update and publishes to a new `state::ALERT` watch (L4 — an alert cannot disturb the recording math); the ui task draws the active alert as a `!`-prefixed all-caps **2x banner over the hero band** — display-only, the DK has no vibration motor. The sim shortens the cadences through the same public setter under `sim-autostart` (30 s drink / 45 s eat; hardware keeps the derived defaults). New `alerts` module 18 host tests (watch_core 115 → 133); flash run-store wire format untouched. Sim-verified: `record: alert Drink` / `alert Eat` alternate with `alert cleared` on the defmt stream at the shortened cadence, and a panel dump during the TTL window shows the banner replacing the elapsed hero over the run view. The zone alert is host-test-only for now — the sim has no HR sensor — so its on-wrist behaviour is bench-gated with the rest. [decisions § 214](../architecture/decisions.md#214-tier-1-on-run-alerts-anchor-their-fuel-cadence-to-fuel_plans-defaults-bank-on-moving-time-and-share-one-display-slot).
## 2026-07-10 — Even-pace virtual partner (Pacer page)

`watch_core::pacer` is the tier-1 pacing-guidance slice from the parity backlog: a goal (distance + time) defines a partner running at perfectly even pace on the **elapsed** clock — a race clock doesn't stop at an aid station, and Garmin's Virtual Partner runs on elapsed time for the same reason, so ahead/behind answers "will I cross the line by the goal time", not "is my moving pace on target". `Pacer::status` reduces the recorder's live distance + elapsed into metres ahead/behind, the same delta as seconds at goal pace, a projected finish extrapolated from the whole-run average, and an ahead / on-pace / behind verdict inside the app's shared ±5 % dead-band — the web `challenge_progress.ts` `ON_PACE_BAND` ratio rule, so the watch can't grade "on pace" differently than the app's challenge hint. Crossing the goal distance **latches the finish**: the delta freezes at the banked result instead of drifting while the runner jogs out; `start()` clears the latch (run state) but keeps the goal (settings), the same split as the sticky max HR. The goal is **unset by default** and armed only through `Recorder::set_pacer_goal`, a plausibility-guarded (100 m..1000 km, 60 s..~11.5 days, ignore-don't-clamp) settings-sync hook mirroring `set_max_hr` — nothing on-device sets it at tier 1; the sim build arms a demo 1 km / 5:00 goal behind `sim-autostart`. BTN3 gains a **sixth Pacer glance page** after Zones: the signed delta as the 2x hero (`+0:42` ahead, `-1:05` behind, grow-to-hours), the verdict beside the label, then goal / target time / projected finish / distance delta over the GPS glance — or an honest `PACER --` / `NO GOAL SET` inactive state, never zeros pretending to be on pace. Even-pace only by design: grade-aware splitting (PacePro's terrain allocation, the roadbook's `gradeFactor` effort split) is a later slice on the same seam. Flash run-store wire format untouched. New `pacer` module 12 host tests, recorder 22 → 26, face 30 → 34 (watch_core 135 total); sim-verified — the record task's debug snapshot line shows the delta evolving against the demo partner (`pacer=Some(0)` → `-5` → `-10` over the bench jog) and `runMacro $btn3` ×5 renders the Pacer page live on the emulated panel (hero `-0:28` → `-0:32`, `DIST -94 M` → `-109 M`, `BEHIND`, the elapsed clock running through an auto-pause exactly as a race clock should). Bench verification pends parts.

## 2026-07-10 — Breadcrumb course following + off-course alert (fifth parity port)

`watch_core::course` ports the main app's course-projection math as the **fifth parity surface**: `Course::project` mirrors web `route_snap.ts` `snapToPolyline` (the nearest perpendicular foot on the closest segment in a per-segment local equirectangular frame — not merely the nearest vertex) plus the along-course accumulation `route_geometry.ts` `distanceAlongRoute` resolves, tests mirrored case-for-case against both TS suites; `OffCourseAlert` latches the mobile run screen's route-overlay thresholds (alert past 40 m, re-arm only back under 20 m, so GPS jitter at the boundary can't flap it); and `PanelFit` maps the course bbox into a pixel panel with the `track_projection.ts` cos(mid-latitude) correction. Capacity is a fixed 256 points (4 KiB RAM) — `from_points` rejects an overflow rather than truncating a course mid-race; a longer course must be phone-simplified before the future BLE push. On the display side `sharp_mip` gains a Bresenham `draw_line` (clipping, dirty-line aware) and the run view a **seventh Nav page** (BTN3 after Pacer): the course polyline + a clamped position-marker cross in a 168x96 panel, distance-along-course + perpendicular offset below, honest NO COURSE LOADED / AWAITING FIX empty states, and a steady (never blinking — a lost runner must not catch the blank frame) 2x OFF COURSE banner over the breadcrumb while the alert is latched. The panel repaints only when the (marker, alert) pair changes, so a resting Nav page still flushes zero SPI lines. The new `nav` task does the per-fix projection and publishes to `state::NAV`, warning on the alert's rising edge whatever page is up; the only course today is the canned sim one behind the default-OFF `sim-course` feature (the west + south edges of the `bench_jog` rectangle, so the fixture's east + north legs exercise the whole surface every lap). Course module 20 host tests, `draw_line` 4 (driver 18 → 22), face 34 → 40 (watch_core 179 total); sim-verified end to end — `nav: course loaded, 3 points, 179 m`, BTN3 ×6 to the Nav page, `nav: OFF COURSE (41 m off, 179 m along)` with the banner + breadcrumb + marker rendering on the emulated panel, then `nav: back on course` as the loop closes on the NW corner. Bench verification pends parts.

## 2026-07-10 — TrackBack / back-to-start

`watch_core::trackback` turns the recorder's accepted-fix seam (`Recorder::last_fix_stored` — the exact points the flash track stores) into the parity backlog's back-to-start navigation: the live haversine distance + great-circle initial bearing to the run's start, a **course-over-ground heading** (tier 1 has no magnetometer, so the heading derives only from ≥5 m of accumulated real displacement — GPS jitter around a stationary point can never manufacture one — and goes honestly stale 10 s after movement stops: `--`, never a frozen arrow), and a **fixed-RAM decimated breadcrumb** — 96 points kept at 20 m spacing that, on overflow, **thins by keeping every other point and doubling the spacing**, so the whole track stays represented at coarser resolution instead of the tail falling off (~245 km inside ~768 B; seven doublings). BTN3 gains an **eighth Back-to-start page** after Nav: distance-to-start as the 2x hero (metres under a km, clamped km beyond), 16-wind HDG/BRG rows, the relative direction arrow (bearing minus heading, drawn from `arrow_lines` via the `sharp_mip` `Framebuffer::draw_line` Bresenham primitive), and a north-up, aspect-preserved breadcrumb map (hollow-box start marker, filled-dot current position) in the region the face's text rows reserve (`TRACKBACK_TEXT_COLS`). The `record` task feeds the crumb per accepted fix and publishes a `TrackbackView` to `state::TRACKBACK`; a run start resets it so run 2 never renders run 1's crumb. RAM display state only — flash run-store wire format untouched. New `trackback` module 14 host tests, face 40 → 44 (watch_core 197 total; the breadcrumb + arrow reuse the course port's `sharp_mip` `draw_line`); sim-verified two ways — the canned jog (the emulated panel renders the rectangular loop with the arrow pointing back at the start; distance/bearing evolve around the loop in the defmt stream) and a straight-line 8 m/s fixture long enough to overflow the buffer (the one-shot `trackback: breadcrumb thinned to 48 points (spacing doubled)` fires at ~1.9 km, and the hero flips from metres to km past 1 km). Bench verification pends parts.

## 2026-07-10 — Selectable GNSS recording modes

`watch_core::gnss_mode` generalises the gps task's idle fix de-rate into the **Performance / Balanced / Expedition** recording-mode surface every ultra watch ships ([roadmap.md § Sensors & connectivity](roadmap.md#sensors--connectivity)): every ~1 s fix / one per 15 s / one per 60 s (the Garmin UltraTrac / COROS UltraMax class), each carrying a **projected**-battery-hours figure (~110/~180/~220 h — derived in the module docs from the `vision.md` tier-2 target + `performance_path.md`'s GNSS duty-cycling lever, explicitly not a measurement; the DK can't measure ultra-watch power). BTN3 cycles the mode on the **idle face** (a `MODE PERF ~110H` row pairs the tag with its figure; the host-tested `btn3_action` keeps mid-run BTN3 on pages, so a run's mode is frozen for its duration — no chorded input, decisions § 81's button budget holds). Downstream the mode threads through every consumer: the gps task forwards fixes at the mode's cadence while a run is active (idle keeps the old de-rate; Performance keeps the historical unconditional full rate), the recorder's corrupt-fix jump gate scales to the interval (`MAX_SPEED_MPS * dt` past 1 s, since the fixed 100 m ceiling would reject every legitimate ~240 m Expedition segment — deliberately keyed off the configured interval so the 1 Hz filter is never loosened), and the face's staleness budget stretches to the cadence (`stale_after_s`) so a 40 s-old fix in Expedition reads `SATS`, not `STALE` — while a genuinely lost signal past the mode's budget still flags, and the idle face keeps the tight 5 s budget in every mode. Run-view GPS rows carry the mode tag. Flash run-store wire format untouched. New `gnss_mode` module 5 host tests, button 5 → 6, recorder 26 → 30, face 44 → 49 (watch_core 212 total); sim-verified end to end via the new `bin/watch-sim.sh --no-autostart` flag (boot idle → `runMacro $btn3` → `MODE BAL ~180H` renders on the emulated panel → BTN1 starts the run): forwarded-fix cadence measured in the defmt stream at ~1 s (Performance), ~15 s (Balanced), ~60 s (Expedition) with distance accruing in all three. What the sim can't demonstrate: any actual power saving (Renode doesn't model power, and the tier-1 throttle cuts downstream wakes only — the UART keeps streaming) and the tier-2 receiver power-down (u-blox power-save / backup mode) this surface plugs into. Bench verification pends parts.

## 2026-07-10 — Cut-off ETA + race-time predictor (two parity ports)

Two tier-1 parity ports built as one batch on top of the course + recording core the earlier batch landed. Both are Shape-A (result folded into `Snapshot`, page reads `snap`, no ui-task change), each a `watch_core` port of an existing app helper (§ 24 — no pioneering).

`watch_core::cutoff_eta` ports web `runs/live_cutoff_eta.ts` `nextCutoffEta` (the `roadbook.ts` `CUTOFF_TIGHT_S` = 30 min span, nearest-cutoff-ahead by strict distance, flat-pace projection), mirrored test-for-test. It rides the breadcrumb-course work: the `nav` task's along-course projection is fed into the **course-agnostic** recorder via `set_route_position` (the same external-input pattern as `set_hr` / `set_baro_altitude` / `set_pacer_goal`, not a course dependency in the core math), and the recorder folds in the whole-run pace to project on / tight / behind at the next cut-off. The port's honesty rule holds: a **stale route position** (lost signal, aged past a stale budget scaled to the GNSS mode's fix interval) or an unknown pace **withholds** the projected time (`Unknown`) rather than fabricate an arrival off a frozen fix — the checkpoint distance is still reported. Cutoff legs are static at tier 1 (canned on the sim course; the hardware build carries none until a BLE course-push lands, so its page reads `NO CUTOFFS`).

`watch_core::race_predictor` ports web `training/race_predictor.ts` `predictRaceLadder` plus the `riegelPredict` (exponent 1.06) + `predictionConfidence` helpers it reuses (recency half-life 30 d, the 5K/10K/Half/Marathon ladder, recency-weighted anchor, per-rung confidence), mirrored test-for-test. On a standalone tier-1 watch the effort pool is the **current run treated as a single effort** — the only source available — projected once the run clears a 1 km input-validity gate (below that a Riegel projection off a warm-up is noise). The ported algorithm is unchanged; only its input is watch-appropriate.

Surfaces: BTN3 gains a **ninth RacePredictor page** (after Pacer) and a **tenth CutoffEta page** (before Nav), settling the cycle as Dashboard → Distance → Pace → Lap → Zones → Pacer → RacePredictor → CutoffEta → Nav → BackToStart. RacePredictor shows the whole ladder — the 10K projection as the 2x hero, each rung with a confidence flag (` ` solid / `?` moderate / `~` low) — with a `NEED 1 KM` blank state. CutoffEta shows the margin as the signed-split hero (`+` slack / `-` over), the verdict, the distance to the cut-off, and the projected arrival clock, with honest `NO CUTOFFS` / `NO CUTOFF AHEAD` / `--` states. Both are text-only glances (no pixel panel), so `sharp_mip` is untouched. Flash run-store wire format untouched.

New `cutoff_eta` 13 + `race_predictor` 13 module tests, recorder 30 → 33 (route-position + cut-off gating, the min-distance predictor gate), face 49 → 53 (both pages, active + honest-inactive states, exact rendered rows) — **watch_core 212 → 245**. The full host suite, embedded release build (hardware default features), the sim feature set build (`sim-autostart,sim-buttons,sim-course,dev-blink`), embedded `clippy -D warnings`, and `rustfmt` are all green. **The rendered output is pinned by the face tests** (`CUTOFF        ON` / `TO   10.00 KM` / `ETA  1:30:00`; `5K   20:00 ?` and the `~` low-confidence marathon rung). Renode sim + bench verification are **pending** — renode/defmt-print weren't available in the authoring session, so unlike prior entries this one does not claim a live sim run; the sim build is clean and the render is test-pinned. [decisions § 215](../architecture/decisions.md#215-tier-1-cut-off-eta-feeds-the-course-agnostic-recorder-a-route-position-the-race-predictor-projects-the-current-run-as-a-single-effort).

## 2026-07-26 — five buildable-now items, chosen because none needed parts

A five-worktree parallel batch scoped deliberately: the work that needed **neither hardware nor a
§ 71 tier-2 trigger**, picked after a pass over the parity backlog established that tier-1's
remaining debt is verification, not code. Host tests **1799 -> 1883**; all three feature sets
build, `clippy -D warnings` and `cargo fmt --check` clean. **Host-tested + build-verified only**
(§ 314) — Renode is not installed on the authoring machine and no parts exist, so nothing here
claims a sim or bench rung, and the radio leg of the course push is a bench item.

Two parity ports: `cutoff_eta` caught up to web issue #607 (`required_pace_s_per_km` +
`limit_passed`, the pace computed even on a stale fix because it does not depend on recent pace),
and `race_phases` landed as a new core (the 10-10-10 / negative-split / even phase plan, closing
factor derived so the distance-weighted mean is exactly 1.0) surfaced on the Pacer page's one
spare row. Three surface items: distance / time / pace alert kinds in the existing engine
(§ 332), a glance page for the already-ported `guided_runs` (§ 333), and the pushed course's
climb profile drawn with a position marker behind a `CRS1` v2 elevation array (§ 334).

**Three defects the batch found, which is the part worth recording.** `Page::bit()` returned
`1 << discriminant` as a `u32` and the enum stood at exactly 32 variants, so page 33 would have
wrapped to bit 0 in release and silently shared the Dashboard's bit — un-hideable, mis-counted,
and reachable through a mask built to exclude it. The page grid was full to the cell at 4 x 8,
which is why it surfaced as a compile error rather than a dropped page (the `const` assert
earned its keep). And `cutoff_eta` gated pace on a bare `p > 0.0`, accepting `+Infinity` where
the canonical helper gates on `Number.isFinite`. All three fixed here.

**Owed, and named rather than deferred silently:** the `CRS1` frame carries no CRC, so a flipped
byte in the point array decodes as a valid but displaced course (the hole § 319 closed for `SET1`
and § 321 for the run blob) — a v3 reusing `run_store::crc32` is the fix. The `SET1` fields that
would let a phone set the three new alert cadences are unwired, as are push paths for
`set_race_phases` / `set_guided_run`. And `navigation.md`'s two page-grid press-cost rows now
predate both the 33rd page and the row-scrolling window; an independent BFS reproduced the linear
row exactly but not those two, so they are flagged for re-measurement rather than re-derived from
a model that does not match.

## 2026-07-26 (second batch) — the wire formats hardened, and the owed items closed

A three-worktree pass taking the previous batch's named debt rather than new features. Host tests
**1883 -> 1903**; three feature sets build, `clippy -D warnings` and `cargo fmt --check` clean,
both Dart twins byte-identical. **Host-tested + build-verified only** (§ 314).

`CRS1` v3 seals the course push with a mandatory CRC32 (§ 335) — and unlike the settings frame its
pre-CRC versions stop decoding, because a course has no plausibility guard that could catch a
displaced polyline and because an accepted un-checksummed version is a bypass. `SET1` v4 carries
the five settings the firmware honoured but the phone could not reach (§ 336), so the alert
cadences, pace band, race-phase plan and guided-run selection are now armable on real hardware
rather than only in the sim. And `navigation.md`'s press-cost table is re-derived at 33 pages after
the missing term was found: the grid is additive, so a page costs `min(walk, 1 + grid moves)` — the
model then reproduces the pre-page-33 table exactly, which is what licensed publishing new figures.

**Process note worth keeping.** Three agents ran in parallel worktrees; two fast-forwarded onto the
working branch, the third forked from `origin/main` and correctly reported that the sinks its wire
fields needed did not exist — because the batch that built them was not yet merged. It declined to
add fields with no sink, which is the right instinct and exactly what the `settings_apply` seam
exists to enforce, but it also rebuilt work already landed. The lesson is a briefing one: an agent
whose worktree may fork from stale main must be told to fast-forward onto the working branch first
and to verify the premises it was handed before building on them.

## 2026-07-28 — training load whole: TRIMP stress + the rolling trio

The last unbuilt halves of the training-load row, pulled forward like the 2026-07-26 batch because
neither needed parts ([§ 352](../architecture/decisions.md)). `SET1` v5 puts the **resting HR** on
the wire (`flags2` bit 6 — the TRIMP calibration pair's second half; max HR has ridden since v1),
the recorder banks a time-weighted HR average exactly where zone time banks, and the single-run
stress upgrades from the 10-points/km proxy to **Banister TRIMP** when pair + average are live —
with the page's `LOAD` row naming the model in force (`TRIMP`/`DIST`) so the number is never
silently re-scored. The **rolling CTL/ATL/TSB** lands as a whole-or-nothing
`Recorder::set_load_trend` push (the `set_fitness` hook shape, no wire field yet) rendering
`CTL/ATL` + a signed `FORM` row once synced. The frozen v4 full-frame golden joins the v1/v2/v3
compat vectors; a v4 frame claiming the v5 bit is rejected. Dart encoder + goldens moved in
lockstep across both twins; the resting-HR-only vector is pinned Rust↔Dart. Host-tested +
build-verified.

## 2026-07-28 — activity profiles: four presets over the knobs that already existed

The parity backlog's "Activity profiles" row, landed as a **macro, not a container**
([§ 353](../architecture/decisions.md)): `watch_core::profiles` names Run / Trail / Ultra / Hike,
each a curated §284 page mask + a GNSS mode, selected from a **fourth §351 settings-menu row** as a
clamped directional ladder (right = longer / more battery; a first-ever press starts at Run, left
of unset applies nothing). Applying a profile rides the SAME channels a phone push and the idle
quick-cycle ride — pages via `state::SETTINGS`, mode via the shared `set_gnss_mode` — so §351's
last-writer rule needed no third state system. The selection persists in CFG1's reserved byte
behind a third flags bit (the no-version-bump drill again) and boot re-applies the preset;
`persist_hide_empty` stopped rebuilding the shared flags byte from scratch on the way, which was a
latent single-writer assumption waiting to eat a future flag. No per-profile alert cadences (§24).
The four-item menu keeps the ≤ 4-press setting-change bound (farthest row is still two wrapping
cursor steps). Host-tested + build-verified.

## 2026-07-28 — structured workout execution: the mobile runner's math, on the wrist

The parity backlog's last big on-run-guidance row ([§ 354](../architecture/decisions.md)).
`watch_core::workout` ports the **shipped** mobile `WorkoutRunner` faithfully — per-step anchors,
the overshoot-carrying multi-step advance loop (a single fix after a GPS gap can clear a short rep
AND its recovery), both end axes, the end-of-step warning window, the mobile pace-adherence bands,
and the ≥80 % completed/partial roll-up — fed the phone-expanded step list over a **`WKT1`** frame:
a sixth GATT characteristic, chunked + reassembled in the course push's exact shape, and
**CRC32-checksummed from v1** (the § 335 lesson applied in advance; a step with no end condition or
both axes set rejects the frame whole, and the recorder's setter re-checks the same rule). The
recorder banks `manual_paused_s` so the workout clock matches the phone stopwatch exactly — frozen
by a manual pause, running through an auto-pause (a standing rest inside a timed recovery is the
step working); **BTN5's lap press doubles as step-skip** (Garmin's lap semantics — § 350 has no
spare key); and the step transition / end-of-step / DONE edges ride the alert slot as `! REP 3/6`
/ `! STEP END` / `! WKT DONE` banners, one rung under the zone ceiling, drop-not-queue, displaced
fuel re-queueing. A 34th **Workout glance page** closes the live cluster beside GuidedRun (step
identity, target, live progress + a render-layer bar, the pace-band adherence vocabulary, the NEXT
step); the § 289 press-cost model re-derived at 34 pages (worst stays 6, avg 3.8235; the linear
worst grows 16 → 17 at the even ring's antipode). Deliberately not ported: rewind / abandon (no
key budget) and the halfway cue (banner spam); the per-step result trail stays RAM-only pending a
run-store format bump, and haptic cues wait on the tier-2 motor. Phone-side `watch_workout.dart`
encoder + chunker take `run_recorder`'s own `WorkoutStep` type and pin the Rust goldens across
both twins, transport-unwired like the course encoder. Host-tested + **sim-verified** (Renode:
the sim demo workout advances warmup → rep → timed recovery under bench_jog with the banners and
fuel re-queue interleaving in the defmt stream).

## 2026-07-28 — Daylight sunset countdown: the ported solar model on a 35th page

The tier-2 board's S-sized pull-forward ([§ 355](../architecture/decisions.md)). `watch_core::daylight`
ports the web `safety_nudge.ts` seasonal half (Cooper's declination, solar noon at local 12:00, the
−0.833° horizon, polar day/night at the `cos H` clamps) test-for-test; the watch adds input shaping
only (§ 215) — `Fix` now carries the RMC `ddmmyy` date behind a day/month plausibility gate, the fix
clock extrapolates by uptime and shifts **with its date** into local civil time, and the § 293
`SET1` v2 timezone offset doubles as the page's data presence: a countdown against the wrong
midnight is whole hours off, so no offset means no page in the cycle rather than a wrong number on
one. The **Daylight glance** (`SUN`, just ahead of the still-last Back-to-start) puts the countdown
floored to H:MM up large over SUNRISE/SUNSET, the event's local clock, and the day length; after
sunset it counts across midnight to tomorrow's sunrise, and the polar seasons answer with two new
Settled unfed states (`MIDNIGHT SUN` / `POLAR NIGHT`) instead of a fabricated clock. Press costs
re-derived at 35 pages: grid worsts hold 6/9, symmetric avg 3.8857, linear worst holds 17 (an odd
ring has two antipodes). The sim demo settings push UTC-6, so bench_jog renders the golden pre-dawn
case — 3:03 to a 04:34 sunrise, 14:53 of day — and `ci_smoke`'s page walk reaches, dumps, and
steps back off the page. Host-tested + sim-verified.

## 2026-07-29 — Run-store v4: the workout trail lands in the flash blob

§ 354's named leftover closed ([§ 356](../architecture/decisions.md)). Each settled workout step's
outcome streams into the staged blob as a tag-2 cell beside the laps — so the mid-run checkpoint
ping-pong carries the trail through a brown-out — and the stop flushes the in-progress step as
skipped-so-far plus a tag-3 summary: planned step count, the ≥80 % roll-up, and the armed step
list's canonical `WKT1` frame CRC (`workout_store::frame_crc`, one `step_bytes` layout shared with
`encode` so hash and frame cannot drift). That CRC is the attribution handle — the phone matches
the trail to the workout it *pushed*, never "whatever came last" — and the phone decoder (v3 + v4)
forwards the section into the new owner-only `metadata.watch_workout` key (registered,
`public_runs`-stripped by `20270430_001`), dropping it whole when a checkpoint recovery has no
summary or a mid-run re-arm spliced duplicate indices; the run itself is never dropped for its
auxiliary trail. Neither workout tag ever decimates; v3 goldens stay as decode-compat vectors and
the v4 goldens pin both codecs. Workspace host sweep 2061 → 2073; sim-verified — `ci_smoke`'s
smoke stop now asserts "workout results stored (5 planned steps)" ahead of the flash commit. The
`plan_workout_id` join stays with the product push surface — but the transport half of that seam
closed in the same batch: `WatchBleTransport.writeWorkout` targets the sixth characteristic,
`WatchSyncClient.pushWorkout` carries `chunkWorkout`'s in-order offset chunks, and the dev Sim
Watch screen gained a Push-workout action (the §209 surface) that sends the golden demo workout —
so the encoder finally has a live caller and the CRC handshake is exercisable end-to-end. The
course encoder followed in the same batch: `WatchSyncClient.pushCourse` writes `chunkCourse`'s
chunks to the fifth characteristic and a Push-course action sends the golden three-point sim
course + elevation, so every phone→watch push rail (settings / course / workout) now has both
halves wired. And the frame CRC closed the loop it opened: an identical workout re-push (a BLE
retry, a reconnect) is now a recorder-level no-op, so a transport hiccup can't wipe mid-run step
progress and splice the duplicate-index trail the phone fail-closed drops.

## 2026-07-29 — Three parity rows in one batch: waypoints, the ICE card, climb detection

Three backlog rows that had each been waiting on something other than maths ([§ 357](../architecture/decisions.md),
[§ 358](../architecture/decisions.md), [§ 359](../architecture/decisions.md)).

**Waypoint marking (§ 357)** had been blocked on the button budget, and the row's own
settings-menu candidate turned out to be wrong: the menu exists only while idle, and the position
worth saving is one the runner is standing on mid-run. The grammar had one gesture free after all —
**BTN5's hold**, on the same 500 ms boundary the paging keys train, firing at the threshold while
still held. `waypoints` is an eight-slot newest-wins store with a `WPT1` codec; marks take the
recorder's distance anchor so the saved point and the recorded track agree, survive `start` and
`reset` (a stash marked on a recce is the point), and persist on the press rather than at stop —
you may not finish the run that found the stash. A refused mark writes nothing, so a dead press
costs no page erase. That third config-page record is why `rewrite_config_page` stopped taking one
`Option` per record: four positional same-shaped `Option`s is the shape a caller transposes in
silence, so it takes a `ConfigPage` struct now.

**The ICE / medical-ID card (§ 358)** rides `SET1` v6, which spends `flags2`'s **last** free bit —
both presence bytes are now saturated and two const asserts in `decode` make the next field a
compile error rather than a frame accepted with an undefined bit. Every gate fails the card whole
rather than degrading a field, because a clipped allergy line reads as complete and a clipped
number dials someone else; that makes ICE the one settings field whose own content can reject the
frame, since it has no setter downstream to guard it. `IceCard` hand-writes its `defmt` impl to
print presence only — a derived one would spill a name, blood type, medical history and a
next-of-kin number into every logged settings frame. It is a third **idle face** (BTN4's walk
gained a one-way third stop) plus a named `MEDICAL ID` menu row for discoverability, and an
`ICE1` flash record, because a medic reads the wrist of a watch that may have power-cycled. Known
tier-1 limit, recorded rather than papered over: the face is idle-only.

**Climb detection (§ 359)** is the batch's one item with no web helper to port. `climb` splits
into the two questions a runner asks: `ClimbDetector` segments the climb underfoot from the same
altitude sample `feed_gap` already takes (so a hill can't register on the GAP page and not this
one), and `crest_ahead` answers how much is left from § 334's distance-even course profile —
needing no new wire, since that series and the along-course position were already on-device.
Both edges hysteretic and deliberately blunt: a page that re-zeroes on every roller is worse than
no page.

Workspace host sweep 2073 → 2140; all three feature sets build and pass `clippy -D warnings`; all
**four** Renode scenarios (smoke / pages / alerts / terrain) green. `terrain` is new with this
batch and is what moves waypoints and climb from build-verified to **sim-verified**: the bench_jog
walk can only show both pages correctly ABSENT, which is indistinguishable from a data-presence bit
on the wrong field, so it boots `mountain_loop`, marks a point with the BTN5 hold and ramps the
BMP581 model past the climb-open threshold, then asserts both pages enter the cycle and render.
Arming that baro ramp is load-bearing — `feed_gap` prefers baro altitude, so the fixture's own GPS
ramp is shadowed by the model's static default. Splitting it out also exposed a latent harness bug:
`alerts` and `pages` had shared a boot, and `alerts` consumes the quiet window `pages` needs (past
~100 s the overlapping cadences never let a banner expire with nothing behind it, so
`record: alert cleared` stops firing). Each scenario now gets its own boot, which is what CI ran
all along. The page ring reached **37**, and pages 36
and 37 are the first to move a grid worst since the § 289 model was built — symmetric 6 → 7 at
page 36, forward-only 9 → 10 at page 37, linear 17 → 18 at page 36 (`navigation.md` re-derived).
The everyday filtered cost is unchanged at worst 4.

## 2026-07-29 (second batch) — the first sheet read back: three kinds of wasted cell, and two bugs behind them

[§ 360](../architecture/decisions.md) made the panel viewable; this is what looking at it produced
([§ 361](../architecture/decisions.md)). **Measured, not eyeballed** — the first impression ("the
pages are half empty") was wrong: mean ink was **6.6 of 9 rows** across the 37-page cycle, so the
waste was concentrated rather than general, and two of the three findings were about cells spent
saying something twice rather than cells left blank.

**`GPS` was a word on twenty-one pages** — five of twenty-one cells, on the one row whose meaning is
fixed across the whole cycle, to say what the dashboard's `Icon::Satellite` already said in two.
`page_icons` labels `GPS_ROW` everywhere now and `write_gps_row` lost its `label` parameter, so the
glyph and the cleared gutter have no way left to disagree.

**Units had drifted a row from their numbers.** `0.08` over `DISTANCE  KM` reads as a heading and a
number. They went there because the numeral faces spell only digits and separators, so one letter
demotes the hero to the pixel-doubled text font — the Workout page's `9.60 KM` was paying exactly
that. The unit is its own channel now, drawn at 1x on the hero's baseline. It joins the tall face's
width budget, counts toward the standing marker's clearance, and is suppressed when the hero holds
no digit.

**Thirteen pages reserved the hero band and left it blank** — a fifth of the panel, at the top, on a
third of the cycle, while the page's headline sat in an 8x16 row indistinguishable from its context
rows. Each headlines its own number now; the row that carried it is dropped rather than kept as a
small copy. Mean ink 6.6 → **7.3**.

**Two real bugs fell out, neither of which any host test could have failed on.**
A hero wide enough to reach the state tag clipped it — live on the dashboard past 100 hours, where
`AUTO` rendered as `UTO`, a tag naming a state the recorder is not in, on exactly the multi-day runs
where an auto-pause matters most. `write_tag`'s refuse-rather-than-truncate rule could not see the
hero, because the hero is not row text; `apply_hero_clearance` is the same refusal from the other
side. And the § 360 sheet itself had lied: **`page-Nav.png` was byte-identical to `page-Climb.png`**,
because the ui task logged `ui: page` *before* it drew. § 360 had added a pixel comparison to catch
that, then exempted the run walk on the grounds that "its elapsed clock changes every frame anyway"
— which is false for every page that shows no clock. The line moved to after the flush, so it now
claims the panel *has* the screen; the comparison stays as the detector for the other cause (a state
that never reached the composer) and now runs on every capture, not just the idle ones.

**A fourth duplicate class turned up while pinning the third.** Three pages already carried an exact
small copy of their headline (`WEAR 87 %`, `CARB 0 G`, `DIST 0.08 KM`), and the Zones page still
labelled its row `HR  BPM` under a hero whose unit is `BPM`. All four go, guarded by
`no_page_restates_its_hero_in_a_body_row` — narrow on purpose, since a row may legitimately hold the
same *number* as a different quantity and a ladder rung stays even when it duplicates. Writing that
guard also caught `fed_snapshot` giving independent fields one value in three places (the three
paces, both climb gains, both streak counts), which is the quieter bug of a test asserting one field
while reading another.

**The satellite glyph was redrawn** in the same pass, because it went from one page to thirty-seven.
It was the lightest icon in the table at 36 ink pixels against 54–110 for its siblings, and
off-centre (cols 1–10 of 16 where the others span 2–13).

The first attempt drew three arcs *from* the shared anchor dot, and rendering the cell showed why
that does not work: arcs sharing a start point overlap near it and part only at their tips, so at
16 px they merged into one diagonal wedge reading as a hook — identical in character across all
three frames. The table's checks passed on it (frames distinct, ink growing 19 → 37 → 59), because
an ink total cannot see a merge. The arcs are now **concentric about** the dot instead of radiating
from it, and symmetric about the cell's centre line so their apexes land as flat pixel runs rather
than stair-steps: 26 → 52 → **84** ink across the three acquiring frames, each arc separated from
its neighbours by clear panel.

`each_search_frame_shows_its_arcs_as_separate_bands` pins that. Because the fan is concentric, the
centre line is a ray out of the dot and has to cross one ink band per arc plus the dot — two, three,
four. It fails on the merged version at frame 0. *Drawn apart* is the property a runner reads;
monotonic ink never was.

**The bang was rendering as a colon**, found in the same look at the panel. Every alert banner is
`!` plus a word, and the `!` in the 8x16 table had kept its top serif and its dot while losing the
stem between them — two short marks, indistinguishable from `:` at a glance. So the banner shown
when the watch says drink, eat, ease off, or *you are at a cut-off* opened `: DRINK`, the mark that
separates an alert from a label reading as punctuation. Same lost-hairline failure the `gen_font.py`
repair pass exists for (`+` packing byte-identical to `-`, `|` shipping blank), one step short of
the collision that would have caught it: `!` and `:` differ as bytes, so nothing looked.

A glyph-wide heuristic was measured and rejected — "a stroke the 2x pass renders at over twice the
1x length" flags 33 of 95 glyphs, because 2x puts most stems across two columns where 1x picks one.
`DAMAGED_GLYPHS` names the near-misses instead and repairs them through the existing supersampler;
the regenerated table is byte-identical everywhere but `!`.
`bang_is_a_stem_over_a_dot_not_a_second_colon` pins the shape from the driver side — a taller
unbroken run than the colon's, and exactly two ink-to-blank transitions so the dot cannot fuse into
a `|` — so a named list falling behind the font fails a test rather than shipping.

**Coverage hole found on the way in.** `fed_snapshot()` backs every page-wide guard in `face.rs` and
only ever filled the *phone-pushed* views — so the Pacer, Workout, CutoffEta, Climb, Waypoint and
RacePredictor bodies had never been walked by the grid-fit sweep, the hero-band placement guard or
the state-tag sweep in anything but their empty state. All three pass unchanged with them fed:
nothing was broken behind the hole, it was simply unwatched.

Workspace host sweep 2140 → 2149; firmware builds; the four Renode scenarios and the 25-screen sheet
re-run green after the log-ordering change.

## 2026-07-30 — Countdown timer + stopwatch, and two refusals (§ 375), host-tested

The roadmap's daily-smartwatch row bundled "alarms / timer / stopwatch / find-my-phone" as one trivial item. Two of the four are trivial and are now built; the other two cannot be built honestly at tier 1, and the box stays **unticked** — nothing here is bench-verified.

**Built.** `watch_core::timers` is one instrument, not two: the preset ladder starts at zero and zero *is* the stopwatch, so there is no mode switch and no second key. Eleven rungs, all durations this repo already names (1/3/5 min aid-station turnaround, 10–90 min sleep-station nap, 60 min backyard bell). Armed from a modal on the idle face — **BTN2, the last dead key in the § 350 grammar** — with BTN1 start/stop, BTN2/BTN3 the preset ladder, BTN5 reset (refused while running), BTN4 exit on the settings menu's BACK slot. Every press swallowed, idle-only, 30 s auto-close. It survives run boundaries, and it takes the **38th** built-in page, gated on being armed. The expiry rides the *existing* alert slot as `Alert::TimerDone` at the milestone rung — dropped, never queued, and below fuel per § 214.

**The honesty decision.** No vibration motor, no buzzer: an expired countdown counts **up** past zero (`+2:14`) rather than freezing at `0:00`, because *how long ago* is the only part of a missed expiry that survives being missed. The banner reads `! TIME UP`; the word *alarm* appears nowhere on the device.

**Refused: alarms.** An alarm promises to interrupt you at a time you are not watching, and a display-only device cannot keep that promise. Re-scoped from "trivial, ship opportunistically" to a **T2 item gated on the haptic channel** — the same gate the sleep-station wedge already records.

**Refused: find-my-phone.** The watch is a GATT peripheral (§ 210 / § 211) with no watch-initiated action toward the phone, and the phone side is a pure consumer with no ring handler. It needs a new characteristic, new phone-side code and background-audio permissions, and per § 210 could never rise above build-verified without a dev kit. No stub was written. **T2, with the BLE bench work.**

**Cost, computed not guessed.** Page 38 moves neither grid worst (symmetric stays 7, stepping at 44; forward-only stays 10, stepping at 42); only the linear-walk worst grows 18 → 19. With the four composed-screen seats the full mask is 42, so the 7-press ceiling now has **one page of margin rather than two** — recorded in `navigation.md` rather than rounded away.

Workspace host sweep 2229 → 2261 (`cargo test --workspace --exclude app --exclude nrf52840_dk`; +32 — 21 in `timers`, 5 in `alerts`, 2 in `face`, 1 each in `record` / `button` / `input_flow`), plus the six count-pins the 38th page moved. Firmware builds green on the default, `ble` and sim feature sets; `fmt` and the clippy `-D warnings` gate clean. **No sim scenario and no bench evidence** — the modal has no `ci_smoke` step yet and the page cannot be armed from a fixture, so this entry claims host-tested and nothing more.

## Next entry expected

Parts order + first flash (blink on the real DK) — see [`parts.md`](parts.md). That entry starts the photo record.
