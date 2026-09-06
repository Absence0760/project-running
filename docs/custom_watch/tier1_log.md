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

`watch_core::grade_adjusted_pace` ports the Minetti GAP helper as the **fourth parity surface** (web `grade_adjusted_pace.ts` canonical → Dart twin → Connect IQ `GradeAdjustedPaceView.mc` → Rust firmware): the identical `grade_factor` polynomial + ±45% clamp, the whole-track batch helper with the same `None` edge cases (too few points / no timestamps / no elevation), and its test suite mirrored case-for-case against the TS/Dart oracles (flat = 200 s/km, uphill faster, descent slower, mixed-elevation still computes). On top sits a streaming `GapEstimator` in the Garmin field's on-watch shape — grade rolled forward only per ≥5 m covered (altitude jitter can't manufacture a grade — raised to ≥20 m on 2026-09-02, [§ 992](../architecture/decisions.md), after 5 m turned out to be below the noise floor divided by the clamp on all four rails), a 0.4 m/s walk gate, and the field's runaway-pace guard. The `Recorder` feeds it each accepted fix with the **baro-preferred altitude** (`set_baro_altitude` from `state::ELEVATION`, GPS `alt_m` fallback — the same preference the flash store's point stamping uses), publishes `Snapshot.gap_s_per_km`, and the Pace glance page renders a `GAP` row under HR so raw and effort-equivalent pace read together on a hill; with no altitude signal the grade stays 0 and GAP reads as raw pace, matching the field's no-altimeter behaviour. Flash run-store wire format untouched. GAP module 17 host tests, recorder 13 → 17, face 25 → 26 (watch_core 101 total); sim-verified on a synthetic 10% climb fed as a custom NMEA fixture — the emulated panel's Pace glance shows `GAP 1:41 /KM` against a raw `NOW 2:46 /KM`, the exact Minetti factor at that grade. Bench verification pends parts.

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

## 2026-07-30 — recovery time: the ported projection that reached no surface

The forward half of the Fitness page's recovery pair ([§ 369](../architecture/decisions.md)).
`fitness::days_until_next_hard_session` had been ported and host-tested since 2026-07-11 and was
called by nothing, so the page showed a verdict (`REST` / `EASY` / `SWEET`) with no answer to "how
long am I still paying for yesterday". It now carries a `NEXT HARD ~3 DAYS` row projected from the
ATL/CTL the `set_load_trend` push has delivered since § 352 — **no new wire field, no new setter, no
new page**: the inputs were already on the device one page over, and web puts this line on the same
Fitness card as the verdict. Web's returning-from-a-layoff suppression travels as the pushed
`RecoveryAdvice::ReturningFromLayoff` verdict rather than the run history the watch does not hold.
Four host tests (three-day + one-day projections, the already-recovered and the layoff
suppressions) plus an assertion on the existing no-load case. **Garmin's Training Status is not
built and is not owed** — web has no such classification, so § 24 forbids the watch pioneering one.
Host-tested only; no scenario arms the Fitness page.
## 2026-07-30 — the generated loop reaches the wrist: a route's own export menu gets a course push

Both ends of this had been built for months. The phone generates loops (the mobile builder's OSRM
bisection; the `graph_cycle` sidecar behind web's `/api/routes/generate`), and the watch has followed
a pushed `CRS1` course since v3 sealed it (§ 335) — Nav page, off-course alert, turn cues, climb
profile, crest ahead. The only `pushCourse` call site in the whole app was the Sim Watch screen's
canned three-point Boulder rectangle. Nothing a runner had ever saved could reach the watch.

The affordance went into **route detail's share menu**, beside Share link / image / GPX /
GPX+markers / KML, rather than beside the builder's Generate button. A button on the builder works
for the ten seconds after a generate and strands every loop generated yesterday, every shared GPX,
every club route; a course is just another export target for a route, and that menu is where the
export targets live.

Three things the seam had to get right, none of them transport work. It reads `_displayWaypoints` —
privacy-clipped for non-owners (§ 33) — because the radio is another way out of the app and the GPX
exporter already honours that. It meets the 256-point budget by **priority Douglas–Peucker**
(`simplifyToBudget`: keep the endpoints, restore whichever dropped point sits furthest from the chord
that replaced it, until the budget is spent), not by even decimation, which spends as much of the
budget on a straight as on a switchback. And both failure directions are doors: a thinned route says
from how many points to how many, an unrepresentable one is refused with a sentence, and nothing
truncates — a course ending at position 256 of 4,000 gives the watch a breadcrumb into nowhere *and*
an off-course alert calibrated against it, which it has no way to notice.

Gated on the loopback backend like the Sim Watch link (§ 209): there is no watch to send to yet.
Host-tested only — 10 tests on the budget simplifier, 7 on the shaping, 7 on the screen. The bytes
leaving the phone are the same `encodeCourse` output the frozen goldens pin against the firmware's,
but **that a real watch loads a real generated loop is a bench item**, on the same list as every
other radio claim. Decisions § 370.

## 2026-07-30 — the structured-workout rail gets a guard instead of a memory

`ci_smoke.py` grows an eighth scenario, `workout` ([§ 371](../architecture/decisions.md)), closing the
last major run-view rail that had no asserted one. The § 354 runner's *sim-verified* rung had been
earned on 2026-07-28 by walking the sim's demo workout **by hand** under `bench_jog` — real evidence,
and worth nothing two days later, because nothing re-ran it. A hand session certifies the afternoon
it happened; only a scenario certifies the branch.

Everything that session watched is now asserted on every PR, in the order the run produces it: the
pushed step list arms the recorder over the same `state::WORKOUT` channel a phone's `WKT1` push lands
on (`record: workout armed (5 steps)`, which is the *receive* — the queue line beside it is only the
send); the Workout page enters the BTN4 cycle and renders; the runner auto-advances **in order over
both end axes**, which the demo plan is shaped to demand (60 / 50 / 50 / 60 m distance steps around a
30 s duration recovery, so a runner that settles only one axis stalls partway and reports a short
sequence rather than a wrong one); exactly **one** end-of-step warning fires, in the recovery; a BTN5
lap press skips the active step and then completes the workout; the runner raises no sixth transition
for a five-step plan; and the finished trail flushes into the run blob with no step or summary
dropped — the loss paths are asserted *absent*, which is the only form that claim can take, since
`push_step_result`'s happy path is silent by design.

Two of those needed conditions the other scenarios do not have, and both are the § 371 record.
**The skip is timed on the firmware's virtual clock**, because its observable is the observable the
auto-advance produces for free: press BTN5 and wait for a transition, and a firmware whose press does
nothing passes — the step ends anyway. On this fixture the displaced steps need ~33 s and ~40 s to
settle (credited distance accrues at ~1.5 m/s), and the press's edge landed at **0.6 s and 0.4 s**.
Wall clock could not carry that bound: Renode's virtual clock runs at a ratio to wall time that
swings with host load, so the gap is read off the decoded stream's own timestamps, the discipline
`dropout` adopted for its void. **And the warning COUNT needs an empty alert slot**, so the session
boots `--no-alerts`: with the sim's shortened fuel / distance / time / pace arms in the single slot,
"exactly one" is a count of traffic rather than a claim about `ENDING_MIN_STEP_M` = 100 m and
`ENDING_MIN_STEP_S` = 20 s. It also keeps a fuel banner off the two page dumps, which a banner would
otherwise own.

**Verified to fail as well as pass, on both halves.** Deleting `Recorder::lap`'s `skip_step()` call
turns the skip assertion red at *30.4 s of virtual time* with the auto-advance named as the cause;
dropping `ENDING_MIN_STEP_M` from 100 m to 10 m turns the count assertion red at three warnings, and
the log then shows precisely the defect that gate's own doc comment exists to prevent — a 50 m step is
already inside the 50 m warning window when it starts, so the runner is told a step is ending 0.9 s
after it began. The wait for the skipped edge is deliberately **longer** than the step it displaces so
that the red is *useful*: the first version used a 30 s wait and failed on a bare "no line matched"
timeout, which says only that something did not arrive. Both sabotages were reverted; no firmware
behaviour moved in this batch.

CI: the `sim-scenarios` job gains a seventh step (`--budget 300`, the same as its siblings — the
unaided walk reaches the fourth transition at ~110 s of virtual time and the whole scenario measures
**2m13** on the authoring workstation), and its cap tracks the budget sum as always, 45 → 50 min.
Every assertion green in one pass locally under Renode 1.16.1.
## 2026-07-30 — Auto-lap becomes a chosen trigger, and picks its clock

The recorder's auto-lap had been a constant since 2026-07-09 — `AUTO_LAP_DISTANCE_M = 1000.0`,
the same kilometre for every runner on every run. The roadmap row counted it as built, which it
was; what it was not was a *setting*. `watch_core::auto_lap` makes it one: a closed eight-rung
catalogue (`Off`, 1/5 km, 1/5 mi, 5/10/30 min), armed by `Recorder::set_auto_lap`, defaulting to
the kilometre the recorder always had.

**Closed, not an arbitrary metre count**, and for a reason particular to this device rather than
to taste: the flash lap store holds 64 records (`run_store::MAX_STORED_LAPS`). A 1 km trigger
already loses laps past 64 km, so the coarse rungs are what keep a 100 km run's splits inside the
store, and `Off` is what lets an ultra runner spend those 64 records on splits they pick by hand.
An open "any distance" field would have let a 50 m trigger exhaust the whole budget inside 3.2 km
with nothing warning anyone. The closed set also costs exactly one byte on the wire and three bits
in flash, which is what made both of the rails below cheap.

**The auto-pause interaction is the decision worth recording** ([§ 374](../architecture/decisions.md)).
Paused time counts toward nothing on either axis. Distance is structural — it only accrues on a fix
the acceptance filter takes as movement, so a runner standing at an aid station accrues none. Time
is a *choice*: the budget is **moving** time, the axis the fuel arms already bank on (§ 214), not
the elapsed clock. An elapsed-clock auto-lap would turn a 40-minute sleep-station stop into eight
zero-distance laps at the 5-minute rung, and on a 64-record budget those empty laps *displace real
ones* — the runner loses splits they ran to laps they slept through. That deliberately differs from
§ 332's time **alert**, which banks on elapsed on purpose; the difference is that an alert costs a
banner and a lap evicts a record. The stationary case is pinned rather than argued: a test runs an
armed distance rung and an armed time rung through an hour of sub-threshold GPS jitter plus 3600
ticks and asserts the lap counter never moves.

**Two rails carry the choice.** The phone reaches it over **`SET1` v7** — both presence bytes were
saturated and v6's `KNOWN_FLAGS2 == u8::MAX` const-assert existed precisely to force this bump, so
`flags3` arrives exactly as `flags2` did at v2; `decode` accepts v3–v7 side by side (this entry originally wrote v1–v7; v1 and v2 had already been withdrawn at §403, when the CRC became mandatory) and the frozen
v6 golden vector is pinned as still decoding, its absent trigger leaving whatever the watch holds
standing rather than resetting a race's splits to a default. Flash keeps it in `CFG1`'s flags byte
behind a set-marker plus three discriminant bits — the §351/§353 drill a third time, no
config-record version bump, and bit 7 is now the last one free. The record task re-applies the
stored rung at boot, because the failure that motivates persisting it is specific: a battery pull at
hour 60 of a 100-miler would otherwise put the rest of the race silently back on 1 km laps.

The Lap page **names the armed trigger** beside the last split (`LAST 4:58    1KM`, or `OFF`). A
setting that changes what a page counts, on a page with no way to see it, reads as a broken lap
counter rather than a choice — the same honesty rule the `unfed` states are built on.

`watch_core` host suite 1851 → 1875 (+8 `auto_lap`, +9 recorder, +2 `flash_store`, +1
`settings_apply`, +4 `settings`/`face`); all three firmware feature sets build and pass
`clippy -D warnings`; `cargo fmt --check` clean. **Host-tested + build-verified only**
([§ 314](../architecture/decisions.md)) — the new rungs have had no sim pass, and nothing here has
run on silicon.

**Owed, and named rather than left implicit:** the phone-side encoder. `watch_settings.dart` still
emits the pre-v7 frame, so the trigger is on the wire and honoured by the firmware but not yet
reachable from the app — one optional field plus its golden-vector bytes, mirrored to the iOS twin.
## 2026-07-30 — Sleep-station mode: the nap the race computes, and the alarm we refused to fake

The 200-mile racer's 3 a.m. question — *how long can I sleep and still make the next cut-off* — turned
out to need almost no new arithmetic. `cutoff_eta::next_cutoff_eta` already returns
`(limit − elapsed) − (time still needed)` as its margin; that IS the nap budget before a reserve. So
`sleep_station` calls the same function once with a different pace and subtracts. The page seats
directly after `CUT` — page 38 — because the budget is that page's margin, and a runner reading
`TIGHT` should be one tap from what `TIGHT` costs them in sleep.

**The feature that got deleted by thinking about the clock.** The roadmap row asked for a nap timer,
a wake alarm, and an elapsed clock. The race clock keeps running through a pause, so a budget
recomputed each tick falls one second per second while the runner sleeps — the countdown *is* the
budget, and the honest elapsed clock is the race clock the watch already keeps. That removed the nap
timer entirely: no nap to arm, no nap state in flash, no reboot recovery, and no new edge in a press
grammar four other in-flight branches are also touching. A test pins the 1:1 fall.

**Where the honesty had to be inherited rather than invented.** `cutoff_eta` withholds its ETA on a
stale fix rather than projecting off an old position. A sleep budget is that projection minus a
reserve, so it inherits the refusal whole. Four states, not two: `NoCutoff` (nothing bounds the nap —
which is *not* "sleep freely"), `NoBudget` (computed, and the answer is none), `Unknown` (a term is
missing), `Budget`. A limit already passed resolves to `NoBudget` even with no pace, because "do not
lie down" is knowable there. And the hero keeps a measured `0` visibly apart from a refused `--`,
because a runner who reads "no time to sleep" as "the watch does not know" lies down anyway.

Every rounding leans one way, since the error is not symmetric — early costs sleep, late costs the
race. The projection takes the **slower** of the run's moving pace and its race-including-stops pace;
the budget floors to whole minutes; a sub-minute budget settles rather than displaying a `0` that
reads as a broken page. The reserve is `max(30 min, 25 % of the leg ahead)`: the floor is
`CUTOFF_TIGHT_S` reused (the product already calls that span uncomfortable, and it covers the fixed
cost of getting up), the fraction covers the error that scales with leg length. The fraction is a
judgement call and is now in the derived-not-measured register — with the note that the bench cannot
settle it either; it needs a field corpus.

**What we refused to build.** No alarm. The tier-1 BOM has no vibration motor and no buzzer, so any
arm added to `alerts` would fire silently onto a screen a sleeping runner cannot see — the appearance
of a wake without the function, which is precisely the oversleep the feature exists to prevent. Row 7
carries `WATCH CANNOT WAKE YOU` unconditionally, through the empty states too, because it describes
the device rather than the data. It is the page's most important line, not its disclaimer. The
roadmap row stays **unticked** on exactly that ground.

Page 38 moves only the linear worst (18 → 19) — both grid worsts hold at 10 and 7, and the symmetric
average 4.0541 → 4.0789, still 4.1 where `navigation.md` publishes it. What shrank is margin, not
cost: the symmetric step to 8 is still page 44, so `MAX_SCREENS` = 4 now lands one page inside it
rather than two. Recomputed by the same BFS, re-validated against the n = 32 figures the section was
built on.

The rail got an observable in the same pass, for the reason [§ 368](../architecture/decisions.md)
gave the climb one: a page dump proves a frame was drawn, never that the minutes on it are right. The
gate is the fields the LINE carries rather than the whole view — the margin ticks with the race clock
every second, so gating on the struct re-emitted a budget and a reserve that had not moved, which is
§368's own defect one page along. Twelve lines across a run instead of one a second.

Host sweep 2229 → **2258** (22 `sleep_station`, 4 `face`, 2 `record`, 1 preview); all three firmware
feature sets build and pass `clippy -D warnings`, `cargo fmt --check` clean. The `pages` scenario
re-runs green and its walk now traverses `SleepStation` directly after `CutoffEta`, so the page is
**data-present and reachable in a real cycle** — but by § 314's own rule that is not the budget being
right, and **nothing asserts the budget yet**. Host-tested; no hardware exists.

## 2026-07-30 — Countdown timer + stopwatch, and two refusals (§ 375), host-tested

The roadmap's daily-smartwatch row bundled "alarms / timer / stopwatch / find-my-phone" as one trivial item. Two of the four are trivial and are now built; the other two cannot be built honestly at tier 1, and the box stays **unticked** — nothing here is bench-verified.

**Built.** `watch_core::timers` is one instrument, not two: the preset ladder starts at zero and zero *is* the stopwatch, so there is no mode switch and no second key. Eleven rungs, all durations this repo already names (1/3/5 min aid-station turnaround, 10–90 min sleep-station nap, 60 min backyard bell). Armed from a modal on the idle face — **BTN2, the last dead key in the § 350 grammar** — with BTN1 start/stop, BTN2/BTN3 the preset ladder, BTN5 reset (refused while running), BTN4 exit on the settings menu's BACK slot. Every press swallowed, idle-only, 30 s auto-close. It survives run boundaries, and it takes the **38th** built-in page, gated on being armed. The expiry rides the *existing* alert slot as `Alert::TimerDone` at the milestone rung — dropped, never queued, and below fuel per § 214.

**The honesty decision.** No vibration motor, no buzzer: an expired countdown counts **up** past zero (`+2:14`) rather than freezing at `0:00`, because *how long ago* is the only part of a missed expiry that survives being missed. The banner reads `! TIME UP`; the word *alarm* appears nowhere on the device.

**Refused: alarms.** An alarm promises to interrupt you at a time you are not watching, and a display-only device cannot keep that promise. Re-scoped from "trivial, ship opportunistically" to a **T2 item gated on the haptic channel** — the same gate the sleep-station wedge already records.

**Refused: find-my-phone.** The watch is a GATT peripheral (§ 210 / § 211) with no watch-initiated action toward the phone, and the phone side is a pure consumer with no ring handler. It needs a new characteristic, new phone-side code and background-audio permissions, and per § 210 could never rise above build-verified without a dev kit. No stub was written. **T2, with the BLE bench work.**

**Cost, computed not guessed.** Page 38 moves neither grid worst (symmetric stays 7, stepping at 44; forward-only stays 10, stepping at 42); only the linear-walk worst grows 18 → 19. With the four composed-screen seats the full mask is 42, so the 7-press ceiling now has **one page of margin rather than two** — recorded in `navigation.md` rather than rounded away.

Workspace host sweep 2229 → 2261 (`cargo test --workspace --exclude app --exclude nrf52840_dk`; +32 — 21 in `timers`, 5 in `alerts`, 2 in `face`, 1 each in `record` / `button` / `input_flow`), plus the six count-pins the 38th page moved. Firmware builds green on the default, `ble` and sim feature sets; `fmt` and the clippy `-D warnings` gate clean. **No sim scenario and no bench evidence** — the modal has no `ci_smoke` step yet and the page cannot be armed from a fixture, so this entry claims host-tested and nothing more.

## 2026-07-30 — Backyard-ultra mode: a bell nobody's watch is anchored to

The first of the roadmap's "nobody ships these" differentiator wedges built on
the wrist ([roadmap.md § New wedges](roadmap.md#new-wedges--nobody-ships-these),
[decisions.md § 372](../architecture/decisions.md)). A backyard ultra sends the
same loop off every hour on the hour and scores on loop count; a runner must
complete the loop *and* be back in the corral before the next bell, with
whistles at 3/2/1 minutes. Nothing on a Garmin or a COROS models any of it.

`watch_core::backyard` (24 host tests) holds the whole format: the countdown
derived from the runner's **local hour boundary** rather than from a lap or a
run start, so a runner who leaves late on loop 7 gets the same bell as
everyone else; the corral state, which flips back to "on loop" on the clock
alone when the bell rings, with no event to miss; the loop length **learned
from the runner's own first loop** rather than configured on five buttons; and
the projected return margin, which is withheld outright when the loop is
unlearned or there is no live pace. It is fed the receiver's UTC clock shifted
by the pushed timezone — the same shaping the Daylight page uses — and refuses
a countdown in exactly the two cases that shaping can fail: no timezone reads
`NOT SYNCED`, no receiver clock reads `AWAITING FIX`, and the hero reads
`--:--` rather than counting to an hour boundary it cannot locate.

The loop rides the recorder's existing lap: while the mode is armed the
**corral bell drives the auto-lap in place of the 1 km boundary**, so one lap
closes per hour and the phone reads loop splits rather than six kilometre
slices of an identical loop. The runner's BTN5 press keeps its one meaning —
close a lap — and is read as the corral return, standing that window's bell
lap down. BTN5 grew no third tier. The whistles ride the existing
`AlertEngine` slot as drop-not-queue milestones one rung under the zone
ceiling. Arming is a sixth settings-menu row persisted in a spare `CFG1` flag
bit, idle-only because re-pointing the auto-lap means a run has to be wholly
inside the mode or wholly outside it; `SCR1` metric byte 35 carries the
countdown to the phone's screen composer.

**Rung: host-tested, plus build-verified for the target.** 1892 `watch_core`
tests green, `clippy -D warnings` clean on `thumbv7em-none-eabihf` across the
default, `ble` and sim feature sets. **Nothing here is sim-verified** — the
sim's NMEA fixtures carry no multi-hour clock, so no scenario can reach a bell
at all; that is the first thing owed. Bench items are in
[`quality_standards.md`](quality_standards.md).

What it deliberately does **not** do: declare a runner in or out. The corral
is the race director's and the timing mat is theirs; a watch announcing `DNF`
at hour 30 off a missed button press would be lying about the only thing that
matters. The loop count is "bells this run closed a loop on", which for a
runner still in the race is their loop count and for one who is out is the
last number the watch saw.

## 2026-07-31 — Storm detection: a barometer that can tell a front from a hill, and admits when it cannot

Built the roadmap's "Weather / storm alerts" row, which had read *baro-driven
storm detection is cheap* since the parity backlog was written. The word cheap
was hiding the whole problem.

**A falling barometer means weather; it also means climbing, and on a mountain
ultra the second signal is twenty times the first.** A front moves station
pressure a few hPa over hours. Five hundred metres of ascent moves it ~57 hPa
in forty minutes. Trending raw station pressure would have announced a storm on
every col and cleared it on every descent — a warning generated by the runner's
own legs, on a device whose stated discipline is that it never fabricates.

`watch_core::storm` trends the **sea-level reduction** instead:
`elevation::sea_level_pa` (the exact inverse of `altitude_m`, sharing its
constants) turns each reading into the sea-level-equivalent pressure it implies
at the altitude it was taken at. Climbing moves the pressure and the altitude
together and the reduced value does not move; a front moves the pressure alone
and it does. **The altitude has to be independent of the pressure**, or the
reduction returns the reference it was derived against with the weather divided
out — so the reference is the GPS receiver's, narrowed through the same
`plausible_gps` window the vert filter uses, and specifically **not** the
complementary filter's corrected altitude, whose entire job is to remove the
signal being measured. Noise is the price: ±15 m of receiver altitude is
~1.8 hPa of reduction error, paid for by five-minute buckets behind a
three-corroborated-readings floor and a least-squares slope over the whole
three-hour window rather than a difference of its endpoints.

**The refusals are the half that matters.** No corroborated GPS altitude inside
two minutes and the answer is `NO ALT REFERENCE` — not a trend off the last
good reference, and not one off raw station pressure. Under a third of the
window banked and it is `TREND BUILDING`. Both still show the absolute reduced
pressure where it is known, so a working barometer never reads as a broken one.

`BARO` is the 41st glance page (beside `SUN` — the sky's clock and the sky's
mood), the alert sits between pace and fuel in the never-dropped class, off by
default and once per front, and `SET1` bumps to **v8** to carry the threshold —
a bump nothing about the layout required, taken because a version has to name
exactly one field set for an unknown presence bit to mean anything.

**Rung: host-tested, build-verified, and sim-verified for what one scenario
names.** 2407 workspace tests green (2365 → 2407, 42 new), `clippy -D warnings` clean on
`thumbv7em-none-eabihf` across the default, `ble` and sim feature sets. The new
`storm` Renode scenario ramps the BMP581 model's **sea-level reference** while
its altitude stays put — a weather change, not a movement one — and asserts the
tracker's own defmt line: the refusal before the window fills, a still
atmosphere reading `Steady` inside 0.5 hPa, `Storm` past the armed threshold
once a full window of the front is banked, exactly one banner for it, and the
page in the cycle rendering. It was **verified to fail as well as pass**: with
the tracker mutated to take the baro-derived altitude — the circularity the
whole module is built around avoiding — the still atmosphere reads a
suspiciously exact `+0.00 hPa` at the ISA reference and the front never arrives.

What no simulator here can settle: the climb-versus-front separation itself.
The firmware's altitude reference comes from the NMEA fixture, which the harness
cannot ramp independently of the barometer, so an in-sim "climb" is a baro ramp
against a flat GPS altitude — which *is* weather as far as any correct
implementation can tell. That separation stays host-tested. The 3 h window and
the 4 hPa threshold are **chosen, not measured**, and join the register in
[`quality_standards.md`](quality_standards.md); a runner-tunable threshold was
deliberately not exposed, because tuning a number whose centre nobody has
validated is guessing twice. § 82 is unchanged: nothing here has run on silicon.

## 2026-07-31 — the privacy posture, and the two things it turned out not to be

The roadmap had carried one line for months: the watch records GPS, HR and
biometrics, and "inherits nothing yet" from a product that takes minimisation,
retention and export seriously. Reading it against the code showed that
sentence was wrong in both directions, which is why this entry exists and why
the fix was mostly a document ([`privacy.md`](privacy.md),
[decisions § 377](../architecture/decisions.md)).

**Three disciplines were already inherited and simply never written down.** The
GATT data plane has been fail-closed against unpaired peers since § 285 — all
seven characteristics require an encrypted link, so a run track never crosses an
unbonded connection. The ICE card's exposure is bounded to the physical wrist by
construction: a display face, not a characteristic, absent from the run blob,
and with a hand-written `defmt::Format` that prints `blank`/`set` and never a
field. And a synced run inherits Art 20 export, Art 17 deletion and privacy-zone
clipping **for free**, because `runFromWatchPayload` → `api.saveRun` lands it as
an ordinary `runs` row — no new table, so the export guard already covers it and
`delete-account`'s bucket drain already reaches it.

**`privacy.rs` having zero callers is the right answer, not the outstanding
work.** § 33 makes clipping read-time and viewer-keyed *because* a write-time
clip is destructive — turn a zone off later and the eaten trace is gone — so the
durable track is stored raw and clipped only for a non-owner. The watch's only
egress is to the single phone it is bonded to, its owner's; clipping there would
mutilate the run before its owner ever saw it, and the device has no zone
transport anyway (`WatchSettings` carries no zone list). The port stays dormant
against a named trigger: tier-2 live spectator tracking, where forwarding
`link::status_frame` makes the watch the **source** of a broadcast to
non-owners, and § 33's `live_run_pings` precedent says a broadcast drops in-zone
fixes at the source because a downstream filter cannot unsend.

**The real leak was the log stream.** `gps.rs` logged lat/lon on every published
fix — one line per fix is a complete track of the wearer — `hr.rs` logged raw
bpm change-gated, which is a biometric time series, and `hr_strap.rs` logged the
strap's BLE address, a stable identifier that follows one person between
sessions. None of that is private: a defmt stream goes wherever the cable, the
CI artifact or the bug report goes, and the repo's own `/audit/pii-in-logs`
sweep treats exactly this class as a real finding for its server tiers while
never having covered this firmware. A stock build now logs fix quality (speed,
satellites) and pulse presence; the values sit behind `log-personal-data`,
default off. `bin/watch-sim.sh` turns it on and nothing else does — the sim's
coordinates are the synthetic `bench_jog` rectangle with nobody behind them, and
`sim/ci_smoke.py` asserts on the logged fix and BPM, so the sim-verified rails
were left intact rather than weakened to fit the fix. The bench build keeps it
off; `bin/watch-flash.sh` forwards cargo args, so seeing your own coordinates is
an explicit opt-in.

**Rung: build-verified.** `clippy -D warnings` clean on
`thumbv7em-none-eabihf` across the default, sim, `ble` and
`ble,log-personal-data` feature sets; `cargo fmt --all --check` clean; 2365 host
tests unchanged, the change being confined to `app/`, which host tests exclude.
Nothing here is bench-verified — no hardware exists — and per § 210 the BLE
encryption this posture leans on can never be sim-verified either.

**What it does not claim.** This is a research prototype with zero users. The
document is an inventory and a set of rules, not a compliance posture. Retention
on the device is still a *capacity* bound and not a clock (four run slots, eight
waypoints, newest-wins), nothing is encrypted at rest, and the largest gap is
recorded rather than closed: **no wearer can erase their own data from the
watch.** The primitives exist, but the affordance is a settings-menu row plus a
destructive-action confirm, which moves the published press-cost model — a
navigation change as much as a privacy one, and owed in that lane.

## 2026-07-31 — the phone catches up: `SET1` v6 → v8, and the two fields that were only ever half-built

Two firmware versions had shipped with the phone's encoder standing still. `settings.rs` was
at **v8**; `watch_settings.dart` was at **v6**. That is not a cosmetic lag — it is the difference
between a feature existing and a feature being reachable. The § 374 auto-lap trigger and the § 376
storm-alert threshold were both on the wire, both decoded, both honoured by the recorder and the
alert engine, and neither could be set by anything a runner touches. Both ADRs said so in their own
"still owed" lines; this entry closes both.

**Nothing about the format was designed here — it was mirrored.** `settings.rs` is the authority and
the Dart side is a port, so the work was reading it exactly: the third presence byte `flags3` in the
header (every v8 frame carries all three, even all-zero), the auto-lap rung as one raw byte on bit 0,
the storm threshold as a `u16` of **tenths** of a hectopascal on bit 1, both after the 92-byte ICE
card, then the CRC32 over everything before it. A fully-populated push is now **196 bytes** — four
more than v6, still one write inside the 256-byte ATT MTU, ~60 bytes of headroom left rather than
~64.

**Two shapes had to be chosen rather than copied, and both followed precedent already in the file.**
The trigger is a `WatchAutoLap` enum whose declaration order IS its wire discriminant, which is the
`WatchRacePhasePreset` drill from v4 and carries the same warning: reordering it re-points every
trigger a phone has already pushed. The threshold is where the two languages genuinely differ —
Rust models it as `Option<Option<f32>>`, an absent field versus a present disarm versus a present
arm, and Dart has no second layer of optionality to spend on it. It flattens to a nullable `double`
over a zero sentinel, exactly as `distanceIntervalM` and `timeIntervalS` already do: null leaves the
watch's threshold standing, `0` disarms the banner, positive arms it. The one guard that had to be
carried across by hand is the floor: an armed threshold rounds up to at least one tenth, because a
value small enough to round to zero would arrive as the **disarm** and there would be nothing left
downstream to reject it — arm silently becoming off, which is the failure mode a fail-closed decoder
cannot catch.

**The version byte stays a constant, and that is the whole of the v8-discipline mirror.** § 376 spent
a version bump `flags3`'s six free bits did not require, because an unknown presence bit is how
`decode` tells a corrupt push from a newer one, and that only holds while a version names exactly one
field set — so a v7-stamped frame carrying the v8 bit is refused whole. The phone's half of that
contract is simply that it never derives the stamp from which fields happen to be set. A test walks
an empty frame, a v1-field frame, a v7-field frame and a v8-field frame and asserts byte 4 is `0x08`
on all four: the phone cannot construct the frame the watch refuses.

**Evidence.** Five golden vectors are byte-identical to the firmware's own `settings.rs` tests — the
fully-populated 196-byte frame (which carries both new fields at their real offsets, `0x02` for the
`1MI` rung and `0x2800` for 4.0 hPa, under CRC `1c26d5df`) plus the v4-arms, resting-HR, ICE and
timezone vectors, each of which moved when the header grew. The remaining 37 are Dart-side and were
re-derived through the same CRC-32 the run-sync path already shares with `run_store`; every one of
them is additionally checked *as* a checksum rather than only as a literal. `watch_settings_test.dart`
goes 32 → 38 tests, mirrored byte-identically to the iOS twin per § 39.

**Reachability, and one thing that deliberately did not get built.** The only push surface is the
dev-only Sim Watch screen (§ 209), and its demo frame now carries both fields — the `1MI` rung and
the 4 hPa storm centre — so the bench has something to measure against the day the parts arrive.
That is **not** the runner-facing threshold control § 376 refused, and it should not be read as one:
§ 376's argument was that letting a runner tune a number whose centre nobody has validated is
guessing twice, and that still stands. A fixed dev value on a screen with no product surface is the
opposite claim — it exists so the constant can eventually be *checked*.

**Rung: host-tested, and not by us.** The Dart suite is CI's to run — this workstation OOMs on
`flutter test`, and no test run backs this entry locally. What was verified here is narrower and
worth stating precisely: the golden bytes were computed by an independent encoder and validated
against five Rust vectors it had no part in producing, and twin parity was checked with `diff -rq`.
No Rust changed. Nothing here has executed on silicon; § 82 is untouched.

## 2026-07-31 — A factory erase, on the settings menu's second far seat

**Decision:** [§ 378](../architecture/decisions.md). **Closes** the gap the
2026-07-31 privacy entry above left open and named as the largest on the page:
no wearer could erase their own data from the device. There was no factory
reset, no clear-all-runs, no wipe; `Waypoints::clear()` had zero callers; the
ICE card could only be cleared by a *phone* push, and the run slots and the BLE
bond could not be cleared at all. A lost, stolen or handed-on watch could not be
sanitised by the person who had been wearing it.

**The seat was computed, not chosen.** § 351's budget is that no row a runner
reaches for *mid-race* costs more than 4 presses, and `navigation.md` predicted
a seventh row would break it. It does not, and the reason is worth keeping: the
prediction assumed **appending**. A wrapping ring's cursor distance to index `k`
is `min(k, n-k)`, so a 6-ring has one far seat at 3 and a 7-ring has **two**
(`[0,1,2,3,3,2,1]`). FACTORY ERASE went in at index 4 — the second far seat —
and every pre-existing row keeps its exact cost, verified by a test that
computes both rings from `ITEMS` rather than restating them. Appending at index
6 would have cost RE-ZERO and MEDICAL ID a press each *and* put the wipe on the
cheapest seat on the ring, one BTN2 press from the cursor's home. The far seat
is where a wipe belongs on both grounds. The published press-cost table was
re-derived rather than adjusted: the § 289 BFS was first reproduced against
`navigation.md`'s own anchors (n = 32 → 16 / 8.0, 9 / 4.7188, 6 / 3.7188;
n = 41 → 20 / 10.2439, 10 / 5.6585, 7 / 4.2927; n = 45 → 22 / 11.2444,
11 / 6.0667, 8 / 4.5778, all matching to the published digit) to confirm the
model, and it does **not** move — a settings row is not a page.

**The layout change § 372 predicted did happen.** Six rows filled the nine-row
panel exactly, so `MENU_TOP_ROW` moved 3 → 2 and the blank spacer under the
title is gone. That was the last slack: an eighth row needs § 333's
row-scrolling window ported from the grid, which is stated in `navigation.md`
so the next person reads a design rather than rediscovering a wall.

**The confirm is the stop guard's, and a hold was refused.** `EraseGuard` is
`StopGuard`'s shape and shares its 4 s window, so the device has one learned
dwell for its two irreversible actions. Hold-to-confirm — the other
guarded-destructive idiom here — is unavailable: *idle gestures are
duration-stable* is a pinned navigation invariant, and a duration split inside
an idle modal would be the first gesture to break it (§ 375 declined the same
split for the same reason). Right arms, a second right inside the window wipes,
**everything else cancels** — a cursor step, a left press, the exit, the menu
closing, the window lapsing. The arm borrows the menu's single deadline slot
while live, so it lapses visibly back to `FACTORY ERASE` rather than standing as
a prompt for a press that would now only re-arm.

**What it takes.** The four run slots, the eight waypoints, the config record,
the composed screens, the ICE card, the BLE bond, the pushed course and workout,
the trackback breadcrumb, and the recorder's pushed biometrics / pacer goal /
gear / roadbook / fuel plan / page mask / auto-lap rung / backyard arm. The two
arguable ones are argued in § 378 and tabulated in
[`privacy.md`](privacy.md#the-erase--378): the **ICE card** goes because it is
the only third-party personal data on the device (a next-of-kin who never
consented to the next holder) and is re-pushable in one action, and the **bond**
goes because it is a live credential whose IRK defeats the previous owner's
address privacy permanently — a watch that keeps it lets the old phone read the
new owner's runs. The timezone offset deliberately stays (not personal,
RAM-only, and the channel has no propagating "unset", so writing `0` would make
the home clock claim `LOCAL` while showing UTC).

**It erases bytes, not directory entries** — `SlotDir::forget` would satisfy
every reader in this firmware while leaving the blobs where they were written,
and the adversary here is whoever holds the device next, with no APPROTECT
between them and a probe. Both halves follow the same rule: the flash side
erases a *range* (`plan_factory_erase`, one contiguous span whose test checks
every published record offset and every slot against it), and the RAM side
replaces the `Recorder` whole. **Erase by default, not by allowlist** — a
personal field added to either side next year is covered without anyone
remembering to extend a list.

**Rung: host-tested + sim-verified, in named parts.** 11 new host tests, 2407 →
2418 passed / 0 failed on `bin/watch-test.sh`. `cargo fmt --all --check` clean;
`clippy -D warnings` clean for `thumbv7em-none-eabihf` on the workspace default,
`-p app --no-default-features --features ble`, and the
`sim-autostart,sim-alerts,sim-buttons,sim-course,dev-blink` set. The `idle`
Renode scenario (`sim/ci_smoke.py --scenario idle --budget 400`, 12/12 green)
walks the row into the cycle, asserts one press **arms and changes the panel**,
asserts stepping off the row and back leaves the next press arming again rather
than confirming, and only then confirms — after which the GNSS mode falls back
from the `Expedition ~220h` the scenario itself walked the ladder to, down to
`Performance 1s ~110h`.

**What is NOT verified, and it is the half that matters.** Renode's flash is
plain memory behind an SVD-derived NVMC model that answers `READY` and swallows
the `ERASEPAGE` write, so the firmware reports a success over an emulator that
changed no byte. That four run slots and a config page actually read back
`0xFF`, and that a previously paired phone really has to re-pair, are **bench**
items — added to [`quality_standards.md`](quality_standards.md) step 7 with a
read-the-flash-back pass criterion, because "the manifest is empty" is what a
directory drop also produces and is exactly the distinction this erase exists to
make. The bond half can never be sim-verified at all (§ 210). Nothing here is
bench-verified, because no hardware exists.

## 2026-08-17 — the parts list audited against the firmware, before a penny was spent

Triggered by a plain question — are we ready to order? — and the answer was no, for
reasons none of which were visible from either document alone. The list and the
firmware had been drifting past each other for months because nothing ever compared
them: every row was individually plausible, and five were wrong about the part the
code actually drives.

**The barometer was the clean case.** `parts.md` ordered a **BMP390** while
`drivers/bmp581` gates on `CHIP_ID == 0x50` at register `0x01`; a BMP390 answers
`0x60` at `0x00` with an unrelated map. § 90 had codified the swap for the
*production* target only, tier-1 firmware implemented BMP581 anyway, and the shopping
list stayed where § 90 left it. The failure would have been silent — a failed probe
parks the baro task, taking elevation, vert, the storm page and the GAP grade with it,
and presenting as four unrelated dead features.

**The GNSS link would not have carried a byte.** `main.rs` had configured UARTE0 at
9600 since bring-up. That is the u-blox **M8** default; the MAX-M10S is M10 and ships
at **38400**, which SparkFun's guide for this exact breakout states outright. No
decision had ever set 9600 — it was an inherited assumption, and § 419/§ 421 had since
built derivations on top of it. Fixed by meeting the part rather than configuring it
([§ 622](../architecture/decisions.md)): the breakout's backup cell holds a u-center
setting about a fortnight, so a configured baud is a value with an expiry date, and the
prototype that sat out a holiday would have come back mute with nobody suspecting a
setting they touched once. Two derived figures moved with it, and **the second is the
one worth having caught**: `BufferedUarte`'s guaranteed headroom is `half_len`, so the
512-byte ring § 421 is holding open covered three 85 ms erases at 9600 and covers
**none** at 38400. It needs to be 2048. A later implementer would have built the fix to
a spec that stopped being right.

**Three more that each cost a bench day rather than a subsystem.** The BMP581 breakout
ships on **0x47** against the driver's **0x46** (one jumper). The display's silkscreen
calls EXTMODE `EIN` and EXTCOMIN `EMD`, and `DISP` needs no MCU pin — which is why the
board crate has none, a coincidence that reads as a bug until you know. And the DK
supplies from a Li-Po but does not **charge** one, so the "percent falls monotonically
across a discharge" bench item had no charger on the list and was a one-shot. Sundries
too: the SKU was `GPS-21086` for a board that is `GPS-18037`, `prototyping.md` named the
obsolete 96×96 `LS013B4DN04` against a framebuffer that hard-codes 168×144, and the
chassis and strap that § 82's on-a-real-wrist DoD requires sat filed under
nice-to-have.

**The finding that actually matters is the optical HR, and it is a doc-process failure
rather than a doc error.** [`vendor_research.md`](vendor_research.md) established on
2026-07-09 that **no public MAX86177 datasheet exists** — ADI gates it behind an NDA —
and closed by asking for a note on `roadmap.md` step 5 and the `bom.md` HR row, marking
those edits as the parent session's job. The parent session never did them. So the
finding sat in one file while three others kept describing the part as ready to wire,
and the driver written afterwards inherited exactly the predicted gap: `drivers/max86177`
carries a register map **modelled on the MAX86171 family idiom, not read off this
part's datasheet**, and says nothing about it. Procurement has moved underneath the
research since: `MAX86177EVSYS#` is discontinued at Digi-Key with no lead time and is a
two-board evaluation *system* rather than a breakout, and the MAX86171 fallback the
research recommended has an EV kit that is **obsolete and no longer manufactured**.

The framing that resolves it is that the MAX86177 is a *production* pick that got
imported into tier 1. § 82 asks for a run recording HR and explicitly accepts "raw
photodiode reads + naive peak-detect"; it does not ask for the launch AFE. So a ~$20
MAX30101-class part with a fully public register map is the tier-1-appropriate choice,
not a compromise — and everything above the raw sample (`peak_detect`, the AGC, the
contact classes, the duty-cycle schedule, the `hr` task seam) is part-agnostic and
survives whichever way it goes. The register map is the only half that does not. The
three costed options live in [`parts.md`](parts.md); the decision is owed before that
line can be ordered, and the other ~$700 should not wait for it.

**Rung: build-verified, and deliberately not more.** `bin/watch-test.sh` 2739 passed /
0 failed, `cargo fmt --all --check` clean, `clippy -D warnings` clean for
`thumbv7em-none-eabihf`. Nothing here is sim-verifiable — Renode delivers the NMEA
fixture over a PTY and its UARTE model does not rate-limit against the baud register,
so the sim is exactly as green at 38400 as it was at 9600 and proves nothing about
either. The baud is now a step-3 bench item alongside the four step-0 gates this entry
added.

**The process lesson, which is the part worth keeping.** A cross-check nobody owns does
not happen. `parts.md` was audited against `bom.md` (§ 90) and `vendor_research.md` was
audited against the vendors, but no document's job was to check the shopping list
against the code that drives the parts — so the two drifted for months while each stayed
internally consistent. The same shape produced the NDA gap: a research doc that ends by
assigning follow-through to "the parent session" has assigned it to nobody. Both are now
`parts.md`'s stated job, in its own opening lines.

## 2026-08-17 (same day) — the HR part decided: a $20 commodity sensor over the $130 one nobody can document

The open line from the audit above, closed ([§ 623](../architecture/decisions.md)). Tier
1 orders a **MAX30101** breakout; § 90's production MAX86177 row is untouched, and
`drivers/max86177` stays in the tree as the head start on it rather than being deleted.

**The wavelength nearly went wrong, which is worth recording because it was one word.**
The option was drafted as "a MAX30101 / MAX30102 breakout" as though the two were
interchangeable. They are not: the MAX30102 carries red and IR only — a fingertip-SpO2
part — and the **green** LED the MAX30101 adds is the wavelength every wrist-worn optical
sensor uses, because green is absorbed strongly by haemoglobin and penetrates shallowly
enough to read a capillary bed through a moving wrist. A device whose entire premise is
the wrist would have been ordered with no wrist wavelength, and the failure would have
looked like a bad peak detector.

**The upside that comes with leaving the NDA part behind** is that the board vendor
stops mattering. The MAX30101 register map is public and identical whoever assembles the
module, so the fact that SparkFun's `SEN-16474` is on backorder and Pimoroni's `PIM438`
reads 0 at Digi-Key (still *Active*, stocked direct) is an inconvenience rather than a
blocker — a generic module answers the same registers. Compare where the MAX86177 left
us: one discontinued kit as the only route to a part whose documentation was also gated.

**And a correction to the audit entry above, made the same day it was written.** It
claimed everything above the raw sample "is part-agnostic and survives the choice". True
of the logic, false of the packaging — `peak_detect` (374 lines) and the LED AGC are
modules of the **`max86177` crate**, and `hr.rs` imports them from there while calling a
concrete `Max86177` rather than a trait. So the port is not "write a second driver": it
is **lift the shared half out first** (to `watch_core` or a `ppg` crate), then a thin
`max30101` register driver under it, then point `hr.rs` at the abstraction. Done in the
other order it forks the peak detector, and two detectors is two things to tune against
one wrist. Three concrete deltas go with it: an **18-bit** saturation ceiling rather than
19, ambient sampling through **multi-LED slots** rather than the MEAS1/MEAS2 tag pair,
and a register-retention-across-shutdown question that § 623 **re-opens rather than
inherits** — it was logged against different silicon.

Nothing is built yet. The step-5 bench items now describe a part the bench will have and
a driver that does not exist; that gap is stated in [`roadmap.md`](roadmap.md) and in
step 0 of [`quality_standards.md`](quality_standards.md) rather than left for someone to
discover with a sensor in their hand.

## 2026-08-17 (third) — the driver lift, and the two bugs that only appeared once something else had to use the same code

§ 623's owed firmware work, done in the order the decision insisted on: **lift first, then
write the second driver.** The reverse order is what forks a peak detector, and a forked
detector is two things to tune against one wrist.

**The lift.** `peak_detect` (374 lines) and the LED AGC moved out of the `max86177` crate
into `watch_core::ppg`, joined by a `PpgAfe` trait. `hr.rs` now names a part exactly once —
at construction — and asks it for its ADC scale, auto-gain window, LED seed and slot tags.
All 30 detector tests passed untouched, which is the point: nothing about the logic
changed, only where it lives and who may use it.

**What the lift exposed, and it was not in the plan.** The detector's four DC thresholds
are quoted in *photodiode counts*, and a count means nothing without the converter's full
scale behind it. They were 19-bit numbers with nothing saying so. An 18-bit part reports
half the counts for the identical optical scene, so porting them across unchanged would
have made every contact and rail threshold **twice as strict** on the new AFE — a wrist
reading as off-wrist, and no test anywhere would have failed. `PpgScale` now carries the
width and derives the bounds; `BITS_19` stays literal so the existing suite pins exactly
what it always pinned, and `scaled_to` is the only thing that ever moves a number. Three
tests pin the relationship, including the invariant that actually matters — the auto-gain
loop must shed LED drive *before* the detector declares a rail, checked at both widths
rather than argued from proportionality.

**The driver.** `drivers/max30101`: public register map, green LED on slot 1 (the wrist
wavelength — a MAX30102 has none and answers on the same address), LED-off ambient on
slot 2, 18-bit counts. The parenthesis above originally ended "and is refused on its
`PART_ID` before a single register is written", which was wrong: the whole MAX3010x
family reports `0x15`. Corrected on 2026-08-17 — see the entry below and
[§ 625](../architecture/decisions.md).

Its design problem is that **this FIFO is positional**. The MAX86177 tags each word; the
MAX30101 writes one sample per enabled slot in slot order and labels nothing, so the tag
is assigned from read position — and a single sample read out of step transposes PPG and
ambient *for the rest of the window*. Nothing downstream can detect that: `hr_drain`
demuxes on the tag it is handed, and a transposed stream yields a plausible wrong heart
rate. Two guards, both tested: reads are whole frames (a FIFO holding half a frame yields
nothing rather than its first sample), and phase is re-derived on every flush rather than
carried across a duty-cycle window.

**Then the Renode model found the second bug, which is the part worth recording.** The
model was going to be a straight adaptation until the FIFO ring was modelled *honestly* —
real write/read pointers and a real overflow counter instead of a queue. That made the
overflow case reachable, and the driver had no answer for it: an overflow drops samples,
an **odd** number of dropped samples slips slot phase exactly as a partial read would, and
`OVF_COUNTER` saturates so the parity is unrecoverable. The whole-frame guard does not
help — every frame after the drop is whole *and* transposed. `refill_frame` now flushes
and re-derives alignment, trading a fraction of a second of pulse for not reporting a
confident wrong number, and the test pins that it clears the counter too (leaving it set
would re-trigger forever). The mock needed the same honesty to make that test mean
anything: it had been ignoring the pointer writes it was supposed to be flushed by.

The general lesson is the one this whole day keeps repeating: **a model that agrees with
the driver's belief cannot detect a wrong belief** — `quality_standards.md` already says
that about the sensor models, and here it was the model getting *less* agreeable that
found the defect.

**Rung: host-tested + sim-verified.** Workspace host sweep 2739 -> 2755 passed / 0 failed
(3 scale invariants, 12 driver, 1 overflow);
`cargo fmt --all --check` clean, `clippy -D warnings` clean for `thumbv7em-none-eabihf` on
the workspace default and the sim feature set. **All nine Renode scenarios green** (smoke,
alerts, pages, terrain, dropout, screens, idle, workout, storm), with `smoke` reading
**70 BPM** off the new model (band 55-95 against a synthesised ~72.3) — and because the
model's FIFO is untagged, that assertion now covers the driver's positional tagging as
well: a phase slip feeds ambient counts in as PPG and no plausible BPM survives it.
Nothing here is
bench-verified; no hardware exists. The part checks, the register values, and the
overflow behaviour are all datasheet-derived and await silicon.

## 2026-08-17 (fourth) — the part check that never checked anything

A verification pass over [`parts.md`](parts.md) before ordering, against both the firmware
and the vendors, turned up a claim this repo had asserted in five places and never tested:
that `drivers/max30101` refuses a MAX30102 on its `PART_ID`. **It does not.** The MAX30101,
MAX30102 and MAX30105 all report `0x15` — the register names the family, not the die. The
same pass found the mirror-image error in the same paragraph: the list said a MAX30105
would be *refused* until its id was added, when in fact it passes and should.

The gap mattered because § 623 chose this part partly for being a commodity, the market for
these modules is dominated by the wrong one, and the two boards are visually near-identical
— so the procurement advice was leaning on a backstop that was not there.

**What the wrong part would actually have done, since the old comment overstated it.** Not a
confident wrong pulse: slot 1 selects LED3, a MAX30102 has none, so both slots read ambient,
the corrected DC collapses and `PeakDetector::contact` refuses it. The cost would have been a
bench day chasing strap pressure and light barriers — step 5 warns that is the hard part — for
a fault that was never mechanical. Full reasoning, including the one narrow path to a genuinely
wrong number, in [§ 625](../architecture/decisions.md).

**The fix, in the order § 625 argues for.** `init` now checks the green channel by capability:
write `LED3_PA`, read it back, refuse before the mode write so nothing streams. That is a
better test than the id even ignoring the family problem — it catches a broken LED3 line or a
cold joint too, which on a hand-wired breadboard is not a hypothetical. Because reserved-register
behaviour is unspecified, `watch_core::ppg::EmitterCheck` backstops it optically: full drive, a
lit diode, no reflected DC, sustained ten auto-gain ticks, and the task says so once. It reports
rather than gates — the contact floor was already withholding the reading, so what was missing
was the reason.

17 host tests on the driver (5 new, including one that pins the shared part id so the premise
cannot be forgotten again) and 8 new on `EmitterCheck`, covering both directions and the two
scenes that must never accuse the hardware. Firmware builds, CI clippy clean.

Still not bench-verified, and one item is now owed that was not before: step 5 opens with a
**negative control** — force the LED drive to zero and watch the new line fire — because a
guard nobody has seen fire is a guard nobody knows works.

## 2026-08-19 — The GPS link gets DMA depth, and the simulator gets the UARTE event provider it was missing

`gps.rs` had re-armed one 32-byte EasyDMA read since GNSS bring-up, which fills in 8.3 ms at
the factory 38400 baud and then leaves the receiver disarmed until a task runs again — while an
NVMC page erase halts the CPU for ~85 ms and cannot be divided ([§ 419](../architecture/decisions.md)).
Up to 326 bytes of NMEA per checkpoint, which is an L4 flash write degrading L1 distance. The
receiver now runs on `BufferedUarte`, whose ENDRX -> STARTRX PPI chain keeps the next transfer
armed in hardware across the stall. The ring is **2048 bytes**, derived rather than picked: the
guaranteed headroom is `half_len`, so 1024 B = 267 ms at this baud against an 85 ms erase, where
the 512 bytes the earlier notes specified buys 66.7 ms and covers none — a sizing that was right
at 9600 and wrong by 4x after [§ 622](../architecture/decisions.md). The peripherals it needs
(TIMER2, PPI channels 2/3, PPI group 0) are claimed in the board crate beside UARTE1's TIMER1 +
PPI 0/1, all of it outside the S140's TIMER0 / PPI 17-31 / group 4-5 reservations, and the board
crate's header now carries the whole budget.

**The interesting half is that [§ 421](../architecture/decisions.md)'s timer model turned out to
be necessary and not sufficient, and only running it showed that.** With SHORTS in place the swap
delivered not one byte and the guest died at ~16 s. Renode's PPI resolves an event endpoint by
casting the owning peripheral to `INRFEventProvider`, and v1.16.1's `NRF52840_UART` does not
implement it, so every PPI channel sourced from a UARTE event was refused at configuration time
with an error in `renode.log` that nothing had ever read. Both of `BufferedUarte`'s UARTE chains
are exactly that. The same error is present in a run of unmodified `main` for UARTE1 — so
§ 420's hardware idle-line chain has never fired under the simulator either, and the software gap
timeout was carrying the settings pipe alone. `sim/NRF52840_UARTE_Events.cs` closes it with
upstream's own event-provider delta, plus one fix: v1.16.1 never disarms the receiver at
RXD.MAXCNT, so once the guest clears ENDRX the RX pointer walks past the driver's buffer without
limit. That is what killed the first attempt, and it presented as `RefCell already borrowed`
inside `embassy_sync::watch` — **issue #713's signature**, reproduced deterministically for the
first time. Not a diagnosis of #713, but the first mechanism candidate that comes with a
reproduction.

Evidence: workspace host tests unchanged and green; all three feature sets build clippy-clean for
`thumbv7em-none-eabihf`; **all nine Renode scenarios pass**, including `smoke`, `dropout` and
`workout` — the three that drive this code path hardest. Bench-verified: nothing. Renode models no
NVMC at all, so the stall the ring is sized against has never been produced; the step-7 item in
[`quality_standards.md`](quality_standards.md) keeps its pass criterion and changes only its
expectation, from up to 326 bytes lost to zero. See [§ 698](../architecture/decisions.md).

## 2026-09-02 — the parity ports are re-measured against their sources, and five had drifted

No new capability, no new page. Roughly half of `watch_core` is a one-way faithful
port of a shipped web helper, and nothing in the repo detects a port whose source
has moved since it was taken. This entry is the first time that was measured
rather than reasoned about: for every `core/src/<m>.rs` with a same-named
`apps/web/src/lib/**/<m>.ts`, compare the last commit date on each side. Forty-nine
modules pair up; on sixteen the web source moved after the port was last touched.

Five of the sixteen carried a real divergence and were fixed
([decisions § 900](../architecture/decisions.md) through
[§ 903](../architecture/decisions.md)):

- `route_geometry` ranked candidate segments by a perpendicular measured inside
  each segment's own planar frame, so 1 cm of sideways jitter moved the answer
  3474.8 m onto the wrong limb of a 3.47 km out-and-back; and a non-finite fix
  came back as `Some(0.0)`, which is the start of the course, not an unknown
  position.
- The four § 468 antimeridian sites that exist here — `route_geometry`'s two,
  `route_simplify`'s RDP perpendicular and equirectangular leg (one 0.06° leg
  measured 40,023 km), and `track_projection`'s and `run_heatmap`'s bounding
  boxes (359.99° spans). § 463 left the ports carrying the bug because web
  carried it too; § 468 fixed web and the reason expired with nothing recording
  the dependency.
- `run_stats::elevation_gain_metres` paired adjacent points, so one missing
  sample in the middle of a climb lost the whole climb. The live `VertAccumulator`
  was checked and is a different mechanism — it holds its reference across a
  dropped sample — so this is a port defect, not a vert defect on the device.
- The shared haversine returned NaN for a near-antipodal pair; clamped rather
  than re-expressed as `asin`, so no pinned `course` figure moves.
- `locale_defaults`' Sunday-first region table was the hand-written 16-region
  list, wrong for 19 regions against CLDR, under a doc comment claiming it agreed
  with `Intl`.

Evidence: `watch_core` host suite 2351 → 2367, whole workspace green; the whole
workspace builds for `thumbv7em-none-eabihf` and `clippy -D warnings` passes;
`cargo fmt --check` clean; `check_watch_doc_counts.mjs` and
`check_watch_wire_vectors.mjs` both green. Nine of the sixteen new cases were
confirmed to fail against the arithmetic they replace before the fix landed.
**Sim-verified: nothing** — no Renode fixture carries a course or a track near
180°, and none of these modules has a glance page to dump. **Bench-verified:
nothing.** None of the five modules has a consumer on the wrist today; this is
port fidelity, and reporting any of it as a device defect would be false. The
remaining eleven of the sixteen are filed with their measurement in
[`followups.md`](../product/followups.md). § 82 unchanged.

## Next entry expected

Parts order + first flash (blink on the real DK) — see [`parts.md`](parts.md), now fully
specified, with every line's driver written. That entry starts the photo record.
