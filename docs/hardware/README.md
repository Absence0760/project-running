# Hardware — ultra-marathon-optimized watch

Research-stage docs for a possible **own-hardware** watch built for ultra-marathon use (100km / 100mi events, multi-day FKTs, backcountry self-supported running). The app is the canonical software surface today and stays so; these docs only describe the path *if* we ever commit to building our own wrist device to compete with Garmin Fenix / COROS Vertix in the ultra niche.

Nothing in this folder is committed-to. It exists so that a future "should we?" conversation has a real cost / parts / firmware baseline to argue against, instead of being relitigated from scratch.

| Doc | What it answers |
|---|---|
| [vision.md](vision.md) | Why ultra (not road / triathlon / smartwatch general-purpose), the four product requirements that fall out of that niche, and what we'd be competing against |
| [bom.md](bom.md) | Concrete component picks per subsystem (MCU, GNSS, optical HR, baro, display, battery, case) with the reasoning for each, plus the rejected alternatives |
| [prototyping.md](prototyping.md) | Three honest cost tiers — DIY bench prototype, wearable prototype, "VC demo" prototype — with dollar ranges, timelines, and what "working" means at each |
| [firmware.md](firmware.md) | Why a custom RTOS (Zephyr / FreeRTOS) on a low-power MCU beats Wear OS for ultra battery life, and how the watch would integrate with the existing Supabase backend |

## Status

Every doc here is **research, not commitment**. Numbers come from vendor datasheets + public teardowns + cost ranges quoted by EE/ID consultants — not from any quote we've requested. Before this becomes a project, every number needs a real quote and every component needs a sourcing path verified at the quantity we'd actually buy.

The *current default* — to stay an app + watch-app company and not start hardware work — is recorded in [decisions.md § 71](../decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely), along with the three triggers that would re-open the question. No hard decision has been made; this folder exists so a future "should we?" conversation argues against a real cost / parts / firmware baseline rather than starting from scratch.
