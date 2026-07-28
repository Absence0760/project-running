# Tier-2 software scope — custom_watch

Sizes the **software** work behind every tier-2 item in [`roadmap.md`](roadmap.md), names what each one is actually blocked on, and sequences them. Written because the roadmap says *what* is owed at tier 2 but never said *how much*, so "the rest is tier 2" was carrying an unknown — and one of the largest items in it (the silicon migration) had no line at all.

**This doc is not a greenlight.** Tier 2 stays gated on the three [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) triggers (paying user base, ODM approach, hardware co-founder). Nothing here is authorised work; it exists so that if a trigger fires, the first conversation starts from a costed list instead of a blank page. Tier-2 design choices are governed by [§ 92](../architecture/decisions.md#92-custom-watch-decisions-optimise-for-tier-3-production-quality-period--scope-and-effort-are-not-constraints) ("optimal regardless of effort or scope"), not by what is cheap here.

## How to read the sizing

| Band | Meaning |
|---|---|
| **S** | ≤ 2 weeks of evenings |
| **M** | 3–8 weeks of evenings |
| **L** | 2–6 months of evenings |
| **XL** | 6+ months — a subproject with its own plan, not a task |

**These bands are derivations, not measurements** — the same standing caveat the GNSS-mode battery figures carry ([`quality_standards.md § derived-not-measured`](quality_standards.md)). They are anchored on the one real datum the project has: tier-1 steps 3–7 each ran roughly 2–4 weeks of evenings ([`apps/custom_watch/README.md`](../../apps/custom_watch/README.md)), and the ported-core batches ran a few days each. Anything touching unfamiliar silicon or a vendor NDA should be read as the top of its band, not the middle. Re-derive these before planning against them.

## Three prerequisites gate most of the list

Almost nothing below is "just firmware." Sort the work by which of these it waits on.

### P1 — The silicon migration is the largest un-costed item in the program

Tier 2 migrates to the **Ambiq Apollo510B** per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified). The tier-1 firmware is **Embassy on Rust targeting the Nordic nRF52840** per [§ 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance), and the two are not the same platform in any layer that touches hardware:

- **No official Embassy HAL exists for Ambiq Apollo** (as of this writing — verify at design time; Apollo510 is recent and its SDK is C-first with much of the reference code NDA-gated per [`bom.md`](bom.md)). Embassy's time driver, interrupt executor, and every `embassy-nrf` peripheral abstraction — UARTE, TWIM, SPIM, SAADC, PWM, NVMC, GPIO SENSE — would need an Ambiq equivalent. That is a HAL project, not a port.
- **The radio changes stack.** `nrf-softdevice` (S140) is Nordic-proprietary. The Apollo510B has an integrated BLE 5.4 network processor with an entirely different host-controller story, so `app/src/tasks/ble.rs`, the bonding/`BND1` path, and `nrf_softdevice::Flash` all get rewritten.
- **Cortex-M55 + Helium (MVE)** replaces Cortex-M4F. The firmware is deliberately float-light and integer-first, so this is upside (Helium is what makes on-MCU map rendering plausible) rather than a porting cost — but the toolchain target changes.

**What survives the migration intact, and this is the good news:** `watch_core` (~85 modules, no peripherals, no allocator), `watch_render`, and the four driver crates are all `no_std` and hardware-abstracted by construction — the drivers speak `embedded-hal` traits, not nRF registers. The 2026-07-25 extraction pass that moved task decisions out of `app/` and into host-tested `watch_core` modules ([§ 316](../architecture/decisions.md), [§§ 324–330](../architecture/decisions.md)) shrank the non-portable surface to roughly **4.5k lines** of `app/` task orchestration. That work now reads as migration insurance that nobody bought it as.

**Size: XL.** Everything else in this doc is cheaper than this, and most of it is easier *after* it.

### P2 — Four BOM parts tier 1 does not carry

Tier-1's parts list ([`parts.md`](parts.md)) is MCU + GNSS + display + optical HR + baro + LiPo. The [BOM](bom.md) adds these at tier 2/3, and each unlocks features that cannot be written against nothing:

| Part | In BOM | Unlocks |
|---|---|---|
| **Bosch BMI270 IMU** | yes (§ Magnetometer + accelerometer) | cadence, running dynamics, incident detection, sleep/wear detection, GNSS-gap dead reckoning |
| **Bosch BMM350 magnetometer** | yes (same line) | a real compass — tier 1 derives heading only over ≥5 m of movement, so a stationary runner honestly gets `--` |
| **16 GB SPI NAND** | yes (~$3–5) | offline maps, and a run store that holds an actual ultra instead of 253 records |
| **Haptic motor / buzzer** | **no — absent from the BOM entirely** | every alert the runner must not miss |

**The missing haptics line is a real gap, not an oversight to paper over.** Tier-1 alerts are display-only, which the README acknowledges ("the DK has no vibration motor"), and a fried runner at hour 60 in a headlamp beam will miss a screen banner. Three tier-2 items (metronome, pace/distance/time alerts, incident detection) are pointless without a haptic channel, and the ultra-critical drink/eat reminders are materially weakened. **Add a haptic driver + its power budget to the BOM at tier-2 design time** — an LRA plus a driver IC is a sub-dollar part and a small firmware task, but it needs a power-tree line and an enclosure coupling path, so it must be designed in rather than bolted on.

### P3 — The external flash store replaces the tier-1 slot store

Tier-1 storage is 4 × 4 KiB internal-flash slots, 253 records per run, decimating when full (run-store v2). An ultra is ~360k points and days off-grid. The external NAND arrives with **LittleFS** per [`bom.md`](bom.md), which makes this a new store, not a bigger one: wear levelling, a real filesystem, a retention/eviction policy, and a migration path for the `run_store` wire format (already at v3, with a version gate and recover-compat both sides — so the format is ready for a v4, and the Dart mirror plus both golden vectors must move with it).

**Size: M** for the store itself, on top of P1 and P2's NAND.

## The tier-2 items

Ordered by dependency, not by value. "Reuse" names what already exists in the tree — this is where the third parity rail pays off.

### Architectural obligations (must land before a field tester holds the device)

| Item | Size | Blocked on | Reuse / notes |
|---|---|---|---|
| **OTA via a dual-bank bootloader** ([§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default)) | **L** | P1 | MCUboot is the default candidate; the choice is made at tier-2 design time but the obligation is fixed. Needs a signing story, an A/B partition map, a rollback trigger, and a phone-side transfer path — the `run_chunk` protocol is the nearest existing shape but a firmware image is far larger and must be atomic. Nothing in tier 1 prepares this; tier-1 ships no OTA deliberately. |
| **PMTiles vector rendering on the MCU** ([§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash)) | **XL** | P1, P2 (NAND) | The single biggest software item anywhere in the program — a constrained subset of MapLibre's algorithm shape on a Cortex-M55. Reuse is real but partial: `watch_render` already owns clipped primitives (Cohen–Sutherland line clipping landed in [§ 327](../architecture/decisions.md)), `route_simplify` is a working Douglas-Peucker, `track_projection` and `nav_map` do lat/lng→panel projection with the cos(mid-lat) correction, and the Nav page proves a polyline renders legibly in a 168×96 band. What does not exist: tile decode, a label engine, layer styling, zoom management, or a tile-cache eviction policy against NAND. Budget it as its own project with its own plan. |

### Recording and on-run guidance

| Item | Size | Blocked on | Reuse / notes |
|---|---|---|---|
| **Pace / distance / time alerts** — **LANDED 2026-07-26** | **S** | P2 (haptics, to deliver well) | `watch_core::alerts` already owns the whole engine — one display slot, 8 s TTL, priority ordering, a re-queueing superseded alert, moving-time-banked cadence, once-per-excursion hysteresis. These are new alert *kinds* in an existing engine, and the settings frame already carries configurable fuel intervals. |
| **Activity profiles** (Run / Trail / Ultra / Hike) | **M** | — | Per-profile defaults plus a per-profile page set. The pieces exist: the page cycle is already **filtered** by a `pages_mask` intersecting data-present pages with a phone-curated set ([§ 284](../architecture/decisions.md) + [§ 286](../architecture/decisions.md)), and `CFG1` already persists config across a power cycle. A profile is largely a named mask plus a GNSS-mode and alert-cadence preset — so this is mostly plumbing an existing selector, not new machinery. |
| **Climb detection / ClimbPro-style ascent view** | **M** | — | New firmware logic with **no web helper to port** — live climb segmentation (start/end of an ascent, remaining vert in *this* climb) off the barometric stream. `elevation` gives calibrated altitude with a GPS-baro complementary filter and a moving gate, `roadbook` gives per-leg vert on a pushed course, and `MiniProfile` renders a series. The segmentation state machine is the actual work, and it should be written phone-side first per [§ 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) — a new algorithm does not get pioneered on the watch. |
| **Structured / interval workout execution** | **M** | — | The reference is the app's runner state machine ([`workout_execution.md`](../features/workout_execution.md)); `watch_core::guided_runs` is the ported scripted-cue neighbour (no page wired yet, an easy **S** on its own). The workout itself needs a push path — the `SET1`/`CRS1` precedent means a `WKT1` frame is a well-trodden shape, and both are CRC-guarded and version-gated. |
| **Metronome / cadence target** | **S** | P2 (**haptics** and IMU) | Trivial firmware over a real cadence source and a haptic channel; impossible without either. Blocked on hardware, not on difficulty. |
| **Course climb-profile graph** — **LANDED 2026-07-26** | **M** | — | The gap between the two elevation surfaces that shipped: the run's own sparkline (`Page::ElevationProfile`) and the pushed course's numbers (`Page::RouteElev`). `MiniProfile` and `route_elevation` both exist, **but `RouteElevView` carries only `gain_m` / `loss_m` / `points` — there is no course elevation series on the watch at all**, so the series has to be pushed: a `CRS1` version bump with v1 still decoding, a fixed-capacity `heapless` series inside the point budget, and the Dart mirror plus golden vectors moved on both sides. Sized **S** on this doc's first pass, which was wrong — the render was the small half. |

### Navigation, sensors, connectivity

| Item | Size | Blocked on | Reuse / notes |
|---|---|---|---|
| **Compass / bearing** | **S** | P2 (magnetometer) | Hard calibration and tilt compensation are the real work, not the maths. Tier 1's `trackback` already renders a relative direction arrow and blanks it honestly when heading is stale — a magnetometer replaces the movement-derived heading behind an existing surface. |
| **BLE sensor pairing** (HR strap, foot pod) | **M** | P1 (radio stack) | The watch is a GATT **server** today; a strap makes it a **central** as well — a dual-role radio config, standard HR/RSC service clients, and a pairing UI on a four-button no-touch device. The retag from T1/T2 to T2 is in `roadmap.md`: no strap is in the tier-1 parts list. |
| **HR broadcast** | **S** | P1 (radio stack) | The inverse of the above, and simpler: advertise the standard HR service and notify. `hr_duty`'s honest-staleness contract must carry through — never broadcast a reading the wrist itself would blank. |
| **ANT+ sensor pairing** | **M** | P1 (radio stack) | Downgraded in value by [`vendor_research.md`](vendor_research.md): Garmin discontinued the adopter program in 2025, docs are free, no fees, new profiles frozen. So ANT+ is now **best-effort legacy compatibility against a frozen protocol**, with BLE as the primary rail. On the nRF52840 this meant the S340 SoftDevice; on Apollo510B the path needs re-establishing. Do it after BLE pairing, or not at all. |
| **Single- vs dual-band GNSS selection** | **S** | P1, and the receiver swap to Sony CXD5610 / Airoha AG3335M | The mode surface, its persistence, the per-mode cadence, and the receiver power-down all shipped at tier 1. Band selection is one more axis on an existing selector — but the tier-1 MAX-M10S is L1-only, so there is nothing to select against until the receiver changes. |
| **Offline vector maps** (the feature row) | — | = the PMTiles renderer (XL) + NAND + a tile pipeline | Not a separate item; sized above. The tile *pipeline* (region selection on the phone, PMTiles archive transfer to NAND, per-region download management) is a further **L**, and it is phone-and-backend work more than firmware. |

### Training, safety, lifecycle

| Item | Size | Blocked on | Reuse / notes |
|---|---|---|---|
| **Rolling training load (CTL / ATL / TSB)** | **S** | — | `training_load` is ported and the single-run stress half is wired; the rolling window needs multi-day history the watch does not hold, so it stays a phone push into an existing `NOT SYNCED` page — the `set_fitness` / `set_readiness` precedent. Upgrading `compute_stress` from the distance model to TRIMP needs an HR-threshold sync, also **S**. |
| **Live spectator tracking** | **M** | — | The watch half of the transport exists: `link::status_frame` notifies once per second, and `live_freshness` is ported. The work is phone-side — forward the frame into the shipped live pipeline instead of the dev Sim Watch screen, and get the reconnect/gap semantics right so a spectator sees honest staleness rather than a frozen dot. Mostly mobile work, and the privacy posture noted under `roadmap.md § Smaller considerations` must land with it. |
| **Resting HR / HRV status** | **L** | P2 (IMU for wear/sleep detection), AFE capability | Requires all-day wear, which is a direct tension with [`vision.md`](vision.md)'s "a tool for the run, not the day" thesis and with the power budget. Decide whether it is in the product before sizing it further. |
| **Incident detection + emergency-contact alert** | **M** | P2 (IMU **and** haptics), phone bridge | Fall/stop detection plus an escalation path with a cancel window — which is why haptics are load-bearing: an alert the runner cannot feel cannot be cancelled, and a false positive that pages a contact is worse than no feature. Safety-critical, so it wants the phone-first treatment and a deliberate false-positive budget. |

## Sequencing

Six phases. Each is a stopping point that leaves a coherent device, which matters because §71 triggers can un-fire.

1. **Bench-verify tier 1 first.** Issue #597, the [bench checklist](quality_standards.md#tier-1-bench-verification-checklist), and real PPK2 numbers folded back into `gnss_mode`'s projections. Doing tier-2 work on an un-bench-verified base means porting unvalidated assumptions onto unfamiliar silicon.
2. **Close the BOM gaps on paper** — add haptics, confirm IMU + magnetometer + NAND, and re-verify the Apollo510B Rust/Embassy story before committing to the migration. Cheap, and it decides the shape of everything after.
3. **P1, the silicon migration** (XL). Everything else is easier after it and most of it is wasted before it.
4. **The cheap wins that were waiting on P1/P2** — HR broadcast, compass, metronome, rolling load. Four items on this list turned out to need *neither* prerequisite and were pulled forward on 2026-07-26 ahead of tier 2: pace/distance/time alerts ([§ 332](../architecture/decisions.md)), the `guided_runs` page ([§ 333](../architecture/decisions.md)), the course climb-profile graph ([§ 334](../architecture/decisions.md)), and #607's required-pace port. What is left in this phase genuinely waits on the silicon or the BOM. It remains the batch that makes the device feel finished.
5. **The obligations** — OTA (L) and the external-flash store (M). Both must precede a field tester: no OTA means every fix is a cable, and the tier-1 slot store cannot hold an ultra.
6. **The map subproject** (XL) plus its tile pipeline (L), run as its own plan. This is the feature the whole §85 BOM commitment exists for, and it is the one most likely to be misjudged.

Ordering note: items 4 and 5 can run in parallel with 6 by different hands, but nothing in 3–6 should start before 1.

## What is not in here

**T3 items stay in [`roadmap.md`](roadmap.md)** and are deliberately unsized: turn-by-turn routing on a routable map, data-screen and watch-face customisation, running dynamics beyond cadence, SpO2, satellite SOS, smart notifications, music, payments, sleep/stress. Several are gated on hardware or partnerships rather than effort, and sizing them now would be false precision.

**Hardware, mechanical, and RF work** — PCB CAD, case CAD, antenna design, IPX certification, drop tests — is out of scope for this doc and remains gated per [`apps/custom_watch/CLAUDE.md`](../../apps/custom_watch/CLAUDE.md).

## Open questions to resolve at tier-2 design time

Landing here rather than in `roadmap.md § Open questions` until a trigger fires, at which point they should move there or become `decisions.md` entries.

| OQ | Question |
|---|---|
| **T2-OQ1** | Does a usable Rust/Embassy path to Apollo510B exist, or does the migration mean writing a HAL — and if so, is that still cheaper than the [§ 80](../architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) Zephyr/C fallback for tier 2 specifically? § 80's fallback clause was written about a *blocking driver issue*, not about a whole-platform port; this deserves its own decision rather than an inherited one. |
| **T2-OQ2** | Haptics: LRA or ERM, which driver IC, and what does the power budget give up for it? |
| **T2-OQ3** | Retention policy for the NAND run store — how many runs, evicted how, and what does the wrist show when it is full? Tier 1's answer (decimate, sacrifice synced runs first) is a good precedent but does not scale to a filesystem. |
| **T2-OQ4** | Is all-day wear in the product at all? It decides resting HR / HRV, sleep, and a large share of the power budget, and it cuts against `vision.md`'s framing. |
| **T2-OQ5** | Does ANT+ earn its keep now that the protocol is frozen and BLE is the primary rail? |

## Pinning

- **Gating decision:** [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) (three triggers), lens [§ 92](../architecture/decisions.md#92-custom-watch-decisions-optimise-for-tier-3-production-quality-period--scope-and-effort-are-not-constraints).
- **Obligations sized here:** [§ 84](../architecture/decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default) (OTA), [§ 85](../architecture/decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) (map renderer), [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) (Apollo510B).
- **Backlog this sizes:** [`roadmap.md § Feature parity backlog`](roadmap.md#feature-parity-backlog-garmin--coros-table-stakes).
- **Verification vocabulary:** [`quality_standards.md`](quality_standards.md) — nothing in this doc is verified at any rung; it is planning.
