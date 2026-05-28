# BOM — component picks per subsystem

Per-subsystem component choices with the reasoning, and the rejected alternatives. Prices are **single-unit / small-qty** from Digi-Key or Mouser unless flagged otherwise — production pricing at 10k+ units typically lands 40–60% of these numbers.

> **Caveat — verify before procurement.** The specific model-number suffixes below (e.g. `Apollo510B`, `CXD5610GF`, `LS013B7DH06`, `BMP581`, `BMM350`) are *representative* picks against vendor family pages, not parts we've sampled or received a quote for. Several of the GNSS, optical-HR, and display SKUs sit behind distributor NDAs or evolve faster than this doc. Before any procurement step, re-verify the exact part number, package, lifecycle status (active vs NRND), and stock against the vendor's current datasheet — and treat any "Garmin uses part X" line below as plausible-from-public-teardowns, not as a sourced quote. Most recent BOM-currency audit: 2026-05-28 (see [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified)).

## Application MCU

| Part | Why | Trade |
|---|---|---|
| **Ambiq Apollo510B** | Cortex-M55 + Helium MVE @ 250 MHz, ~2× lower energy + ~10× lower latency than Apollo4 family. 4 MB MRAM + 3.75 MB SRAM, integrated 48 MHz BLE 5.4 network processor, secureSPOT 3.0. ~$10 single-qty, ~$5 at 10k+ | Apollo510 SDK + HAL maturity is ~12 months behind Apollo4 but stable since Q4 2025. Limited public SDK; most reference code under NDA |
| *Alt: Apollo510 Lite / Lite-B* | Lower-cost variants of the Apollo510 family. Sampling now with volume Q1 2026 | Drops some peripherals; cost-down path for a future SKU, not the launch SKU |
| *Alt: Apollo4 Blue Plus (AMA4B2KP-KXR)* | Previous-gen Ambiq pick. ~4 µA/MHz active, BLE 5.1. ~$8 / $4 | ~2× higher MCU energy than Apollo510B on the same workload; locks in last-gen silicon for a 2027+ product. Superseded per [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified) |
| *Alt: Nordic nRF5340* | Easier toolchain (Nordic SDK + Zephyr both first-class), dual-core M33, BLE 5.4. ~$6 single-qty | ~3–5× the active current of Apollo510B — costs material GPS battery life on the same cell. Right pick for a *bench prototype*, wrong pick for the shipping product |
| *Alt: STM32WB55* | Cheapest at ~$5, well-documented | Higher idle current; ST's wearable reference designs are weak |

**Pick: Ambiq Apollo510B for the shipping product, Nordic nRF52840 for the tier-1 bench prototype** per [§ 80](../decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) (Embassy + `nrf-softdevice` ecosystem maturity). Apollo4 → Apollo510B production-target swap codified in [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified).

## GNSS receiver

| Part | Why | Trade |
|---|---|---|
| **Sony CXD5610 family** | Dual-band L1+L5, multi-constellation (GPS+GLONASS+Galileo+BeiDou+QZSS), ~9 mA tracking, ~25 mA acquisition (vendor datasheet). Sony GNSS silicon is widely reported in modern Garmin Fenix / Enduro / Forerunner teardowns; the specific Sony part per model is harder to verify without a teardown of our own. ~$12 single-qty | Sony sells through reps; getting datasheet + sample under NDA takes ~4 weeks. No hobbyist breakout boards exist |
| *Alt: Airoha AG3335M* | 12 nm L1+L5 dual-band, wearable-optimised power envelope. Powers some Garmin / COROS-tier watches; Quectel LC29H module is built on it (easier sourcing via Quectel). Documented alt per [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified) | Performance close to Sony CXD5610 but with a more accessible vendor relationship if Sony NDA engagement stalls |
| *Alt: u-blox ZED-X20P* | All-band (L1/L2/L5/L6), sampling Apr 2025 | **Disqualifying for wearable use** — targeted at industrial / UAV / robotics; power envelope wrong for wrist. Listed only to flag it isn't the right pick despite being publicly visible |
| *Alt: u-blox MAX-M10S* | Single-band L1 only, $8, easy to source, mature SDK, dev boards everywhere | **Disqualifying** for the ultra niche — the whole selling point is dual-band foliage accuracy. Fine for the bench prototype, not the shipping product |
| *Alt: Quectel L96 / Mediatek MT3333* | Cheap (~$4), commodity | Single-band only; the parts every $50 fitness band uses |

**Pick: Sony CXD5610 for shipping; MAX-M10S for the bench prototype** (same trade-off as the MCU — get the firmware working on cheap parts first, then port).

## Optical heart rate

| Part | Why | Trade |
|---|---|---|
| **Maxim MAX86177** | Industry-leading optical-HR AFE — 4-LED, 2-PD, sub-µA standby, on-chip motion-artifact preprocessing. Used by several premium wearables. ~$6 single-qty | Algorithm IP needs licensing or in-house DSP work. Raw signal alone won't beat the tuned pipelines the incumbents have iterated on for years |
| *Alt: Goodix GH3026* | Used by Huawei, Honor, several mid-tier wearables. Cheaper at ~$3, mature drivers | Documentation is China-first; English datasheets exist but are partial. Algorithm IP almost always sourced from Goodix themselves under licence |
| *Alt: PixArt PAH8011* | Cheapest viable optical HR at ~$2 | Single-LED — measurably worse in low-perfusion conditions (cold weather, dark skin tones) |
| *Future upgrade: MAX86178* | Same family as MAX86177 + adds ECG + BioZ in one part; IEC 60601-2-47-compliant ECG channel; 0.5 µA shutdown. ~$8 single-qty | Documented upgrade path per [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified) for a future ECG-capable SKU (AFib screening, HRV-from-ECG). Not the launch pick — adds cost + ECG-electrode design complexity at tier 2 |

**Pick: MAX86177 for launch.** Optical HR is the second-most-common complaint about cheap watches (after battery); cutting cost here is false economy. Also: support **ANT+ chest strap pairing** as a first-class option — the people we're building for already own a strap. ECG-capable upgrade path via MAX86178 documented for a future SKU.

## Barometric altimeter

**Bosch BMP581** — capacitive pressure sensor. 1.3 µA @ 1 Hz (**~85% lower current than BMP390**), 80% lower noise, 33% lower temperature coefficient, 0.5 µA deep standby, ±0.1 hPa / 12-month drift. ~$4 single-qty. For an altimeter sampled continuously to drive ultra-marathon elevation-gain math, the lower noise + drift directly improves the user-visible elevation total at end-of-run. Swap from BMP390 codified in [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified).

*Alt: Bosch BMP390* — previous-gen piezoresistive sensor. ±3 Pa noise, ~3 µA in normal mode. Still in production; not a meaningful BOM-cost saving over BMP581 at the volumes that matter, and gives up the perf delta listed above.

## Magnetometer + accelerometer

**Bosch BMI270 (IMU) + BMM350 (magnetometer)** — combined ~$5. Garmin / COROS use the Bosch sensor stack. The alternative is ST's LSM6DSV16X + LIS2MDL which is equivalent in spec and very slightly cheaper; either is fine, pick on local distributor stock.

## External storage

**16 GB SPI NAND flash** — Macronix MX25R series, Winbond W25Q series, or equivalent. ~$3–5 BOM at tier-3 volumes (TSSOP-8 / WSON-8 package). Per [decisions.md § 85](../decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu-16-gb-external-nand-flash): required for the on-watch PMTiles map archives; LittleFS-formatted, partitioned for one global low-zoom tileset plus per-region high-zoom tilesets the user has explicitly downloaded.

Why not internal MCU flash: the Apollo4 + nRF52/nRF53 family tops out at ~2 MB internal flash. Map storage at vector-tile resolution needs gigabytes; external SPI NAND is the only path. The Sony CXD5610 GNSS chip uses the same SPI bus; routing is straightforward.

Why not a removable card (microSD): an SD slot interrupts the IPX7 sealing story, adds a mechanical failure mode, and signals "tinkerer's device" to non-technical buyers. Fixed-flash is the segment norm (Garmin Fenix, COROS Vertix — both 32 GB internal NOR/NAND).

**Second-source qualification:** Per [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified), qualify **GigaDevice GD5F** as a second-source at PCB design time. 2025–2026 NAND flash supply has 6–9 month lead times; single-sourcing the largest storage component risks an allocation event stalling a tier-2 build for months.

## Display

| Part | Why | Trade |
|---|---|---|
| **Sharp Memory LCD LS013B7DH06 (1.34", 168×144, 8-colour)** | What Garmin Fenix uses. Static power ~10 µA, transmissive (readable in direct sun without backlight), no refresh between frame changes. The only display technology that survives the "100hr GPS" battery target | Low colour gamut (8 colours), ~10Hz refresh ceiling — no smooth animations, no video. Looks "old" next to AMOLED in a side-by-side demo |
| *Alt: AMOLED (BOE / Visionox 1.4" 466x466)* | Beautiful, bright, full colour, what Apple Watch / Pixel Watch / Galaxy Watch use. ~$30–60 | Always-on draws 10–30 mA — kills the battery target. Direct sun washes it out unless brightness is cranked, which compounds the problem |
| *Alt / qualified backup: Sharp LS027B7DH01* | Larger (2.7", 400×240), same MIP family. Higher current than LS013 series; useful as a qualified backup if LS013 line goes NRND post-Mobara closure (March 2026 — see [§ 90](../decisions.md#90-bom-refresh-2026-05-28-apollo510b-bmp581-swap-ins-supply-alternates-qualified)) or if we want a bigger watch face | Watch case has to grow with the larger display |

**Pick: Sharp Memory LCD LS013B7DH06.** Single decision that most makes-or-breaks the battery target. AMOLED is what Apple does because they're not optimising for ultra runners. **Supply-chain action item:** request a Sharp lifecycle letter on LS013B7DH06 before tier-2 case-CAD tooling spend (~$30–80k commitment to the LS013 form factor); the JDI Mobara fab is closing March 2026 and the broader Sharp/JDI LCD footprint is contracting.

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
| MCU + internal flash + DRAM | $7 |
| GNSS module + antenna | $11 |
| Optical HR + IMU + baro + mag | $9 |
| External storage (16 GB SPI NAND) | $4 |
| Display | $14 |
| Battery + BMS | $5 |
| Case + crystal + buttons + strap | $50 |
| PCB + assembly | $8 |
| Misc (connectors, passives, packaging) | $6 |
| **Total** | **~$114** |

Retail at $549 gives a ~5x BOM multiplier — standard for consumer electronics (Apple Watch is ~4–4.5x). That leaves room for marketing, channel margin (40% to REI / running specialty retailers), and the first 2–3 years of firmware development before unit economics get good.

At 1k unit production volume the BOM roughly doubles (~$200) which is why the cost-down curve only kicks in above ~5k units. The first production run almost certainly loses money on every unit.
