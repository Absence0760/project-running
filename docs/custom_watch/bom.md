# BOM — component picks per subsystem

Per-subsystem component choices with the reasoning, and the rejected alternatives. Prices are **single-unit / small-qty** from Digi-Key or Mouser unless flagged otherwise — production pricing at 10k+ units typically lands 40–60% of these numbers.

> **Caveat — verify before procurement.** The specific model-number suffixes below (e.g. `AMA4B2KP-KXR`, `CXD5610GF`, `LS013B7DH06`, `BMM350`) are *representative* picks against vendor family pages, not parts we've sampled or received a quote for. Several of the GNSS, optical-HR, and display SKUs sit behind distributor NDAs or evolve faster than this doc. Before any procurement step, re-verify the exact part number, package, lifecycle status (active vs NRND), and stock against the vendor's current datasheet — and treat any "Garmin uses part X" line below as plausible-from-public-teardowns, not as a sourced quote.

## Application MCU

| Part | Why | Trade |
|---|---|---|
| **Ambiq Apollo4 Blue Plus (AMA4B2KP-KXR)** | Sub-threshold voltage design — 4µA/MHz active, ~3µA sleep with RTC. ARM Cortex-M4F + BLE 5.1 in one package. Used by Fitbit Charge 6, Garmin Venu 3, Huawei Watch GT series. ~$8 single-qty, ~$4 at 10k+ | Limited public SDK; most reference code is under NDA. Zephyr support is good, FreeRTOS support is excellent |
| *Alt: Nordic nRF5340* | Easier toolchain (Nordic SDK + Zephyr both first-class), dual-core M33, BLE 5.4. ~$6 single-qty | ~3–5x the active current of the Apollo4 — costs us ~20–40 hours of GPS battery life on the same cell. Right pick for a *bench prototype*, wrong pick for the shipping product |
| *Alt: STM32WB55* | Cheapest at ~$5, well-documented | Higher idle current; ST's wearable reference designs are weak |

**Pick: Apollo4 for the shipping product, nRF5340 for the bench prototype** (the Nordic dev board is 10x easier to bring up and the firmware will mostly port across).

## GNSS receiver

| Part | Why | Trade |
|---|---|---|
| **Sony CXD5610 family** | Dual-band L1+L5, multi-constellation (GPS+GLONASS+Galileo+BeiDou+QZSS), ~9 mA tracking, ~25 mA acquisition (vendor datasheet). Sony GNSS silicon is widely reported in modern Garmin Fenix / Enduro / Forerunner teardowns; the specific Sony part per model is harder to verify without a teardown of our own. ~$12 single-qty | Sony sells through reps; getting datasheet + sample under NDA takes ~4 weeks. No hobbyist breakout boards exist |
| *Alt: u-blox dual-band wearable part* | u-blox's roadmap includes low-power dual-band parts beyond the current single-band MAX-M10S, with strong multipath rejection in canyons — likely the right answer if Sony is unsourceable, but the specific SKU and availability need verification with a u-blox FAE before relying on this | Pricing typically higher than Sony at our volumes |
| *Alt: u-blox MAX-M10S* | Single-band L1 only, $8, easy to source, mature SDK, dev boards everywhere | **Disqualifying** for the ultra niche — the whole selling point is dual-band foliage accuracy. Fine for the bench prototype, not the shipping product |
| *Alt: Quectel L96 / Mediatek MT3333* | Cheap (~$4), commodity | Single-band only; the parts every $50 fitness band uses |

**Pick: Sony CXD5610 for shipping; MAX-M10S for the bench prototype** (same trade-off as the MCU — get the firmware working on cheap parts first, then port).

## Optical heart rate

| Part | Why | Trade |
|---|---|---|
| **Maxim MAX86177** | Industry-leading optical-HR AFE — 4-LED, 2-PD, sub-µA standby, on-chip motion-artifact preprocessing. Used by several premium wearables. ~$6 single-qty | Algorithm IP needs licensing or in-house DSP work. Raw signal alone won't beat the tuned pipelines the incumbents have iterated on for years |
| *Alt: Goodix GH3026* | Used by Huawei, Honor, several mid-tier wearables. Cheaper at ~$3, mature drivers | Documentation is China-first; English datasheets exist but are partial. Algorithm IP almost always sourced from Goodix themselves under licence |
| *Alt: PixArt PAH8011* | Cheapest viable optical HR at ~$2 | Single-LED — measurably worse in low-perfusion conditions (cold weather, dark skin tones) |

**Pick: MAX86177.** Optical HR is the second-most-common complaint about cheap watches (after battery); cutting cost here is false economy. Also: support **ANT+ chest strap pairing** as a first-class option — the people we're building for already own a strap.

## Barometric altimeter

**Bosch BMP390** — ±3 Pa noise, ~3 µA in normal mode. ~$4 single-qty. This is the de facto standard part for outdoor wearables; no meaningful alternative worth listing. The BMP581 is newer but the BMP390 is cheaper and equally accurate for our use.

## Magnetometer + accelerometer

**Bosch BMI270 (IMU) + BMM350 (magnetometer)** — combined ~$5. Garmin / COROS use the Bosch sensor stack. The alternative is ST's LSM6DSV16X + LIS2MDL which is equivalent in spec and very slightly cheaper; either is fine, pick on local distributor stock.

## Display

| Part | Why | Trade |
|---|---|---|
| **Sharp Memory LCD LS013B7DH06 (1.34", 168×144, 8-colour)** | What Garmin Fenix uses. Static power ~10 µA, transmissive (readable in direct sun without backlight), no refresh between frame changes. The only display technology that survives the "100hr GPS" battery target | Low colour gamut (8 colours), ~10Hz refresh ceiling — no smooth animations, no video. Looks "old" next to AMOLED in a side-by-side demo |
| *Alt: AMOLED (BOE / Visionox 1.4" 466x466)* | Beautiful, bright, full colour, what Apple Watch / Pixel Watch / Galaxy Watch use. ~$30–60 | Always-on draws 10–30 mA — kills the battery target. Direct sun washes it out unless brightness is cranked, which compounds the problem |
| *Alt: Reflective TFT (Sharp LS027B7DH01)* | Larger, more pixels, same MIP technology family | Higher current than the LS013 series; only useful if we want a bigger watch face |

**Pick: Sharp Memory LCD.** This is the single decision that most makes-or-breaks the battery target. AMOLED is what Apple does because they're not optimizing for ultra runners.

## Battery

| Part | Why | Trade |
|---|---|---|
| **Custom Li-Po pouch cell, ~600 mAh, 3.7V nominal** | Sized to fill the case. Fenix 7X is ~640 mAh; we'd be in the same envelope. Tooling for a custom shape is ~$8–15k one-off; per-unit cost ~$4 at 10k | Custom cells lock you to one supplier (typically Varta, Murata, or one of the Shenzhen majors). MOQ usually 5–10k units |
| *Alt: Off-the-shelf coin cell (Renata CR2032)* | $0.50, no tooling | ~250 mAh — kills the battery target. Only useful for the bench prototype |
| *Alt: 18650 cylindrical cell* | Cheap, high capacity (3500 mAh), available everywhere | Wrong form factor — too thick for a wrist device. Some early COROS prototypes apparently used these strapped to the forearm |

**Pick: custom Li-Po pouch for shipping; CR2032 + Nordic dev board for the bench prototype.**

## Case + crystal + buttons

Per [decisions.md § 81](../decisions.md#81-custom-watch-input-is-5-physical-buttons-in-the-garmin-fenix-layout-no-touchscreen), the production watch ships with **exactly 5 buttons in the Garmin Fenix 7 / Enduro 3 arrangement** (left side: LIGHT, UP, DOWN; right side: START/STOP, BACK/LAP), **no touchscreen**, no capacitive overlay, no touch controller IC. Tier-1 bench prototype uses the nRF52840 DK's 4 onboard buttons; production button mapping lands when there's a custom PCB.

This is where the budget actually goes once you get serious. A CNC-machined titanium case (Fenix 7X Sapphire), sapphire crystal, and 5 buttons with proper IPX7 sealing is **~$80–120 in materials and assembly per unit** at small production volumes, dropping to ~$40–60 at 10k+. The tooling to get there:

- Industrial design + mechanical engineering: ~$30–80k one-off
- Injection mould tooling (if we go polymer body instead of titanium): ~$25–50k one-off
- Sapphire crystal tooling: ~$15–30k one-off
- Button + gasket tooling: ~$10–20k one-off (5 buttons × overmoulded silicone gasket — proven 20-year design on Garmin Fenix)

This is the largest single line item that *cannot* be borrowed from a dev board. Reference designs don't ship as case-included.

## Connectivity

- **Bluetooth LE 5.x** — built into the Apollo4 / nRF5340. Used for phone sync, ANT+ via the nRF52840's multi-protocol radio if we go Nordic
- **WiFi 802.11n** (optional, +$3 BOM) — only useful for direct-to-cloud sync without a phone. Garmin shipped this on the Fenix 7 family and most users never use it. **Skip for the first product**
- **NFC** (optional, +$2 BOM) — Garmin Pay equivalent. **Skip; out of scope for ultra niche**

## Total BOM estimate

At 10k unit production volume:

| Category | Cost |
|---|---|
| MCU + flash + DRAM | $7 |
| GNSS module + antenna | $11 |
| Optical HR + IMU + baro + mag | $9 |
| Display | $14 |
| Battery + BMS | $5 |
| Case + crystal + buttons + strap | $50 |
| PCB + assembly | $8 |
| Misc (connectors, passives, packaging) | $6 |
| **Total** | **~$110** |

Retail at $549 gives a ~5x BOM multiplier — standard for consumer electronics (Apple Watch is ~4–4.5x). That leaves room for marketing, channel margin (40% to REI / running specialty retailers), and the first 2–3 years of firmware development before unit economics get good.

At 1k unit production volume the BOM roughly doubles (~$200) which is why the cost-down curve only kicks in above ~5k units. The first production run almost certainly loses money on every unit.
