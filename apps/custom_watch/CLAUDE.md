# custom_watch — AI session notes

**Pure Rust + Embassy firmware** for an ultra-marathon-optimised wrist device
research prototype. Targets the Nordic nRF52840 DK at tier 1. Not Flutter,
not Kotlin, not Zephyr — see
[../../docs/decisions.md § 80](../../docs/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)
for why.

## Scope — read before writing code

**This is research-tier, owner-personal investigation. Not a product.** See
[../../docs/decisions.md § 71](../../docs/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)
(the original deferral) and its 2026-05-28 amendment (permits tier-1 bench-
prototype firmware code on owner-personal evenings-and-weekends, nothing
more). Everything in this directory is **research scaffolding** — not a
green-lit app SKU, not a roadmap line item, not customer-facing.

**Build here:**

- Tier-1 bench-prototype Rust firmware: Embassy tasks, hand-rolled drivers
  for the Sharp MIP / MAX86177 / u-blox NMEA breakouts that don't have
  community Rust crates, GATT-server bring-up via `nrf-softdevice`.
- Firmware-architecture work that ports forward to production silicon:
  DMA-driven I/O, async tasks, coprocessor-split design, partial display
  updates, aggressive sleep. See
  [../../docs/custom_watch/performance_path.md](../../docs/custom_watch/performance_path.md)
  for which patterns matter at tier 2+ and which don't move the needle.
- Driver crates under `drivers/<sensor>/` that we'd reuse if we ever ported
  to a custom PCB. Independently testable, no `app/` dependencies.
- Host-side unit tests (`cargo test`) for any pure-logic crate (NMEA
  parser, recording state machine, signal-processing helpers).

**Don't build here:**

- PCB CAD, schematic files, EAGLE / KiCad projects, case CAD, gerbers.
  These are tier-2+ work and remain gated on the three §71 triggers
  (paying user base, ODM approach, hardware co-founder). The 2026-05-28
  amendment did *not* lift this.
- RF antenna designs, IPX certification testing, FCC / CE pre-compliance
  scans, drop tests. Also tier-2+.
- C / Zephyr code. The §80 decision picked Rust + Embassy; the fallback
  to Zephyr is documented in §80 but takes effect only if we hit a
  blocking driver issue that takes more than two weeks to resolve in Rust.
- Anything that implies the watch is a shipping product — marketing copy,
  product-page work, App Store / Play Store metadata, customer-facing
  documentation. The repo has none of that for this directory and
  shouldn't acquire any until §71 triggers flip.
- Schema-synced row types. Watch-to-Supabase sync is tier-2+ integration
  work per [`../../docs/custom_watch/firmware.md`](../../docs/custom_watch/firmware.md);
  no `generated/db_rows.rs` exists yet and shouldn't until that sync
  ships.
- Anything that pioneers a product feature not yet on web. Per
  [`../../docs/decisions.md` § 24](../../docs/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive),
  web is the canonical feature surface for the product. Firmware here
  is for *bench-prototype investigation of the hardware path*, not for
  proving out new product features (a novel recording-algorithm variant,
  a different training-load model, a coach behaviour the web app doesn't
  have). Pioneering happens on web first — same rule as the other watch
  apps.

## Where the research lives

| Concern | File |
|---|---|
| Strategic framing — why ultra, who we'd compete with, where we can credibly win | [../../docs/custom_watch/competitive_landscape.md](../../docs/custom_watch/competitive_landscape.md) |
| Product vision — ultra niche + the 10 product requirements that fall out of it | [../../docs/custom_watch/vision.md](../../docs/custom_watch/vision.md) |
| Concrete BOM — chip picks per subsystem, ~$110 production BOM at 10k units | [../../docs/custom_watch/bom.md](../../docs/custom_watch/bom.md) |
| Cost tiers — $1–2k bench, $15–250k wearable, $300–600k production-intent | [../../docs/custom_watch/prototyping.md](../../docs/custom_watch/prototyping.md) |
| Firmware architecture + Supabase-integration design (Zephyr fallback spec) | [../../docs/custom_watch/firmware.md](../../docs/custom_watch/firmware.md) |
| Where battery life actually comes from (big / medium / small levers) | [../../docs/custom_watch/performance_path.md](../../docs/custom_watch/performance_path.md) |
| Tier-1 active parts list / shopping checklist | [../../docs/custom_watch/parts.md](../../docs/custom_watch/parts.md) |

For status + next-steps + the active workspace layout, see
[`README.md`](README.md) in this directory.
