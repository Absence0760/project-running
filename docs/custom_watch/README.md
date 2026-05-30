# custom_watch — research baseline for an ultra-marathon watch

Research-stage docs for a possible **own-hardware** watch built for ultra-marathon use (100km / 100mi events, multi-day FKTs, backcountry self-supported running). The app is the canonical software surface today and stays so; these docs only describe the path *if* we ever commit to building our own wrist device to compete with Garmin Fenix / COROS Vertix in the ultra niche.

The bench-prototype firmware workspace lives at [`apps/custom_watch/`](../../apps/custom_watch/README.md) — paired with this directory by design so that strategic + research docs sit next to (but separate from) the code. Most of this folder is *research, not commitment*; only the active parts list ([`parts.md`](parts.md)) and the workspace under `apps/custom_watch/` are live.

| Doc | What it answers |
|---|---|
| [roadmap.md](roadmap.md) | Current status across tier 1 / tier 2 / tier 3, the three strategic vectors (Connect IQ / Wear OS / ODM), the per-step bring-up checklist, and the open planning questions still to resolve. **Read this first to orient.** |
| [vision.md](vision.md) | Why ultra (not road / triathlon / smartwatch general-purpose), the product requirements that fall out of that niche, and what we'd be competing against |
| [competitive_landscape.md](competitive_landscape.md) | Frank read on Garmin / COROS / Suunto — what they're unbeatable on, what their real faults are, where you can credibly win, and the three asymmetric strategic vectors (Connect IQ app, Wear OS app, ODM partnership) that beat "build your own watch" |
| [bom.md](bom.md) | Concrete component picks per subsystem (MCU, GNSS, optical HR, baro, display, battery, case) with the reasoning for each, plus the rejected alternatives |
| [prototyping.md](prototyping.md) | Three honest cost tiers — DIY bench prototype, wearable prototype, "VC demo" prototype — with dollar ranges, timelines, and what "working" means at each |
| [performance_path.md](performance_path.md) | Where the watt-hours actually come from — big levers (display, MCU, GNSS, coprocessor) vs medium (DMA, tickless, partial display, power tree, BLE tuning) vs the small levers that don't move the needle (RTOS, language, compiler) |
| [firmware.md](firmware.md) | Why a custom RTOS on a low-power MCU beats Wear OS for ultra battery life, and how the watch would integrate with the existing Supabase backend. Note: this doc was written as the Zephyr proposal; the actual firmware decision (§80) picked Embassy on Rust — see the banner at the top of the doc for the supersession |
| [parts.md](parts.md) | Active tier-1 shopping list — MCU dev kit + sensor breakouts + bench tools, with order checkboxes for received items |

## Status

Strategic content (vision, competitive landscape, BOM, prototyping cost tiers, performance path, firmware architecture) is **research, not commitment**. Numbers come from vendor datasheets + public teardowns + cost ranges quoted by EE/ID consultants — not from any quote we've requested. Before this becomes a project, every number needs a real quote and every component needs a sourcing path verified at the quantity we'd actually buy.

The *current default* — to stay an app + watch-app company and not start hardware work — is recorded in [decisions.md § 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely), along with the three triggers that would re-open the question. The 2026-05-28 amendment to §71 permits **owner-personal tier-1 bench-prototype work**; the active workspace for that code lives at [`apps/custom_watch/`](../../apps/custom_watch/README.md) and the active parts list lives at [`parts.md`](parts.md) in this directory. Tier 2+ remains gated on the original triggers.
