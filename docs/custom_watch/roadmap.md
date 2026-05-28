# Roadmap — custom_watch

The big-picture sequencing for the ultra-marathon watch research effort. Separate from the main app's [`docs/roadmap.md`](../roadmap.md) because the watch has its own multi-tier hardware-investment sequence that doesn't map onto the main app's phased product roadmap. Read alongside [`competitive_landscape.md`](competitive_landscape.md) (strategic framing), [`prototyping.md`](prototyping.md) (the three cost tiers), and [`decisions.md § 71 / § 80 / § 81`](../decisions.md) for the locked decisions.

**This doc is live.** Update the per-tier checkboxes + status snapshot as work progresses; resolve open questions into `decisions.md` entries as they're decided.

## Status snapshot (2026-05-28)

- **Tier 1 (bench prototype)**: workspace scaffolded; no parts ordered; no on-board verification yet.
- **Tier 2 (wearable prototype)**: gated on the three [§ 71](../decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) triggers; not active.
- **Tier 3 (production-intent unit)**: gated on the same triggers; not active.
- **Vector 1 (Connect IQ app)**: not started.
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

### Definition of Done

Per [decisions.md § 82](../decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype): tier 1 is complete when **one real outdoor run produces a GPS+HR-tagged track that syncs to Supabase** from the bench prototype end-to-end. No power-budget bar (separate question — see [OQ3](#oq3-power-measurement-methodology) below).

## Tier 2 — wearable prototype (gated)

**Goal.** A device shaped like a watch, sized for the wrist, ≥24hr GPS battery, 100% outdoor fix reliability. Polish level of an early Kickstarter prototype.

**Budget.** $15–40k DIY or $80–250k consultant-built + 9–18 months calendar.

**Re-opening triggers** (per [§ 71](../decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)):

- [ ] **Trigger (a)** — app has a paying user base large enough to fund a parallel hardware effort.
- [ ] **Trigger (b)** — an existing ODM (Mobvoi, Amazfit, Polar) approaches us about a white-label deal.
- [ ] **Trigger (c)** — a co-founder with shipped-consumer-hardware experience joins.

### Long-lead-time pre-validation (worth starting even while tier 2 is gated — see [OQ7](#oq7-vendor-relationship-pre-validation))

- [ ] **Sony CXD5610** — datasheet + sample under NDA. ~4 weeks lead time.
- [ ] **Maxim MAX86177 HR algorithm** — licensing terms + per-unit cost at our volumes.
- [ ] **ANT+ Alliance adopter application** — open question whether Garmin (owner of ANT+) will sell adoption rights to a direct competitor.

## Tier 3 — production-intent unit (gated)

**Goal.** Indistinguishable from a Garmin Fenix at arm's length. The first unit you'd ship to a paying customer.

**Budget.** $300–600k cash + 18–24 months calendar + a small team (1 EE, 1 ID, 1 mech-E, 1 RF consultant, 1 firmware lead).

**Triggers.** Same as tier 2 + a working tier-2 wearable prototype.

## Strategic vectors — alternatives to building our own

Per [`competitive_landscape.md`](competitive_landscape.md), three vectors beat "build your own watch from scratch" if the asymmetric play is the goal. Listed in order of cost / risk:

### Vector 1 — Connect IQ app or data field for existing Garmin owners

| Field | Value |
|---|---|
| Status | Not started |
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

These are the unsettled planning calls from the 2026-05-28 audit pass. Listed in roughly the order they bottleneck other decisions. Each is a candidate for a future `decisions.md` entry.

### OQ3: Power-measurement methodology

How do we know we're meeting the performance budget at tier 1, given the DK can't measure realistic ultra-watch power? Options:

- **(a)** Buy a Nordic Power Profiler Kit II (~$120) — measures sub-µA on a test rig wired between the DK and its USB power input.
- **(b)** Proxy metrics — measure sleep-current, peripheral-active-current, GPS-fix-current via PPK2 on isolated subsystems; project tier-2 power from those.
- **(c)** Accept blindness — defer real measurement to tier-2 silicon. Risk: don't discover the architecture misses the budget until tier 2.

### OQ4: OTA architecture decision

Per [`firmware.md`](firmware.md) open Q#3, OTA must be in v1.0 or shipped units can't be updated. Tier 1 doesn't implement OTA, but flash-layout decisions made now affect it. Options:

- **(a)** Adopt MCUboot — Embassy ecosystem has integration; production-proven dual-bank bootloader.
- **(b)** Roll our own dual-bank bootloader — more work, more risk, no clear benefit unless MCUboot has a specific gap.
- **(c)** Declare "tier-1 units are throwaway; no OTA design needed yet." Defer the decision to tier 2. Acceptable if we don't ship tier-1 to anyone.

### OQ5: Map renderer + format

Per [`firmware.md`](firmware.md) open Q#1, vector-map rendering on a Cortex-M4F is a multi-month firmware project. Tier 1 doesn't need maps, but BOM flash size depends on the choice. Options:

- **(a)** Build a PMTiles parser + minimal renderer — multi-month firmware project, max flexibility, 16+ GB flash.
- **(b)** Pre-bake vector tiles into a simpler intermediate (compressed line/polygon arrays per zoom level) — less flexible than PMTiles but tractable to render on M4F.
- **(c)** Punt to raster tiles — worse zoom-in quality, reduce flash to ~4GB, accept the segment-laggard reputation on map UX (the thing both Garmin and COROS are bad at — see [`competitive_landscape.md`](competitive_landscape.md)).

### OQ6: Strategic-vector sequencing

Is tier 1 the only thing happening, or does vector 1 (Connect IQ app) run in parallel? Vector 1 is the cheapest market test of our software differentiation — arguably should be the #1 priority, not the #4. Options:

- **(a)** Sequential — finish tier 1 first, then start vector 1.
- **(b)** Parallel — start vector 1 *now*, alongside tier 1.
- **(c)** Vector-1-first — pause tier 1 until vector 1 has shipped + collected feedback, then resume.

### OQ7: Vendor relationship pre-validation

Should we email Sony / Maxim / ANT+ Alliance now, or wait until tier 1 demonstrates serious intent? Lead times are real (Sony ~4 weeks); zero cost to start emails. Options:

- **(a)** Email all three now — establish the relationships, get the licensing/sampling pipeline started.
- **(b)** Email Sony only now (longest lead time, no commercial commitment to start NDA conversation).
- **(c)** Wait until tier 1 produces something we can demo. Risk: tier-2 start gets delayed by the vendor lead times.

### OQ8: User research with actual ultra runners

[`competitive_landscape.md`](competitive_landscape.md) is built from forums + reviews + general pattern-matching. Worth interviewing 5–10 real ultra runners about their Garmin/COROS pain points before locking the product vision? ~10 hours, free, could validate or invalidate the whole thesis. Options:

- **(a)** Run the interviews before any more tier-1 work — feeds back into vision.md if findings disagree.
- **(b)** Run them in parallel with tier-1 firmware bring-up.
- **(c)** Skip — the competitive analysis is good enough as-is.

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
