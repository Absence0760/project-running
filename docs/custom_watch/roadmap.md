# Roadmap — custom_watch

The big-picture sequencing for the ultra-marathon watch research effort. Separate from the main app's [`docs/roadmap.md`](../roadmap.md) because the watch has its own multi-tier hardware-investment sequence that doesn't map onto the main app's phased product roadmap. Read alongside [`competitive_landscape.md`](competitive_landscape.md) (strategic framing), [`prototyping.md`](prototyping.md) (the three cost tiers), and [`decisions.md § 71 / § 80 / § 81`](../decisions.md) for the locked decisions.

**This doc is live.** Update the per-tier checkboxes + status snapshot as work progresses; resolve open questions into `decisions.md` entries as they're decided.

## Status snapshot (2026-05-28)

- **Long-term goal: [§ 92](../decisions.md#92-custom-watch-decisions-optimise-for-tier-3-production-quality-period--scope-and-effort-are-not-constraints) — build the best watch ever** (full Phase 0–5 optimal-road timeline in § 92's table). Tier-2+ decisions optimise for the tier-3 shipped product without effort or scope as valid counter-arguments.
- **Tier 1 (bench prototype)**: workspace scaffolded; no parts ordered; no on-board verification yet. **Stays on nRF52840 per [§ 80](../decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)** — deliberate first-prototype compromise per the [§ 92 Resolution](../decisions.md#resolution-2026-05-28--hybrid--92-long-term-goal---80-tier-1-preserved-as-deliberate-first-prototype-compromise) ("keep costs down and get a working version first").
- **Tier 2 (wearable prototype)**: gated on the three [§ 71](../decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) triggers; not active. Migrates to Apollo510B silicon per [§ 90](../decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified); MCUboot lands per [§ 84](../decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default); ANT+ Alliance per [§ 88](../decisions.md#88-vendor-engagement-is-tiered-across-project-maturity) Layer 3.
- **Tier 3 (production-intent unit)**: gated on same triggers; not active. The full Phase 0–5 vision per § 92.
- **Vector 1 (Connect IQ app)**: not started — runs parallel to tier-1 per [§ 87](../decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware).
- **Vector 2 (Wear OS app)**: `apps/watch_wear/` ships product features but isn't framed as a "Garmin alternative for sub-12hr runners" play.
- **Vector 3 (ODM partnership)**: no vendor conversations; no outreach.

## Tier 1 — bench prototype (active, owner-personal)

**Goal.** Prove the firmware skeleton works end-to-end against the existing Supabase backend on real silicon, and build the domain credibility for later ODM conversations.

**Budget.** ~$1–2k cash + 3–6 months of evenings/weekends.

Per the [§ 71 2026-05-28 amendment](../decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely), this is owner-personal investigation only; tier 2+ remains gated on the original triggers.

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

Per [decisions.md § 83](../decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem): a Nordic Power Profiler Kit II (PPK2, ~$120) is part of the tier-1 bench-tools kit. Used **per-subsystem** (bare-MCU sleep, GPS active/sleep, HR AFE sample, display refresh) rather than whole-device — the DK's onboard J-Link + LEDs burn ~30 mA at idle and make whole-device readings useless as a baseline. The per-subsystem numbers project to tier-2 / tier-3 power (see [`performance_path.md`](performance_path.md)). DoD doesn't require hitting any specific number; these measurements inform tier-2 planning, they don't gate tier-1 completion.

### Definition of Done

Per [decisions.md § 82](../decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype): tier 1 is complete when **one real outdoor run produces a GPS+HR-tagged track that syncs to Supabase** from the bench prototype end-to-end.

## Tier 2 — wearable prototype (gated)

**Goal.** A device shaped like a watch, sized for the wrist, ≥24hr GPS battery, 100% outdoor fix reliability. Polish level of an early Kickstarter prototype.

**Budget.** $15–40k DIY or $80–250k consultant-built + 9–18 months calendar.

**Re-opening triggers** (per [§ 71](../decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)):

- [ ] **Trigger (a)** — app has a paying user base large enough to fund a parallel hardware effort.
- [ ] **Trigger (b)** — an existing ODM (Mobvoi, Amazfit, Polar) approaches us about a white-label deal.
- [ ] **Trigger (c)** — a co-founder with shipped-consumer-hardware experience joins.

### Architectural obligations (must land before tier-2 prototype reaches a field tester)

- [ ] **OTA via a production-grade dual-bank bootloader.** [§ 84](../decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default) — MCUboot is the default candidate; the specific choice gets made at tier-2 design time but the obligation is fixed.
- [ ] **PMTiles vector renderer running on the MCU.** [§ 85](../decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) — multi-month firmware subproject (constrained subset of MapLibre's algorithm shape, port to Cortex-M4F + later Apollo4). 16 GB external SPI NAND flash committed in the BOM. Decision driven by [§ 86](../decisions.md#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) (end-state quality > engineering convenience).

### Vendor engagement (tiered per [§ 88](../decisions.md#88-vendor-engagement-is-tiered-across-project-maturity))

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

## Strategic vectors — alternatives to building our own

Per [`competitive_landscape.md`](competitive_landscape.md), three vectors beat "build your own watch from scratch" if the asymmetric play is the goal. Listed in order of cost / risk:

### Vector 1 — Connect IQ app or data field for existing Garmin owners

| Field | Value |
|---|---|
| Status | **Active, parallel to tier-1** per [§ 87](../decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware) |
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
| OQ1 + OQ2 | Tier-1 Definition of Done + kill criteria | [§ 82](../decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype) — one-outdoor-run DoD; explicitly no kill criteria |
| OQ3 | Power-measurement methodology | [§ 83](../decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem) — Nordic PPK2, per-subsystem |
| OQ4 | OTA architecture | [§ 84](../decisions.md#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default) — tier-1 no OTA; tier-2 obligated to a dual-bank bootloader (MCUboot default) |
| OQ5 | Map renderer + format | [§ 85](../decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) — full PMTiles + on-MCU vector rendering + 16 GB external NAND |
| OQ6 | Strategic-vector sequencing | [§ 87](../decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware) — vector 1 (Connect IQ app) runs in parallel with tier-1 |
| OQ7 | Vendor relationship pre-validation | [§ 88](../decisions.md#88-vendor-engagement-is-tiered-across-project-maturity) — tiered: research now, NDA post-prototype, commercial at tier-2 |
| OQ8 | User research with ultra runners | [§ 89](../decisions.md#89-skip-user-research-interviews-vector-1-install-rate-is-the-validation-channel) — skipped; vector-1 install rate is the validation channel |

**Decision-making meta-principle:** [§ 86](../decisions.md#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) (custom_watch picks optimise for end-state product quality, even at small margins).

## Smaller considerations

These are real but lower-leverage. Worth tracking; not blocking.

- **Privacy posture for the watch.** Watch records GPS, HR, biometrics. The rest of the product takes data minimization + retention + export seriously; the watch inherits nothing yet. Pull in the patterns from the main app (`docs/api_database.md`, `docs/dev_prod_isolation.md`) when tier 2 starts.
- **Tier-1 budget cap formalization.** § 71 amendment lifts the spend cap but doesn't say "tier-1 spend over $X requires re-asking." Easy to drift past $1–2k without noticing.
- **Local-store overflow behaviour.** Tier-1 records to LittleFS — but how big does the local store get before we start dropping runs? Architectural choice; matters for ultra runners who go off-grid for days.
- **Tier-1 development log + showcase plan.** Tier 1's stated deliverable is "knowledge + a credible technical story for ODM conversations." Without a written log + photos/video, that knowledge stays in your head. Suggested: `docs/custom_watch/tier1_log.md`, photographed at each milestone.
- **Watch face customization architecture.** Per [`firmware.md`](firmware.md) open Q#4 — almost certainly out of v1.0 scope but worth designing the UI layer with the customization hook in mind. Decide which Embassy UI primitives stay decoupled.
- **No external issue tracker.** All planning lives in markdown. Fine while it's one person; gets messy fast if anyone else joins. GitHub Projects board is the cheapest pivot.

## Pinning

- **Locked decisions:** [§ 71](../decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) (deferral + amendment), [§ 80](../decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) (firmware stack), [§ 81](../decisions.md#81-custom-watch-input-is-5-physical-buttons-in-the-garmin-fenix-layout-no-touchscreen) (input).
- **Active workspace:** [`apps/custom_watch/`](../../apps/custom_watch/README.md).
- **Strategic / spec references:** [`vision.md`](vision.md), [`competitive_landscape.md`](competitive_landscape.md), [`bom.md`](bom.md), [`prototyping.md`](prototyping.md), [`performance_path.md`](performance_path.md), [`firmware.md`](firmware.md).
- **Active checklist:** [`parts.md`](parts.md).
