# Roadmap — custom_watch

The big-picture sequencing for the ultra-marathon watch research effort. Separate from the main app's [`docs/product/roadmap.md`](../product/roadmap.md) because the watch has its own multi-tier hardware-investment sequence that doesn't map onto the main app's phased product roadmap. Read alongside [`competitive_landscape.md`](competitive_landscape.md) (strategic framing), [`prototyping.md`](prototyping.md) (the three cost tiers), and [`decisions.md § 71 / § 80 / § 81`](../architecture/decisions.md) for the locked decisions.

**This doc is live.** Update the per-tier checkboxes + status snapshot as work progresses; resolve open questions into `decisions.md` entries as they're decided.

## Status snapshot (2026-07-09)

- **Long-term goal: [§ 92](../architecture/decisions.md#92-custom-watch-decisions-optimise-for-tier-3-production-quality-period--scope-and-effort-are-not-constraints) — build the best watch ever** (full Phase 0–5 optimal-road timeline in § 92's table). Tier-2+ decisions optimise for the tier-3 shipped product without effort or scope as valid counter-arguments.
- **Tier 1 (bench prototype)**: all bring-up steps 3–7 are **code-done** — steps 3–5 and step 7's recording core are sim-verified on Renode (2026-07-08), step 6 (BLE) + the run-sync BLE leg are compile-and-link-verified only (the sim can't run the SoftDevice) — but **no parts ordered and no on-board verification yet**; bench verification of everything pends the dev kit. Milestone history in [`tier1_log.md`](tier1_log.md); per-step detail in [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md). **Stays on nRF52840 per [§ 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)** — deliberate first-prototype compromise per the [§ 92 Resolution](../architecture/decisions.md#resolution-2026-05-28--hybrid--92-long-term-goal---80-tier-1-preserved-as-deliberate-first-prototype-compromise) ("keep costs down and get a working version first").
- **Tier 2 (wearable prototype)**: gated on the three [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) triggers; not active. Migrates to Apollo510B silicon per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified); MCUboot lands per [§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default); ANT+ Alliance per [§ 88](../architecture/decisions.md#88-vendor-engagement-is-tiered-across-project-maturity) Layer 3.
- **Tier 3 (production-intent unit)**: gated on same triggers; not active. The full Phase 0–5 vision per § 92.
- **Vector 1 (Connect IQ app)**: not started — runs parallel to tier-1 per [§ 87](../architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware).
- **Vector 2 (Wear OS app)**: `apps/watch_wear/` ships product features but isn't framed as a "Garmin alternative for sub-12hr runners" play.
- **Vector 3 (ODM partnership)**: no vendor conversations; no outreach.
- **Feature parity:** the software feature surface an ultra runner expects from a Garmin / COROS flagship — recording, navigation, training metrics, safety — is enumerated in [§ Feature parity backlog](#feature-parity-backlog-garmin--coros-table-stakes) below. Almost nothing built yet (auto-pause + laps, grade-adjusted pace, HR zones + in-zone time, on-run alerts, the even-pace virtual partner, breadcrumb course following + the off-course alert, TrackBack / back-to-start, selectable GNSS modes, the race-time predictor, cut-off ETA alerts, and the sync protocol are the partial exceptions — see the annotated lines); most on-run-guidance + metric items already have a pure-logic helper in the main app to port, so parity is largely a firmware port, not a fresh design.

## Tier 1 — bench prototype (active, owner-personal)

**Goal.** Prove the firmware skeleton works end-to-end against the existing Supabase backend on real silicon, and build the domain credibility for later ODM conversations.

**Budget.** ~$1–2k cash + 3–6 months of evenings/weekends.

Per the [§ 71 2026-05-28 amendment](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely), this is owner-personal investigation only; tier 2+ remains gated on the original triggers.

### Per-step bring-up

Per [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md), in order:

- [ ] **Step 1 — Order parts.** See [`parts.md`](parts.md). ~$300 silicon + $200–900 bench tools.
- [x] **Step 2 — Scaffold Cargo workspace.** DONE 2026-05-28. Embassy + nRF52840 stub.
- [ ] **Step 3 — GNSS bring-up.** u-blox MAX-M10S NMEA parse, log fixes via defmt over RTT. — Code done, sim-verified 2026-07-08; bench verification pending parts.
- [ ] **Step 4 — Display bring-up.** Sharp Memory LCD over SPI, render current GPS fix. — Code done (driver + face + paged run dashboard + icons), sim-verified 2026-07-08; bench verification pending parts.
- [ ] **Step 5 — Optical HR bring-up.** MAX86177 over I²C, raw sample → naive peak-detect. — Code done incl. app-task wiring, sim-verified 2026-07-08 (absent-sensor probe parks cleanly); bench verification pending parts.
- [ ] **Step 6 — BLE GATT bring-up.** Phone pairs via `nrf-softdevice`, custom service. — Code done behind the `ble` feature ([§ 210](../architecture/decisions.md#210-tier-1-ble-s140-softdevice-is-a-compile-verified-feature-gated-build--mutually-exclusive-with-the-sim-off-by-default)), compile-and-link-verified only — the sim can't run the SoftDevice; needs the dev kit.
- [ ] **Step 7 — Integration.** Wire steps 3–6 into a single recording state machine (port of Dart `run_recorder`). — Recorder (with auto-pause) + button control + baro/elevation + flash run store + BLE run-sync firmware half all wired; recording sim-verified 2026-07-08, BLE sync compile-only ([§ 211](../architecture/decisions.md#211-owner-override-build-the-full-watchphonesupabase-run-sync-vertical-now-despite-the-tier-2-gate)); bench verification pending parts.

### Power instrumentation

Per [decisions.md § 83](../architecture/decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem): a Nordic Power Profiler Kit II (PPK2, ~$120) is part of the tier-1 bench-tools kit. Used **per-subsystem** (bare-MCU sleep, GPS active/sleep, HR AFE sample, display refresh) rather than whole-device — the DK's onboard J-Link + LEDs burn ~30 mA at idle and make whole-device readings useless as a baseline. The per-subsystem numbers project to tier-2 / tier-3 power (see [`performance_path.md`](performance_path.md)). DoD doesn't require hitting any specific number; these measurements inform tier-2 planning, they don't gate tier-1 completion.

### Definition of Done

Per [decisions.md § 82](../architecture/decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype): tier 1 is complete when **one real outdoor run produces a GPS+HR-tagged track that syncs to Supabase** from the bench prototype end-to-end.

## Tier 2 — wearable prototype (gated)

**Goal.** A device shaped like a watch, sized for the wrist, ≥24hr GPS battery, 100% outdoor fix reliability. Polish level of an early Kickstarter prototype.

**Budget.** $15–40k DIY or $80–250k consultant-built + 9–18 months calendar.

**Re-opening triggers** (per [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)):

- [ ] **Trigger (a)** — app has a paying user base large enough to fund a parallel hardware effort.
- [ ] **Trigger (b)** — an existing ODM (Mobvoi, Amazfit, Polar) approaches us about a white-label deal.
- [ ] **Trigger (c)** — a co-founder with shipped-consumer-hardware experience joins.

### Architectural obligations (must land before tier-2 prototype reaches a field tester)

- [ ] **OTA via a production-grade dual-bank bootloader.** [§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default) — MCUboot is the default candidate; the specific choice gets made at tier-2 design time but the obligation is fixed.
- [ ] **PMTiles vector renderer running on the MCU.** [§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) — multi-month firmware subproject (constrained subset of MapLibre's algorithm shape, port to Cortex-M4F + later Apollo4). 16 GB external SPI NAND flash committed in the BOM. Decision driven by [§ 86](../architecture/decisions.md#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) (end-state quality > engineering convenience).

### Vendor engagement (tiered per [§ 88](../architecture/decisions.md#88-vendor-engagement-is-tiered-across-project-maturity))

**Layer 1 — active now (free public research, zero commercial commitment):** **all three completed 2026-07-09** — findings + sources in [`vendor_research.md`](vendor_research.md).

- [x] ANT+ Alliance public adopter list → confirm competitors (COROS, Polar, Suunto, Apple Watch) are granted adoption. Closes most of the "would Garmin refuse?" uncertainty without writing a check. **Done 2026-07-09 — closed twice over: COROS APEX (+ Wahoo, Polar sensors) is publicly ANT+ Certified, and the adopter program itself was discontinued by Garmin in 2025 (fees ended, cert submissions closed 2025-03-31, docs now free, new profiles frozen — new metrics go BLE-only).**
- [x] Sony CXD5610 public family briefs → power consumption, mode breakdowns, package options. Enough for BOM planning. **Done 2026-07-09 — public brief is quantitative (9 mW L1+L5 tracking, −167 dBm, XFBGA-54); acquisition-mode + duty-cycled power are NOT public, so the Layer-2 NDA stays justified. No public teardown places the CXD5610 in any shipping watch; the Airoha AG3335M alternate is upgraded to co-equal (see `bom.md`).**
- [x] ADI MAX86177 public datasheet → register set + power-state characteristics for the tier-1 driver work. **Done 2026-07-09 — the "already public" premise was wrong: the full datasheet (register map included) is NDA-gated. Public sources confirm the AFE topology but not shutdown current. Tier-1 step-5 options: pull the ADI NDA forward, or bench on the MAX86171 (full datasheet public, same family idioms).**

**Layer 2 — active when tier-1 has a working bench prototype to point at:**

- [ ] Email Sony FAE with project brief + request for CXD5610 NDA datasheet + sampling conversation (~4 weeks for NDA paperwork; no commercial commitment). Ask specifically for acquisition-mode + duty-cycled power figures (not in the public brief) and for shipping-watch design-win references.
- [ ] Email ADI Maxim for HR-algorithm licensing terms at projected volume (real quote, non-binding until signed) — and the MAX86177 NDA datasheet, which turns out to be gated too (see `vendor_research.md`).

**Layer 3 — active at tier-2 greenlight (one of § 71's triggers fires):**

- ~~ANT+ Alliance Adopter membership application ($2–5k/year + Garmin review).~~ **Obsolete 2026-07-09:** Garmin discontinued the adopter program in 2025 — no fees, no certification submissions, documentation free ([`vendor_research.md`](vendor_research.md)). There is nothing left to apply for. Consequence for the parity backlog: BLE sensor pairing is the primary rail; ANT+ reception is best-effort legacy compat against a frozen protocol.

## Tier 3 — production-intent unit (gated)

**Goal.** Indistinguishable from a Garmin Fenix at arm's length. The first unit you'd ship to a paying customer.

**Budget.** $300–600k cash + 18–24 months calendar + a small team (1 EE, 1 ID, 1 mech-E, 1 RF consultant, 1 firmware lead).

**Triggers.** Same as tier 2 + a working tier-2 wearable prototype.

## Feature parity backlog (Garmin + COROS table stakes)

Everything above sequences the *hardware* build-out. This section tracks the *software feature surface* — the on-watch capabilities an ultra runner relies on today from a Garmin Fenix / Enduro or COROS Vertix, and would notice missing the day they switch. [`vision.md`](vision.md) covers the hardware table stakes (battery, GNSS, MIP display, buttons, maps, baro, HR); [`competitive_landscape.md`](competitive_landscape.md) covers where we go *beyond* parity (map UX, AI coach, social, update cadence). This is the middle layer: the features we have to match just to not feel like a downgrade.

**Framing.** Parity here means "an ultra runner doesn't lose a feature they relied on." It explicitly does **not** mean matching Garmin's full daily-smartwatch surface — per [`vision.md`](vision.md) the device is "a tool for the run, not a tool for the rest of the day," so the daily / lifestyle features are deliberately deprioritised (last table).

**Big lever.** Most on-run-guidance and training-metric items already have a pure-logic helper in the main app (the TS↔Dart parity pairs enumerated in [`CLAUDE.md`](../../CLAUDE.md)). For those, watch parity is a *firmware port* of an already-tested algorithm — the third language-level parity surface per [`firmware.md`](firmware.md) — not a fresh design; noted `(port: <helper>)` below. Items with no helper are new firmware design work.

Nothing in this section is complete; the partial exceptions (auto-pause + laps, grade-adjusted pace, HR zones + in-zone time, on-run alerts, the even-pace virtual partner, breadcrumb course following + off-course alert, TrackBack / back-to-start, selectable GNSS modes, the race-time predictor, cut-off ETA alerts, companion-app sync) are annotated on their lines and stay unticked until bench-verified. Tier tags show where each item realistically lands: **T1** = bench-prototype recording core, **T2** = wearable-prototype guidance / nav, **T3** = production polish.

### Recording & on-run guidance

- [ ] **Activity profiles** — at minimum Run / Trail Run / Ultra / Hike, each with its own data screens + defaults. **T2.**
- [ ] **Auto-lap / manual lap / auto-pause.** Auto-pause is already specced in [`run_recording.md`](../features/run_recording.md); direct firmware port. **Auto-pause is implemented** in the tier-1 recorder (`watch_core::record`, the 0.5 m/s moving-time gate, sim-verified 2026-07-08). **Auto-lap + manual lap are implemented too** (2026-07-09): a 1 km auto-lap boundary and a BTN4 manual lap close through the same host-tested `close_lap` path (a manual lap resets the auto countdown), surfaced on a fourth Lap run-view page — current lap time up large, lap number + last-lap split below. Laps are RAM display state only (the flash run-store wire format is unchanged). Host-tested + sim-verified (BTN4 → lap command → Lap page renders); stays unticked until bench-verified. **T1.**
- [ ] **Customisable data screens / fields** — which metrics show, how many per page. Ties to the data-screen customisation open question ([`firmware.md`](firmware.md) #4). **T3.**
- [ ] **Grade-adjusted pace on-watch.** `(port: grade_adjusted_pace)` — the same helper the Connect IQ Vector-1 field already surfaces. **Implemented** (2026-07-09): `watch_core::grade_adjusted_pace` is the fourth parity port of the Minetti helper (web canonical, Dart twin, Monkey C field) — the identical `grade_factor` polynomial + clamp and the whole-track batch helper mirrored test-for-test — plus a streaming `GapEstimator` in the Garmin field's shape (grade rolled per ≥5 m segment, 0.4 m/s walk gate) that the recorder feeds each accepted fix with the baro-preferred altitude; `Snapshot.gap_s_per_km` renders as a `GAP` row on the Pace glance page beside raw pace. Host-tested + sim-verified (synthetic 10% climb: GAP reads faster than raw pace on the emulated panel); stays unticked until bench-verified. **T1.**
- [ ] **Structured / interval workout execution** — run the planned workout (warmup → reps → recovery → cooldown) with per-step alerts. The main app's runner state machine ([`workout_execution.md`](../features/workout_execution.md)) is the reference. **T2.**
- [ ] **Pacing guidance (even / adaptive / target-time)** — Garmin PacePro, COROS pace alerts, a virtual-partner ahead/behind vs a goal. **The even-pace target-time virtual partner is implemented** (2026-07-10): `watch_core::pacer` runs a partner at perfectly even pace over a goal (distance + time) on the **elapsed** clock (the Garmin Virtual Partner semantics — a race clock doesn't stop at an aid station) and reduces the live totals into metres/seconds ahead-behind, a projected finish at the whole-run average, and an ahead / on-pace / behind verdict inside the app's shared ±5 % dead-band (the web `challenge_progress.ts` `ON_PACE_BAND` ratio rule, so watch and app can't disagree on "on pace"). Crossing the goal distance latches the result. The goal is unset by default, armed only through the plausibility-guarded `Recorder::set_pacer_goal` settings-sync hook (same shape as max HR) — nothing on-device sets it at tier 1. Surfaced as a sixth Pacer glance page (signed-split hero, verdict, goal / target / projected / distance delta, honest `NO GOAL SET` inactive state). Host-tested + sim-verified (demo goal under `sim-autostart`: the delta evolves in the defmt stream and on the emulated panel); stays unticked until bench-verified. Adaptive / PacePro-style grade-aware splitting (the roadbook's `gradeFactor` seam) and pace alerts remain **T2.**
- [ ] **On-run alerts** — HR-zone, pace, distance, time, and **drink / eat / nutrition reminders** (the ultra-critical one). `(port: fuel_plan for the nutrition cadence)`. **The T1 slice is implemented** (2026-07-10): `watch_core::alerts` fires drink/eat reminders on a moving-time cadence reduced from `fuel_plan`'s defaults (500 ml/hr → drink every 15 min, 60 g/hr at 25 g/gel → eat every 25 min — pauses bank nothing) plus an HR-zone ceiling alert (off by default, once-per-excursion hysteresis + 60 s cooldown); one alert on screen at a time (8 s TTL, zone outranks fuel, a superseded fuel reminder re-queues), rendered as a `!`-prefixed 2x banner over the hero band. Host-tested (18 tests) + sim-verified (shortened sim cadence → `! DRINK` / `! EAT` banners render on the emulated panel); stays unticked until bench-verified. Pace / distance / time alerts remain **T2**. See [decisions § 214](../architecture/decisions.md#214-tier-1-on-run-alerts-anchor-their-fuel-cadence-to-fuel_plans-defaults-bank-on-moving-time-and-share-one-display-slot). **T1/T2.**
- [ ] **Metronome / cadence target** — audible or vibration cadence pacer. **T2.**
- [ ] **Race / finish-time predictor on-watch.** `(port: race_predictor)`. **Implemented** (2026-07-10): `watch_core::race_predictor` is a parity port of web `training/race_predictor.ts` (`predictRaceLadder`) plus the `riegelPredict` + `predictionConfidence` helpers it reuses (Riegel exponent 1.06, recency half-life 30 d, the 5K/10K/Half/Marathon ladder), mirrored test-for-test. On the watch the effort pool is the **current run treated as a single effort** — the only source a standalone tier-1 watch has, and a platform-appropriate input to the *unchanged* ported algorithm, not a pioneered feature (see [decisions § 215](../architecture/decisions.md#215-tier-1-cut-off-eta-feeds-the-course-agnostic-recorder-a-route-position-the-race-predictor-projects-the-current-run-as-a-single-effort)). The recorder projects the ladder in its snapshot once the run clears a 1 km input-validity gate (below that a Riegel projection off a warm-up is noise); a ninth RacePredictor glance page (after Pacer) shows the whole ladder — the 10K projection as the hero, each rung with a per-rung confidence flag (` ` solid / `?` moderate / `~` low from `predictionConfidence`) — and an honest `NEED 1 KM` blank state. Host-tested (13 module + wiring/face tests) + build-verified (hardware + sim feature sets); Renode sim + bench verification pending. **T1.**
- [ ] **Pace-distribution / race-band / gear-wear glance pages.** `(port: pace_segments, distance_bands, gear_wear)`. **Implemented** (2026-07-11): three more parity-port cores fold into the recorder snapshot + run-view pages — a **Splits** page (distance banked per pace bucket, accrued in `on_fix` by segment speed via `pace_segments::pace_bucket_for_speed`, bars scaled to the fullest bucket — the pace analogue of the Zones page), a **DistanceBand** page (the race-distance band the run distance falls in, or an honest gap), and a **GearWear** page (the active shoe's wear, the run's distance folded into a synced baseline via `Recorder::set_gear`; unset on hardware until a settings sync, sim-armed at 700/800 km). Host-tested + build-verified. **T1.**
- [ ] **Climb detection / ClimbPro-style ascent view** — live "X m of climb remaining in this ascent," per-climb grade. A headline Garmin ultra feature; COROS has an equivalent. Per-leg vert exists in `roadbook`; live climb segmentation is new firmware work. **T2/T3.**
- [ ] **Climb detection / ClimbPro-style ascent view** — live "X m of climb remaining in this ascent," per-climb grade. A headline Garmin ultra feature; COROS has an equivalent. Per-leg vert exists in `roadbook`; live climb segmentation is new firmware work. **T2/T3.**

### Navigation & maps

- [ ] **Breadcrumb course following + off-course alert.** `(port: route_overlay off-route detection)` — already called out in [`firmware.md`](firmware.md). **Implemented** (2026-07-10): `watch_core::course` is the fifth parity port — `Course::project` mirrors web `route_snap.ts` `snapToPolyline` (nearest perpendicular foot per segment, along-course accumulation, the `route_geometry.ts` `distanceAlongRoute` shape, tests mirrored case-for-case) and `OffCourseAlert` latches the mobile run screen's thresholds (alert past 40 m, re-arm below 20 m, so a boundary can't flap). A seventh Nav run-view page (BTN3, after Pacer) draws the course polyline + a position-marker cross into a 168x96 panel (`PanelFit` with the cos(mid-lat) correction, `sharp_mip` gains Bresenham `draw_line`), with distance-along-course + offset below and a steady 2x OFF COURSE banner over the breadcrumb while the alert is latched; the panel repaints only when marker/alert change. Course capacity is 256 points / 4 KiB RAM — a longer course must be phone-simplified before the (future, tier-2) BLE push; today the only course is the canned sim one behind the default-off `sim-course` feature, so the hardware build's Nav page honestly reports NO COURSE LOADED. Host-tested + sim-verified (the bench_jog fixture leaves the canned course on two legs: `nav: OFF COURSE (41 m off, 179 m along)` fires, the banner renders on the emulated panel, `nav: back on course` re-arms); stays unticked until bench-verified. **T1** (breadcrumb) / **T2** (alert — landed at T1 with the breadcrumb since the latch is 30 lines on top of the projection).
- [ ] **Offline vector maps.** The hardware + renderer commitment is [`vision.md`](vision.md) req #5 + [§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash); this is the *feature* row. **T2/T3.**
- [ ] **Turn-by-turn on a routable map** — beyond breadcrumb, actual routing. **T3.**
- [ ] **Course elevation profile + aid-station / checkpoint markers.** `(port: route_markers, roadbook)`. **The checkpoint-schedule + fuelling half is implemented** (2026-07-11): `watch_core::roadbook` + `fuel_plan` (parity ports) drive a Roadbook glance page (the upcoming checkpoints from the current route position — each its distance, projected arrival, and safe/tight/miss cutoff flag) and a Fuel page (`build_fuel_plan` over the schedule → carry-to-next-aid + run totals). The roadbook is **pushed pre-built** (`Recorder::set_roadbook`, name-free `Copy` checkpoints capped at 16, the same model as cutoff legs) because building it needs the route polyline the watch doesn't hold — the phone builds it where the polyline lives. Unset on hardware (honest `NO ROADBOOK` / `NO FUEL PLAN` pages) until a phone push; the sim arms a demo schedule behind `sim-course`. Host-tested + build-verified (hardware + sim). The **elevation-profile graph** itself (a rendered climb profile) is not drawn yet — only the per-leg schedule — so this stays **T2**.
- [ ] **TrackBack / back-to-start** — retrace the recorded track to the start. **Implemented** (2026-07-10): `watch_core::trackback` reduces the recorder's accepted fixes (the `last_fix_stored` seam, so the crumb mirrors the flash track exactly) into a fixed-RAM breadcrumb — 96 points at 20 m spacing that **thins by halving + spacing-doubling** instead of dropping the tail, so capacity grows logarithmically with run length (~245 km in ~768 B) — plus the live haversine distance and great-circle bearing back to the start and a course-over-ground heading (bearing over the last ≥5 m of real displacement; tier 1 has no magnetometer, so a stationary runner's heading goes honestly stale after 10 s rather than freezing an arrow). BTN3 gains an eighth BackToStart glance page after Nav: distance-to-start hero (m under a km, km beyond), 16-wind HDG/BRG rows, a relative direction arrow (bearing minus heading, `--` when the heading is absent/stale), and a north-up aspect-preserved breadcrumb map (hollow-box start, filled-dot position) drawn via the `sharp_mip` `draw_line` Bresenham primitive. Flash run-store wire format unchanged. Host-tested (14 trackback + 4 face tests) + sim-verified over the canned jog (distance/bearing evolve around the loop, arrow points back, breadcrumb decimates at 20 m spacing); stays unticked until bench-verified. **T2** (built at T1 — pure recording-core geometry, no map/route dependency).
- [ ] **Round-trip / loop route generation** pushed from the phone. The app already generates loops (the `graph_cycle` sidecar); parity is surfacing one to the watch. **T3.**
- [ ] **Compass / bearing** — needs a magnetometer in the BOM (check [`bom.md`](bom.md)). **T2/T3.**

### Training & physiology metrics

- [ ] **HR zones + in-zone time.** **Implemented** (2026-07-09): `watch_core::hr_zones` mirrors the main app's default zone model rather than inventing one (web `training/hr_zones.ts` canonical, Dart + Wear OS twins) — Z1..Z5 upper bounds at 60/70/80/90/100 % of max HR, inclusive boundaries, the same legacy 190 bpm fallback; the runner's explicit `hr_zones` / Tanaka-from-age precedence stays a phone/web concern, with max HR a plausibility-guarded (80..=240) recorder setter for a future settings sync. Per-zone time banks exactly where moving time accrues — manual pause, auto-pause, and a missing/dropped pulse bank nothing. Run-view HR rows show the live zone (`152 BPM Z3`) and BTN3 gains a fifth Zones glance page after Lap: BPM hero, current zone, per-zone time rows with bars scaled to the fullest zone. Flash run-store wire format unchanged. Host-tested + sim-verified (the sim has no HR sensor, so the honest sim check is the `--` / zero-time rendering on the Zones page); stays unticked until bench-verified. **T1.**
- [ ] **Training load / acute-chronic balance (CTL / ATL / TSB).** `(port: training_load, fitness)`. **The single-run stress half is implemented** (2026-07-11): `watch_core::training_load` (parity port) computes the current run's stress contribution via `compute_stress` — the distance model, since the watch tracks no average HR (a future HR-threshold sync upgrades it to TRIMP) — surfaced on a TrainingLoad glance page. The **rolling CTL/ATL/TSB** needs the multi-day run history the standalone watch doesn't hold, so the page shows it as `SYNC` and that half stays a phone/web concern. Host-tested + build-verified. **T2.**
- [ ] **VO2max / fitness estimate.** `(port: fitness / race_predictor inputs)`. **T2.**
- [ ] **Training status / readiness / recovery time** — Garmin Training Readiness, COROS equivalent. New synthesis on top of the load helpers. **T3.**
- [ ] **Running dynamics** — cadence (have), plus stride length, vertical oscillation, ground-contact time, running power. Some need extra sensor fusion or an accessory. **T3.**
- [ ] **Resting HR / HRV status.** **T2/T3.**
- [ ] **SpO2 / pulse-ox** (altitude acclimatisation — mountain ultras). Needs AFE support; check the HR-sensor choice in [`vision.md`](vision.md) req #8. **T3.**
- [ ] **Sleep / stress / "body-battery"-style energy** — explicitly low-priority; these are daily-wear metrics, not run metrics. **T3 or deferred.**

### Safety & live tracking

- [ ] **Live spectator tracking** — watch → phone → the existing live pipeline. Already specced as a firmware stretch in [`firmware.md`](firmware.md). `(reuses live_freshness)`. **T2.**
- [ ] **Cutoff / barrier ETA alerts** — "you're 8 min ahead of the next cutoff." `(port: live_cutoff_eta, roadbook)` — a genuine ultra differentiator, not just parity. **Implemented** (2026-07-10): `watch_core::cutoff_eta` is a parity port of web `runs/live_cutoff_eta.ts` `nextCutoffEta` (the `roadbook.ts` `CUTOFF_TIGHT_S` = 30 min span, the nearest-cutoff-ahead selection, the flat-pace projection), mirrored test-for-test. It rides the breadcrumb-course work this batch's sibling built: the `nav` task's along-course projection is fed into the (course-agnostic) recorder via `set_route_position`, and the recorder folds in the whole-run pace to project on / tight / behind at the next cutoff. The honesty rule is the port's: a stale route position (lost signal, aged past a few fix intervals) or an unknown pace **withholds** the projected time (`Unknown`) rather than fabricate an arrival off an old fix — the checkpoint distance is still shown. A tenth CutoffEta glance page (after RacePredictor) shows the margin as the hero (`+`/`-` split), the verdict, the distance to the cutoff, and the projected arrival clock, with honest `NO CUTOFFS` / `NO CUTOFF AHEAD` states. Cutoff legs are static at tier 1 (canned on the sim course; the hardware build carries none until a BLE course-push path lands, so its page reads `NO CUTOFFS`). See [decisions § 215](../architecture/decisions.md#215-tier-1-cut-off-eta-feeds-the-course-agnostic-recorder-a-route-position-the-race-predictor-projects-the-current-run-as-a-single-effort). Host-tested (13 module + wiring/face tests) + build-verified (hardware + sim feature sets); Renode sim + bench verification pending. **T1** (landed at T1 with the course work — pure projection on top of the along-course distance).
- [ ] **Incident detection + emergency-contact alert** (fall / stop detection → notify). Needs an accelerometer + the phone bridge. **T3.**
- [ ] **Satellite SOS.** Garmin's inReach integration is the backcountry safety killer feature — **and a COROS gap** ([`competitive_landscape.md`](competitive_landscape.md)) — so it is parity-with-Garmin *and* a wedge against COROS. Needs satellite hardware + service → real BOM + partnership cost. **T3+ / stretch.**

### Sensors & connectivity

- [ ] **BLE sensor pairing** — external HR strap, foot pod. **T1/T2.**
- [ ] **ANT+ sensor pairing** — gated on the ANT+ adoption question ([`firmware.md`](firmware.md) #2; vendor layers in [§ 88](../architecture/decisions.md#88-vendor-engagement-is-tiered-across-project-maturity)). **T2.**
- [ ] **HR broadcast** — rebroadcast wrist HR to another device / the phone. **T2.**
- [ ] **Selectable GNSS / battery modes** — single-band vs dual-band vs max-accuracy, each with a battery estimate. The power-manager surface every ultra watch ships. Firmware power management. **The tier-1 software half is implemented** (2026-07-10): `watch_core::gnss_mode` defines three modes — Performance (every ~1 s fix), Balanced (one per 15 s), Expedition (one per 60 s, the Garmin UltraTrac / COROS UltraMax class) — each with a projected-battery-hours figure (~110/~180/~220 h, derived from the `vision.md` tier-2 target + `performance_path.md`'s GNSS duty-cycling lever; projections, not measurements — the DK can't measure power). BTN3 cycles the mode on the idle face (`MODE PERF ~110H` row; mid-run BTN3 keeps cycling pages, so a run's mode is frozen for its duration), the gps task generalises its idle fix de-rate into the selected recording cadence, the recorder's jump gate scales with the interval (`MAX_SPEED_MPS * dt` past 1 s — the fixed 100 m ceiling would reject every legitimate 60 s segment; the 1 Hz filter is unchanged), and the face's staleness budget stretches to the mode's cadence so Expedition's 60 s gaps read as the chosen rhythm, not signal loss; run-view GPS rows carry the mode tag. Host-tested + sim-verified (idle BTN3 cycles the MODE row on the emulated panel; forwarded-fix cadence measured ~1 s / 15 s / 60 s per mode in the defmt stream). What stays hardware: actually power-managing the receiver between fixes (u-blox power-save / backup mode — the sim can't model it) and single-vs-dual-band selection. Stays unticked until bench-verified. **T1 (mode surface + cadence) / T2 (receiver power-down + band selection).**
- [ ] **Phone smart-notifications** — read-only notification mirroring. Low priority per the "tool for the run" framing. **T3.**

### Platform & lifecycle

- [ ] **OTA firmware updates** — already an architectural obligation ([§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default), tier-2 dual-bank bootloader). **T2.**
- [ ] **Companion-app sync** — BLE GATT run / course sync, specced in [`firmware.md`](firmware.md). Both halves are built ([§ 211](../architecture/decisions.md#211-owner-override-build-the-full-watchphonesupabase-run-sync-vertical-now-despite-the-tier-2-gate)): the firmware's `run_manifest`/`run_chunk` GATT protocol + flash run store, and the phone's pull→verify→`api.saveRun` client — compile-only on the radio side, bench verification pending parts. **T1.**
- [ ] **Watch-face / data-screen customisation** — [`firmware.md`](firmware.md) #4; Garmin's Connect IQ face marketplace is part of their moat. Design the hook now, ship later. **T3.**

### Daily / smartwatch — deliberately deferred (out of the ultra thesis)

Per [`vision.md`](vision.md) the watch is a tool for the run, not the day. These are Garmin / COROS features we are **choosing not to chase** for v1; listed so the decision is explicit, not an oversight. Music + payments are also COROS gaps, so skipping them costs no ground against COROS specifically.

- [ ] **On-watch music storage + BLE-headphone playback** — deferred. (COROS lacks this too.)
- [ ] **Contactless payments (Garmin Pay-style)** — deferred. (COROS lacks this too.)
- [ ] **Weather / storm alerts** — partial: baro-driven storm detection is cheap ([`vision.md`](vision.md) req #7) and worth it; full forecast sync is deferred.
- [ ] **Alarms / timer / stopwatch / find-my-phone** — trivial; ship opportunistically. **T3.**

## Strategic vectors — alternatives to building our own

Per [`competitive_landscape.md`](competitive_landscape.md), three vectors beat "build your own watch from scratch" if the asymmetric play is the goal. Listed in order of cost / risk:

### Vector 1 — Connect IQ app or data field for existing Garmin owners

| Field | Value |
|---|---|
| Status | **Active, parallel to tier-1** per [§ 87](../architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware). **Scaffold landed** at [`apps/watch_garmin/`](../../apps/watch_garmin/README.md) — a Connect IQ **data field** (Monkey C) showing grade-adjusted pace; toolchain spike, not yet shipped. See [§ 107](../architecture/decisions.md#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app). |
| Cost | A few weeks of Monkey C development |
| Risk | Near zero — distributed via Garmin's own marketplace |
| What it tests | Whether our software UX is meaningfully better than Garmin's first-party UI (the #1 complaint about Garmin) |
| Downside | Garmin can sherlock the idea, though they've been bad at this for a decade |

### Vector 2 — Wear OS app positioned as Garmin alternative for sub-12hr runners

| Field | Value |
|---|---|
| Status | `apps/watch_wear/` exists, ships product features, **not yet framed as a Garmin-alternative play** |
| Cost | Months of focused work (positioning + feature gaps vs Garmin) |
| Risk | Low — already shipping on Wear OS |
| What it tests | Whether our app + AI coach + community make a Galaxy Watch / Pixel Watch a credible Garmin alternative for the sub-12hr market |
| Trade | Concedes the 100hr-GPS ultra market entirely; Wear OS battery can't reach it |

### Vector 3 — ODM partnership

| Field | Value |
|---|---|
| Status | No vendor conversations |
| Cost | Significant team time; no tooling capital |
| Risk | Medium — depends on ODM relationship |
| What it tests | Whether a mid-tier ODM (Polar, Mobvoi, Amazfit) will license our software for their hardware |
| Trade | Tied to their hardware roadmap; have to negotiate the relationship |

## Open questions to resolve

**All initial open questions resolved during the 2026-05-28 planning sweep.** Resolutions tracked below; new OQs land here as they arise during tier-1 / tier-2 work.

| OQ | Topic | Resolved in |
|---|---|---|
| OQ1 + OQ2 | Tier-1 Definition of Done + kill criteria | [§ 82](../architecture/decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype) — one-outdoor-run DoD; explicitly no kill criteria |
| OQ3 | Power-measurement methodology | [§ 83](../architecture/decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem) — Nordic PPK2, per-subsystem |
| OQ4 | OTA architecture | [§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default) — tier-1 no OTA; tier-2 obligated to a dual-bank bootloader (MCUboot default) |
| OQ5 | Map renderer + format | [§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) — full PMTiles + on-MCU vector rendering + 16 GB external NAND |
| OQ6 | Strategic-vector sequencing | [§ 87](../architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware) — vector 1 (Connect IQ app) runs in parallel with tier-1 |
| OQ7 | Vendor relationship pre-validation | [§ 88](../architecture/decisions.md#88-vendor-engagement-is-tiered-across-project-maturity) — tiered: research now, NDA post-prototype, commercial at tier-2 |
| OQ8 | User research with ultra runners | [§ 89](../architecture/decisions.md#89-skip-user-research-interviews-vector-1-install-rate-is-the-validation-channel) — skipped; vector-1 install rate is the validation channel |

**Decision-making meta-principle:** [§ 86](../architecture/decisions.md#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) (custom_watch picks optimise for end-state product quality, even at small margins).

## Smaller considerations

These are real but lower-leverage. Worth tracking; not blocking.

- **Privacy posture for the watch.** Watch records GPS, HR, biometrics. The rest of the product takes data minimization + retention + export seriously; the watch inherits nothing yet. Pull in the patterns from the main app (`docs/backend/api_database.md`, `docs/testing/dev_prod_isolation.md`) when tier 2 starts.
- **Tier-1 budget cap formalization.** § 71 amendment lifts the spend cap but doesn't say "tier-1 spend over $X requires re-asking." Easy to drift past $1–2k without noticing.
- **Local-store overflow behaviour.** Current tier-1 answer (per [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md) step 7): the run store is **4 × 4 KiB internal-flash slots** with a **253-point-per-run cap** — a few minutes of track per run, a bench-prototype foundation, not shipping capacity. Real capacity (an ultra's 360k points, days off-grid) needs the tier-2 external QSPI flash; the overflow/retention policy for that store is still an open architectural choice.
- **Tier-1 development log + showcase plan.** Tier 1's stated deliverable is "knowledge + a credible technical story for ODM conversations." The log exists: [`tier1_log.md`](tier1_log.md), one dated entry per milestone (started 2026-07-09, reconstructed back to the 2026-05-28 scaffold). Photo/video slots start when parts arrive.
- **Watch face customization architecture.** Per [`firmware.md`](firmware.md) open Q#4 — almost certainly out of v1.0 scope but worth designing the UI layer with the customization hook in mind. Decide which Embassy UI primitives stay decoupled.
- **No external issue tracker.** All planning lives in markdown. Fine while it's one person; gets messy fast if anyone else joins. GitHub Projects board is the cheapest pivot.

## Pinning

- **Locked decisions:** [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) (deferral + amendment), [§ 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) (firmware stack), [§ 81](../architecture/decisions.md#81-custom-watch-input-is-5-physical-buttons-in-the-garmin-fenix-layout-no-touchscreen) (input).
- **Active workspace:** [`apps/custom_watch/`](../../apps/custom_watch/README.md).
- **Strategic / spec references:** [`vision.md`](vision.md), [`competitive_landscape.md`](competitive_landscape.md), [`bom.md`](bom.md), [`prototyping.md`](prototyping.md), [`performance_path.md`](performance_path.md), [`firmware.md`](firmware.md).
- **Active checklist:** [`parts.md`](parts.md).
