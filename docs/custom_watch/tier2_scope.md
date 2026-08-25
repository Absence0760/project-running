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

**What survives the migration intact, and this is the good news:** `watch_core` (**98** modules, no peripherals, no allocator), `watch_render`, and the four driver crates are all `no_std` and hardware-abstracted by construction — the drivers speak `embedded-hal` traits, not nRF registers. The 2026-07-25 extraction pass that moved task decisions out of `app/` and into host-tested `watch_core` modules ([§ 316](../architecture/decisions.md), [§§ 324–330](../architecture/decisions.md)) shrank the non-portable surface to roughly 4.5k lines of `app/` task orchestration; it has since grown back to **~5.6k** as the radio, flash and screen rails landed, which is the number to watch — the extraction bought headroom, it did not install a ratchet. That work now reads as migration insurance that nobody bought it as.

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

Tier-1 storage is 4 × 4 KiB internal-flash slots, 253 records per run, decimating when full (the decimation arrived with run-store v2). An ultra is ~360k points and days off-grid. The external NAND arrives with **LittleFS** per [`bom.md`](bom.md), which makes this a new store, not a bigger one: wear levelling, a real filesystem, a retention/eviction policy, and a migration path for the `run_store` wire format — now at **v4** (`FORMAT_VERSION` 4, `MIN_FORMAT_VERSION` 3), the workout-results tags of [§ 356](../architecture/decisions.md) having ridden the same version-gate-plus-recover-compat machinery this row predicted, with the Dart mirror and both golden vectors moving in lockstep each time.

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
| **Activity profiles** (Run / Trail / Ultra / Hike) — **LANDED 2026-07-28** | **M** | — | Shipped as [decisions § 353](../architecture/decisions.md): a profile is a **macro** over the existing knobs — a curated `pages_mask` preset + a GNSS mode — selected from a fourth §351 menu row, CFG1-persisted, boot-re-applied. The alert-cadence axis this row once imagined was deliberately dropped (§24 — per-profile physiology would pioneer past web; the desert cadence case rides `SET1` `FLAG_FUEL`). |
| **Climb detection / ClimbPro-style ascent view** — **LANDED 2026-07-29** ([§ 359](../architecture/decisions.md)) | **M** | — | New firmware logic with **no web helper to port** — live climb segmentation (start/end of an ascent, remaining vert in *this* climb) off the barometric stream. Shipped as `watch_core::climb`: a hysteretic `ClimbDetector` (opens past 20 m of gain at ≥ 2 % grade, closes only after 10 m lost below the high point) riding the same altitude sample `feed_gap` already takes, plus `crest_ahead` reading the pushed course profile — which needed no new wire, since § 334's distance-even `CRS1` series and the nav task's along-course position were already on-device. The `CLMB` page heads the course cluster; sim-verified by the `terrain` scenario. |
| **Structured / interval workout execution** — **LANDED 2026-07-28** | **M** | — | `watch_core::workout` ports the mobile `WorkoutRunner` over pushed pre-expanded steps; the `WKT1` frame followed the `SET1`/`CRS1` precedent exactly (CRC-sealed from v1, chunked on a sixth characteristic, Dart goldens both sides); BTN5's lap doubles as step-skip; step banners ride the alert slot. See [§ 354](../architecture/decisions.md) + the roadmap row. Per-step results persistence followed 2026-07-29 (run-store v4, [§ 356](../architecture/decisions.md) — the trail lands in the flash blob attributed by the WKT1 frame CRC and syncs into `metadata.watch_workout`). The push transport itself is wired (same batch: `writeWorkout` on the sixth characteristic + `WatchSyncClient.pushWorkout` + a dev Sim Watch push action). What stays tier-2+: haptic step cues (no motor in the BOM), and the product push surface + `plan_workout_id` join that turns the stored trail into the review surface. `watch_core::guided_runs`, the scripted-cue neighbour, has had its own glance page since 2026-07-26. |
| **Metronome / cadence target** | **S** | P2 (**haptics** and IMU) | Trivial firmware over a real cadence source and a haptic channel; impossible without either. Blocked on hardware, not on difficulty. |
| **Course climb-profile graph** — **LANDED 2026-07-26** | **M** | — | The gap between the two elevation surfaces that shipped: the run's own sparkline (`Page::ElevationProfile`) and the pushed course's numbers (`Page::RouteElev`). `MiniProfile` and `route_elevation` both exist, but at the time this row was written **`RouteElevView` carried only `gain_m` / `loss_m` / `points` — there was no course elevation series on the watch at all**, so the series had to be pushed: a `CRS1` version bump with v1 still decoding, a fixed-capacity series inside the point budget, and the Dart mirror plus golden vectors moved on both sides. All of that landed — `RouteElevView` now also carries `total_m`, `samples: [i16; COURSE_PROFILE_CAP]` and `len`, and `CRS1` has since gone to v3 with a mandatory CRC ([§ 335](../architecture/decisions.md)). Sized **S** on this doc's first pass, which was wrong — the render was the small half. |
| **Daylight remaining / sunset countdown** — **LANDED 2026-07-28** | **S** | — | Shipped as [decisions § 355](../architecture/decisions.md): the S sizing held — pure computation off state already on-device (latitude from the fix, the RMC date newly carried on `Fix`, the `SET1` v2 timezone offset as the presence bit), the `safety_nudge.ts` seasonal-half port, one tall-hero glance page. The polar seasons cost two new `Unfed` variants the sizing hadn't priced; nothing else grew. |
| **Sleep-station mode** | **M** | P2 (haptics — a wake alarm the runner cannot feel is not a wake alarm) | The nap budget is `cutoff_eta`'s live margin minus a safety buffer over the roadbook's next leg — both shipped; the new work is the countdown surface, the wake escalation, and keeping the elapsed clock honest through the nap. Differentiation case in [`roadmap.md § Differentiation backlog`](roadmap.md#differentiation-backlog--where-we-can-beat-them). |
| **Backyard-ultra mode** | **M** | P2 (haptics for the 3/2/1 bell warnings; a display-only countdown is a degraded but shippable first cut) | Bell-anchored 60:00 countdown + loop count + corral-return margin, riding the existing lap machinery and the alerts engine; last-person-standing scoring semantics stay app-side. Differentiation case in [`roadmap.md § Differentiation backlog`](roadmap.md#differentiation-backlog--where-we-can-beat-them). |

### Navigation, sensors, connectivity

| Item | Size | Blocked on | Reuse / notes |
|---|---|---|---|
| **Compass / bearing** | **S** | P2 (magnetometer) | Hard calibration and tilt compensation are the real work, not the maths. Tier 1's `trackback` already renders a relative direction arrow and blanks it honestly when heading is stale — a magnetometer replaces the movement-derived heading behind an existing surface. |
| **Waypoint marking / save location** — **LANDED 2026-07-29** ([§ 357](../architecture/decisions.md)) | **S** | — | The geometry is `trackback`'s distance-and-bearing against a stored point; the real work was interaction. This row's own candidate — a § 351 settings-menu action — was **rejected on inspection**: the menu is idle-only, and the position worth saving is one the runner is standing on mid-run. The grammar had one gesture free after all, **BTN5's hold**. `watch_core::waypoints` is an eight-slot newest-wins store with a CRC-sealed `WPT1` codec persisted **on the press** in a config-page record beside `CFG1` / `BND1`, and the `WPT` page sits beside Back-to-start. |
| **BLE sensor pairing** (HR strap, foot pod) — **HR STRAP LANDED 2026-07-30 under an owner override** ([§ 365](../architecture/decisions.md)) | **S** (foot pod only) | — | This row used to read "the watch is a GATT **server** today; a strap makes it a **central** as well" — that stopped being true when `app/src/tasks/hr_strap.rs` shipped. The dual-role config is live (`tasks/ble.rs`: `periph_role_count: 1`, `central_role_count: 1`, two concurrent connections — phone *and* strap), the watch scans for the standard Heart Rate Service (0x180D), connects, and subscribes to Heart Rate Measurement notifications. **There is no pairing UI, and the earlier claim here that one "exists on the four buttons" was wrong twice over** — the device has five buttons, and strap pairing is not a wearer action at all: `app/src/tasks/hr_strap.rs:172` is an unconditional background loop that rescans on a `SCAN_GAP_S` timer, and none of the eight settings-menu rows is a strap row (`core/src/settings_menu.rs:111` — `GnssMode`, `HideEmpty`, `Profile`, `Backyard`, `PairPhone`, `Erase`, `QnhRezero`, `Ice`). The only wearer-visible trace is the HR-source tag on the face reading `STRAP` when the strap won arbitration (`core/src/face.rs:2487`). A row to arm, forget or prefer a strap is unbuilt work, not shipped work — size it here rather than assume it. `central_sec_count` stays 0 by design: a strap's HR service needs no encrypted link. What is left of this row is the **foot pod** (an RSC service client) — hence the resize from M to S. Note that nothing here is bench-verified: no hardware has executed `hr_strap.rs`, so the advertising-data filter, the connection, and the 31 KiB `memory-ble.x` reservation under two links are all unproven. |
| **HR broadcast** | **S** | P1 (radio stack) | The inverse of the above, and simpler: advertise the standard HR service and notify. `hr_duty`'s honest-staleness contract must carry through — never broadcast a reading the wrist itself would blank. |
| **ANT+ sensor pairing** | **M** | P1 (radio stack) | Downgraded in value by [`vendor_research.md`](vendor_research.md): Garmin discontinued the adopter program in 2025, docs are free, no fees, new profiles frozen. So ANT+ is now **best-effort legacy compatibility against a frozen protocol**, with BLE as the primary rail. On the nRF52840 this meant the S340 SoftDevice; on Apollo510B the path needs re-establishing. Do it after BLE pairing, or not at all. |
| **Single- vs dual-band GNSS selection** | **S** | P1, and the receiver swap to Sony CXD5610 / Airoha AG3335M | The mode surface, its persistence, the per-mode cadence, and the receiver power-down all shipped at tier 1. Band selection is one more axis on an existing selector — but the tier-1 MAX-M10S is L1-only, so there is nothing to select against until the receiver changes. |
| **Offline vector maps** (the feature row) | — | = the PMTiles renderer (XL) + NAND + a tile pipeline | Not a separate item; sized above. The tile *pipeline* (region selection on the phone, PMTiles archive transfer to NAND, per-region download management) is a further **L**, and it is phone-and-backend work more than firmware. |

### Training, safety, lifecycle

| Item | Size | Blocked on | Reuse / notes |
|---|---|---|---|
| **Rolling training load (CTL / ATL / TSB)** — **LANDED 2026-07-28** | **S** | — | Both halves shipped ([decisions § 352](../architecture/decisions.md)): the rolling trio as a whole-or-nothing `Recorder::set_load_trend` push into the TrainingLoad page (the `set_fitness` precedent), and `compute_stress` upgraded to TRIMP via the `SET1` v5 resting-HR sync plus a live time-weighted HR average banked beside zone time. |
| **Live spectator tracking** | **M** | — | The watch half of the transport exists: `link::status_frame` notifies once per second, and `live_freshness` is ported. The work is phone-side — forward the frame into the shipped live pipeline instead of the dev Sim Watch screen, and get the reconnect/gap semantics right so a spectator sees honest staleness rather than a frozen dot. Mostly mobile work, and the privacy posture noted under `roadmap.md § Smaller considerations` must land with it. |
| **Resting HR / HRV status** | **L** | P2 (IMU for wear/sleep detection), AFE capability | Requires all-day wear, which is a direct tension with [`vision.md`](vision.md)'s "a tool for the run, not the day" thesis and with the power budget. Decide whether it is in the product before sizing it further. |
| **Incident detection + emergency-contact alert** | **M** | P2 (IMU **and** haptics), phone bridge | Fall/stop detection plus an escalation path with a cancel window — which is why haptics are load-bearing: an alert the runner cannot feel cannot be cancelled, and a false positive that pages a contact is worse than no feature. Safety-critical, so it wants the phone-first treatment and a deliberate false-positive budget. |
| **ICE / medical-ID idle screen** — **LANDED 2026-07-29** ([§ 358](../architecture/decisions.md)) | **S** | — | A `SET1` extension carrying a few phone-synced strings plus one idle-face surface a medic can find. Shipped as `watch_core::ice`: five lines on **`SET1` v6** (which spent `flags2`'s last free bit — the next settings field is a compile error until the presence bytes grow) mirrored into an `ICE1` flash record, reached by BTN4's idle walk (home → diagnostics → ICE) and a `MEDICAL ID` menu row. Fail-closed harder than every other settings field: an over-long line, an undrawable byte, or a byte past a field's NUL refuses the **whole** card, because a clipped allergy reads as complete and a clipped number dials someone else. |

## Sequencing

Six phases. Each is a stopping point that leaves a coherent device, which matters because §71 triggers can un-fire.

1. **Bench-verify tier 1 first.** Issue #597, the [bench checklist](quality_standards.md#tier-1-bench-verification-checklist), and real PPK2 numbers folded back into `gnss_mode`'s projections. Doing tier-2 work on an un-bench-verified base means porting unvalidated assumptions onto unfamiliar silicon.
2. **Close the BOM gaps on paper** — add haptics, confirm IMU + magnetometer + NAND, and re-verify the Apollo510B Rust/Embassy story before committing to the migration. Cheap, and it decides the shape of everything after.
3. **P1, the silicon migration** (XL). Everything else is easier after it and most of it is wasted before it.
4. **The cheap wins that were waiting on P1/P2** — HR broadcast, compass, metronome. **Twelve** items on this list turned out to need *neither* prerequisite and were pulled forward ahead of tier 2: pace/distance/time alerts ([§ 332](../architecture/decisions.md)), the `guided_runs` page ([§ 333](../architecture/decisions.md)), the course climb-profile graph ([§ 334](../architecture/decisions.md)), #607's required-pace port (all 2026-07-26), the rolling training load + TRIMP upgrade ([§ 352](../architecture/decisions.md)) and activity profiles ([§ 353](../architecture/decisions.md), both 2026-07-28), then structured-workout execution ([§ 354](../architecture/decisions.md)), the Daylight countdown ([§ 355](../architecture/decisions.md)), waypoint marking ([§ 357](../architecture/decisions.md)), the ICE card ([§ 358](../architecture/decisions.md)), climb detection ([§ 359](../architecture/decisions.md)) and — the one that *did* look like it needed P1, and turned out not to, because the nRF52840's radio was already capable of the dual role — the HR strap's GATT central ([§ 365](../architecture/decisions.md), 2026-07-30). What is left in this phase genuinely waits on the silicon or the BOM. It remains the batch that makes the device feel finished.
5. **The obligations** — OTA (L) and the external-flash store (M). Both must precede a field tester: no OTA means every fix is a cable, and the tier-1 slot store cannot hold an ultra.
6. **The map subproject** (XL) plus its tile pipeline (L), run as its own plan. This is the feature the whole §85 BOM commitment exists for, and it is the one most likely to be misjudged.

Ordering note: items 4 and 5 can run in parallel with 6 by different hands, but nothing in 3–6 should start before 1.

## What is not in here

**T3 items stay in [`roadmap.md`](roadmap.md)** and are deliberately unsized: turn-by-turn routing on a routable map, **third-party** watch faces (a Connect IQ competitor, MicroPython or a DSL), running dynamics beyond cadence, SpO2, satellite SOS, smart notifications, music, payments, sleep/stress. *Data-screen customisation left this list on 2026-07-30* — see the `roadmap.md` row; the config half is built and only a phone-side authoring UI remains. Several are gated on hardware or partnerships rather than effort, and sizing them now would be false precision.

**Continuous programs are also deliberately unsized:** GNSS fix-quality tuning, optical-HR algorithm quality (licensing + tuning), and the field-validation corpus both tune against — all named in [`roadmap.md § Feature parity backlog`](roadmap.md#feature-parity-backlog-garmin--coros-table-stakes). They are practices that run for the life of the program, not items that complete.

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
