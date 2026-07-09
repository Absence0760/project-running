# Roadmap — custom_watch

The big-picture sequencing for the ultra-marathon watch research effort. Separate from the main app's [`docs/product/roadmap.md`](../product/roadmap.md) because the watch has its own multi-tier hardware-investment sequence that doesn't map onto the main app's phased product roadmap. Read alongside [`competitive_landscape.md`](competitive_landscape.md) (strategic framing), [`prototyping.md`](prototyping.md) (the three cost tiers), and [`decisions.md § 71 / § 80 / § 81`](../architecture/decisions.md) for the locked decisions.

**This doc is live.** Update the per-tier checkboxes + status snapshot as work progresses; resolve open questions into `decisions.md` entries as they're decided.

## Status snapshot (2026-05-28)

- **Long-term goal: [§ 92](../architecture/decisions.md#92-custom-watch-decisions-optimise-for-tier-3-production-quality-period--scope-and-effort-are-not-constraints) — build the best watch ever** (full Phase 0–5 optimal-road timeline in § 92's table). Tier-2+ decisions optimise for the tier-3 shipped product without effort or scope as valid counter-arguments.
- **Tier 1 (bench prototype)**: workspace scaffolded; no parts ordered; no on-board verification yet. **Stays on nRF52840 per [§ 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)** — deliberate first-prototype compromise per the [§ 92 Resolution](../architecture/decisions.md#resolution-2026-05-28--hybrid--92-long-term-goal---80-tier-1-preserved-as-deliberate-first-prototype-compromise) ("keep costs down and get a working version first").
- **Tier 2 (wearable prototype)**: gated on the three [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) triggers; not active. Migrates to Apollo510B silicon per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified); MCUboot lands per [§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default); ANT+ Alliance per [§ 88](../architecture/decisions.md#88-vendor-engagement-is-tiered-across-project-maturity) Layer 3.
- **Tier 3 (production-intent unit)**: gated on same triggers; not active. The full Phase 0–5 vision per § 92.
- **Vector 1 (Connect IQ app)**: not started — runs parallel to tier-1 per [§ 87](../architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware).
- **Vector 2 (Wear OS app)**: `apps/watch_wear/` ships product features but isn't framed as a "Garmin alternative for sub-12hr runners" play.
- **Vector 3 (ODM partnership)**: no vendor conversations; no outreach.
- **Feature parity:** the software feature surface an ultra runner expects from a Garmin / COROS flagship — recording, navigation, training metrics, safety — is enumerated in [§ Feature parity backlog](#feature-parity-backlog-garmin--coros-table-stakes) below. Nothing built yet; most on-run-guidance + metric items already have a pure-logic helper in the main app to port, so parity is largely a firmware port, not a fresh design.

## Tier 1 — bench prototype (active, owner-personal)

**Goal.** Prove the firmware skeleton works end-to-end against the existing Supabase backend on real silicon, and build the domain credibility for later ODM conversations.

**Budget.** ~$1–2k cash + 3–6 months of evenings/weekends.

Per the [§ 71 2026-05-28 amendment](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely), this is owner-personal investigation only; tier 2+ remains gated on the original triggers.

### Per-step bring-up

Per [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md), in order:

- [ ] **Step 1 — Order parts.** See [`parts.md`](parts.md). ~$300 silicon + $200–900 bench tools.
- [x] **Step 2 — Scaffold Cargo workspace.** DONE 2026-05-28. Embassy + nRF52840 stub.
- [ ] **Step 3 — GNSS bring-up.** u-blox MAX-M10S NMEA parse, log fixes via defmt over RTT.
- [ ] **Step 4 — Display bring-up.** Sharp Memory LCD over SPI, render current GPS fix.
- [ ] **Step 5 — Optical HR bring-up.** MAX86177 over I²C, raw sample → naive peak-detect.
- [ ] **Step 6 — BLE GATT bring-up.** Phone pairs via `nrf-softdevice`, custom service.
- [ ] **Step 7 — Integration.** Wire steps 3–6 into a single recording state machine (port of Dart `run_recorder`).

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

**Layer 1 — active now (free public research, zero commercial commitment):**

- [ ] ANT+ Alliance public adopter list → confirm competitors (COROS, Polar, Suunto, Apple Watch) are granted adoption. Closes most of the "would Garmin refuse?" uncertainty without writing a check.
- [ ] Sony CXD5610 public family briefs → power consumption, mode breakdowns, package options. Enough for BOM planning.
- [ ] ADI MAX86177 public datasheet → register set + power-state characteristics for the tier-1 driver work.

**Layer 2 — active when tier-1 has a working bench prototype to point at:**

- [ ] Email Sony FAE with project brief + request for CXD5610 NDA datasheet + sampling conversation (~4 weeks for NDA paperwork; no commercial commitment).
- [ ] Email ADI Maxim for HR-algorithm licensing terms at projected volume (real quote, non-binding until signed).

**Layer 3 — active at tier-2 greenlight (one of § 71's triggers fires):**

- [ ] ANT+ Alliance Adopter membership application ($2–5k/year + Garmin review). Commitment-grade; paying the fee + tipping our hand only makes sense once we've committed to ship hardware.

## Tier 3 — production-intent unit (gated)

**Goal.** Indistinguishable from a Garmin Fenix at arm's length. The first unit you'd ship to a paying customer.

**Budget.** $300–600k cash + 18–24 months calendar + a small team (1 EE, 1 ID, 1 mech-E, 1 RF consultant, 1 firmware lead).

**Triggers.** Same as tier 2 + a working tier-2 wearable prototype.

## Feature parity backlog (Garmin + COROS table stakes)

Everything above sequences the *hardware* build-out. This section tracks the *software feature surface* — the on-watch capabilities an ultra runner relies on today from a Garmin Fenix / Enduro or COROS Vertix, and would notice missing the day they switch. [`vision.md`](vision.md) covers the hardware table stakes (battery, GNSS, MIP display, buttons, maps, baro, HR); [`competitive_landscape.md`](competitive_landscape.md) covers where we go *beyond* parity (map UX, AI coach, social, update cadence). This is the middle layer: the features we have to match just to not feel like a downgrade.

**Framing.** Parity here means "an ultra runner doesn't lose a feature they relied on." It explicitly does **not** mean matching Garmin's full daily-smartwatch surface — per [`vision.md`](vision.md) the device is "a tool for the run, not a tool for the rest of the day," so the daily / lifestyle features are deliberately deprioritised (last table).

**Big lever.** Most on-run-guidance and training-metric items already have a pure-logic helper in the main app (the TS↔Dart parity pairs enumerated in [`CLAUDE.md`](../../CLAUDE.md)). For those, watch parity is a *firmware port* of an already-tested algorithm — the third language-level parity surface per [`firmware.md`](firmware.md) — not a fresh design; noted `(port: <helper>)` below. Items with no helper are new firmware design work.

Nothing in this section is built. Tier tags show where each item realistically lands: **T1** = bench-prototype recording core, **T2** = wearable-prototype guidance / nav, **T3** = production polish.

### Recording & on-run guidance

- [ ] **Activity profiles** — at minimum Run / Trail Run / Ultra / Hike, each with its own data screens + defaults. **T2.**
- [ ] **Auto-lap / manual lap / auto-pause.** Auto-pause is already specced in [`run_recording.md`](../features/run_recording.md); direct firmware port. **T1.**
- [ ] **Customisable data screens / fields** — which metrics show, how many per page. Ties to the data-screen customisation open question ([`firmware.md`](firmware.md) #4). **T3.**
- [ ] **Grade-adjusted pace on-watch.** `(port: grade_adjusted_pace)` — the same helper the Connect IQ Vector-1 field already surfaces. **T1.**
- [ ] **Structured / interval workout execution** — run the planned workout (warmup → reps → recovery → cooldown) with per-step alerts. The main app's runner state machine ([`workout_execution.md`](../features/workout_execution.md)) is the reference. **T2.**
- [ ] **Pacing guidance (even / adaptive / target-time)** — Garmin PacePro, COROS pace alerts, a virtual-partner ahead/behind vs a goal. **T2.**
- [ ] **On-run alerts** — HR-zone, pace, distance, time, and **drink / eat / nutrition reminders** (the ultra-critical one). `(port: fuel_plan for the nutrition cadence)`. **T1/T2.**
- [ ] **Metronome / cadence target** — audible or vibration cadence pacer. **T2.**
- [ ] **Race / finish-time predictor on-watch.** `(port: race_predictor)`. **T2.**
- [ ] **Climb detection / ClimbPro-style ascent view** — live "X m of climb remaining in this ascent," per-climb grade. A headline Garmin ultra feature; COROS has an equivalent. Per-leg vert exists in `roadbook`; live climb segmentation is new firmware work. **T2/T3.**

### Navigation & maps

- [ ] **Breadcrumb course following + off-course alert.** `(port: route_overlay off-route detection)` — already called out in [`firmware.md`](firmware.md). **T1** (breadcrumb) / **T2** (alert).
- [ ] **Offline vector maps.** The hardware + renderer commitment is [`vision.md`](vision.md) req #5 + [§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash); this is the *feature* row. **T2/T3.**
- [ ] **Turn-by-turn on a routable map** — beyond breadcrumb, actual routing. **T3.**
- [ ] **Course elevation profile + aid-station / checkpoint markers.** `(port: route_markers, roadbook)`. **T2.**
- [ ] **TrackBack / back-to-start** — retrace the recorded track to the start. **T2.**
- [ ] **Round-trip / loop route generation** pushed from the phone. The app already generates loops (the `graph_cycle` sidecar); parity is surfacing one to the watch. **T3.**
- [ ] **Compass / bearing** — needs a magnetometer in the BOM (check [`bom.md`](bom.md)). **T2/T3.**

### Training & physiology metrics

- [ ] **HR zones + in-zone time.** **T1.**
- [ ] **Training load / acute-chronic balance (CTL / ATL / TSB).** `(port: training_load, fitness)`. **T2.**
- [ ] **VO2max / fitness estimate.** `(port: fitness / race_predictor inputs)`. **T2.**
- [ ] **Training status / readiness / recovery time** — Garmin Training Readiness, COROS equivalent. New synthesis on top of the load helpers. **T3.**
- [ ] **Running dynamics** — cadence (have), plus stride length, vertical oscillation, ground-contact time, running power. Some need extra sensor fusion or an accessory. **T3.**
- [ ] **Resting HR / HRV status.** **T2/T3.**
- [ ] **SpO2 / pulse-ox** (altitude acclimatisation — mountain ultras). Needs AFE support; check the HR-sensor choice in [`vision.md`](vision.md) req #8. **T3.**
- [ ] **Sleep / stress / "body-battery"-style energy** — explicitly low-priority; these are daily-wear metrics, not run metrics. **T3 or deferred.**

### Safety & live tracking

- [ ] **Live spectator tracking** — watch → phone → the existing live pipeline. Already specced as a firmware stretch in [`firmware.md`](firmware.md). `(reuses live_freshness)`. **T2.**
- [ ] **Cutoff / barrier ETA alerts** — "you're 8 min ahead of the next cutoff." `(port: live_cutoff_eta, roadbook)` — a genuine ultra differentiator, not just parity. **T2.**
- [ ] **Incident detection + emergency-contact alert** (fall / stop detection → notify). Needs an accelerometer + the phone bridge. **T3.**
- [ ] **Satellite SOS.** Garmin's inReach integration is the backcountry safety killer feature — **and a COROS gap** ([`competitive_landscape.md`](competitive_landscape.md)) — so it is parity-with-Garmin *and* a wedge against COROS. Needs satellite hardware + service → real BOM + partnership cost. **T3+ / stretch.**

### Sensors & connectivity

- [ ] **BLE sensor pairing** — external HR strap, foot pod. **T1/T2.**
- [ ] **ANT+ sensor pairing** — gated on the ANT+ adoption question ([`firmware.md`](firmware.md) #2; vendor layers in [§ 88](../architecture/decisions.md#88-vendor-engagement-is-tiered-across-project-maturity)). **T2.**
- [ ] **HR broadcast** — rebroadcast wrist HR to another device / the phone. **T2.**
- [ ] **Selectable GNSS / battery modes** — single-band vs dual-band vs max-accuracy, each with a battery estimate. The power-manager surface every ultra watch ships. Firmware power management. **T2.**
- [ ] **Phone smart-notifications** — read-only notification mirroring. Low priority per the "tool for the run" framing. **T3.**

### Platform & lifecycle

- [ ] **OTA firmware updates** — already an architectural obligation ([§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default), tier-2 dual-bank bootloader). **T2.**
- [ ] **Companion-app sync** — BLE GATT run / course sync, specced in [`firmware.md`](firmware.md). **T1.**
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
- **Local-store overflow behaviour.** Tier-1 records to LittleFS — but how big does the local store get before we start dropping runs? Architectural choice; matters for ultra runners who go off-grid for days.
- **Tier-1 development log + showcase plan.** Tier 1's stated deliverable is "knowledge + a credible technical story for ODM conversations." Without a written log + photos/video, that knowledge stays in your head. Suggested: `docs/custom_watch/tier1_log.md`, photographed at each milestone.
- **Watch face customization architecture.** Per [`firmware.md`](firmware.md) open Q#4 — almost certainly out of v1.0 scope but worth designing the UI layer with the customization hook in mind. Decide which Embassy UI primitives stay decoupled.
- **No external issue tracker.** All planning lives in markdown. Fine while it's one person; gets messy fast if anyone else joins. GitHub Projects board is the cheapest pivot.

## Pinning

- **Locked decisions:** [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) (deferral + amendment), [§ 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) (firmware stack), [§ 81](../architecture/decisions.md#81-custom-watch-input-is-5-physical-buttons-in-the-garmin-fenix-layout-no-touchscreen) (input).
- **Active workspace:** [`apps/custom_watch/`](../../apps/custom_watch/README.md).
- **Strategic / spec references:** [`vision.md`](vision.md), [`competitive_landscape.md`](competitive_landscape.md), [`bom.md`](bom.md), [`prototyping.md`](prototyping.md), [`performance_path.md`](performance_path.md), [`firmware.md`](firmware.md).
- **Active checklist:** [`parts.md`](parts.md).
