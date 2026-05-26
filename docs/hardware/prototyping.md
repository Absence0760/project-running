# Prototyping — three honest cost tiers

"How much to build one working unit" depends entirely on what *working* means. Three tiers, with real numbers.

## Tier 1 — Bench prototype ($500–$2k, 3–6 months)

A working device that records a GPS track and a heart rate sample, displays distance and pace, and uploads to the Supabase backend on a button press. Ugly. Not wearable in any practical sense. Lives on a desk and on a Velcro strap for the occasional jog.

### What you buy

| Part | Price |
|---|---|
| Nordic nRF52840 dev kit (PCA10056) | $50 |
| u-blox MAX-M10S GPS breakout board (SparkFun) | $40 |
| Sharp Memory LCD breakout (1.3" LS013B4DN04) | $35 |
| MAX86177 optical HR eval board (Maxim MAXREFDES220) | $130 |
| Bosch BMP390 breakout (Adafruit) | $15 |
| LiPo battery 500 mAh + JST connector | $10 |
| Tactile buttons + breadboard + jumpers | $20 |
| **Hardware subtotal** | **~$300** |
| Toolchain (J-Link debugger, Saleae logic analyzer, soldering iron upgrade) | $400–800 |
| Misc dev tools (3D printer access for case, Velcro, FTDI adapters) | $200–500 |
| **Total** | **$1k–2k** |

### What "working" means at this tier

- GPS fix in <60s outdoor, logs NMEA at 1Hz
- Optical HR sample at 25Hz, displays current bpm
- Battery powers the system for ≥8 hours continuous GPS (the dev board itself burns most of the budget)
- BLE connects to a paired phone running the app, syncs a finished run to Supabase
- 3D-printed enclosure that holds the boards together and straps to a wrist

### What it doesn't do

Look like a watch. Be water-resistant. Have decent antenna performance (breakout boards have poor RF tuning). Last more than a single run on a charge.

### Your time

Realistic for a competent embedded developer: **3–6 months of evenings and weekends**, ~200–400 hours total. If you've never written firmware before, double that. The Nordic SDK is well-documented; the GNSS NMEA parser is a weekend; integrating MAX86177's HR algorithm is the multi-week timesink.

### Value of completing tier 1

You learn whether you actually like doing this, you build the firmware skeleton that ports forward, and you produce a thing you can hold up to demonstrate progress. Most projects that get to tier 1 stop there — which is fine, and saves the cost of finding out the hard way at tier 2.

## Tier 2 — Wearable prototype ($15k–40k DIY, $80k–250k consultant-built, 9–18 months)

A device shaped like a watch. Fits on a wrist comfortably. Has buttons that feel like buttons. Looks plausible in photos. Roughly the polish level of an early-stage Kickstarter prototype.

### What changes from tier 1

| Line item | DIY cost | Consultant cost |
|---|---|---|
| Custom 4-layer PCB design (schematic + layout) | $2–5k EDA tools / your time | $30–80k |
| PCB fabrication, small run (10–20 boards) | $1–3k | $1–3k (same fab) |
| PCB assembly (low-volume, hand-place or stencil) | $2–5k | $2–5k |
| Industrial design (case CAD, button feel, strap mount) | Your time + Fusion 360 | $15–40k |
| Mechanical engineering (tolerances, IPX rating, drop test) | Your time | $10–30k |
| **RF / antenna tuning** (the unsexy killer) | $5–15k for a couple of weeks of consultant time | $15–50k |
| Firmware bring-up (BSP, drivers, basic UI) | Your time, 4–8 months | $50–150k |
| Case prototyping (CNC aluminium or SLA print, expect 3–5 iterations) | $500–3k per iteration | $500–3k per iteration |
| Display (sourced from Sharp via distributor, low qty) | $80–150 per unit | $80–150 per unit |
| Custom battery (small batch, no custom tooling — off-the-shelf cell sized close) | $30–80 per unit | $30–80 per unit |
| **Total to first working wrist unit** | **$15–40k cash + 12+ months of your time** | **$80–250k cash + 9–12 months** |

### Why RF is the line item that surprises everyone

A GNSS antenna in a 45mm metal case is genuinely hard. The antenna needs ≥-160 dBm sensitivity at L1+L5, the case acts as a Faraday cage, and the user's wrist absorbs ~3 dB of signal. Getting from a working breakout-board GPS fix to a working in-case GPS fix typically takes **2–6 weeks of an RF engineer's time** with a calibrated chamber. Skipping this step means the watch loses fix every time you turn your wrist.

The DIY path here is "find an RF consultant on Upwork or via the Hackaday community for ~$150/hr." The consultant path is "Pluga RF Engineering or similar firm, ~$300–400/hr, full chamber characterisation, deliverable is an antenna design file."

### What "working" means at this tier

- Looks like a watch in a photo. Friends ask "is that a Garmin?"
- 100% reliable GPS fix outdoors, ≥50% reliable fix under light foliage
- ≥24hr GPS battery life (still well short of the 100hr target — that needs the Apollo4 + custom battery shape, which is tier 3)
- Splashproof but not swimmable
- Pairs with the app, syncs runs, displays course overlay

### What it doesn't do

Pass IPX7 (proper sealing requires injection-moulded case + gasket tooling). Hit the battery target. Look like a production unit under a magnifying glass. Be safely worn in a real ultra-marathon (no certified water seal, no shock tolerance verified, no field-tested antenna).

## Tier 3 — VC-demo prototype ($300k–600k, 18–24 months)

Indistinguishable from a real production watch unless you take it apart. Proper enclosure tooling, IPX7 sealed, dual-band GNSS working in foliage, the Sharp MIP display, custom battery cell shaped to the case, sapphire crystal, 5-button layout that survives a 1.5m drop test. This is what you'd hand to a buyer at REI or a Kickstarter video producer.

### Where the money goes (beyond tier 2)

| Line item | Cost |
|---|---|
| Injection mould tooling (case) | $25–50k |
| Sapphire crystal tooling | $15–30k |
| Custom battery cell tooling (specific pouch shape) | $8–15k |
| Button + gasket tooling | $10–20k |
| Migration from nRF5340 to Ambiq Apollo4 (firmware port, NDA paperwork, new toolchain) | $40–80k |
| Migration from MAX-M10S to Sony CXD5610 (NDA, new firmware integration, RF re-tune) | $30–60k |
| IPX7 certification testing | $5–10k per design iteration, expect 2–3 iterations |
| Drop / vibration / thermal cycling certification | $15–30k |
| FCC + CE + IC pre-compliance scans + final cert | $20–40k |
| 100-unit production-intent run for field testing | $30–60k |
| Field test programme (10–20 ultra athletes, 6 months of usage data) | $20–40k cash + huge logistics overhead |
| **Total** | **$300–600k cash, 18–24 months calendar** |

### Why "one unit" doesn't make sense at this tier

Most of the cost is **one-time tooling that only makes sense if you're going to make 5,000+ units**. Building "one tier-3 unit" is a category error — the tooling cost gets allocated against the production run. If you stop after 1 unit you've effectively spent $300–600k on that one watch.

A more honest framing: tier 3 is the **first production-intent unit**, with the assumption that units 2–100 from the same tooling cost ~$300 each in materials and assembly. The "first unit" cost is the tooling amortisation; the ongoing cost is BOM + assembly + margin.

### What "working" means at this tier

Indistinguishable from a Garmin Fenix at arm's length. Survives a real 100mi ultra. Hits the 100hr GPS target. Charges via inductive pad. Maps load. Course breadcrumb works. The thing you'd ship.

## Recommended path

For one person investigating whether this is worth doing:

1. **Tier 1 first.** $1–2k, evenings and weekends, 3–6 months. Most of the value of the whole exercise is here — you find out whether you actually enjoy firmware development on this scale, and you build the codebase that ports forward.
2. **If still in love after tier 1, get a tier-2 budget approved before starting it.** Tier 2 is the bridge that determines whether tier 3 is worth doing. Plan on $30k cash + 12 months if you're doing the engineering yourself, more if you're hiring it out.
3. **Tier 3 is not a one-person project.** Even with $500k in the bank, you need a small team: 1 EE, 1 ID, 1 mech-E, 1 RF consultant on retainer, 1 firmware lead. The right way to enter tier 3 is with seed funding and a co-founder who has shipped consumer hardware before.

The honest assessment for this project specifically: **the app is the moat, not the hardware**. Every dollar spent on hardware is a dollar not spent on the software stack that already differentiates us. The hardware path exists as a research baseline so we know what we'd be saying yes to — not as a recommendation.
