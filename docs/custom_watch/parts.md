# Parts list — tier 1 bench prototype

Single shopping list for building the tier-1 bench prototype from scratch. Total ~$1k–$2k including tools. Sourced from the cost analysis in [`prototyping.md`](prototyping.md).

Order numbers / vendor SKUs below are starting points — re-verify stock + current price + lifecycle status at the vendor before ordering. See also the procurement caveat at the top of [`bom.md`](bom.md). Prices last checked **2026-08-17**; the audit that set them is recorded in [`tier1_log.md`](tier1_log.md).

**Every row here is checked against the firmware that will drive it**, not against the BOM's production picks — the two diverge on purpose (§ 90 names production silicon; tier 1 uses what has a driver and a debugger). Where a part needs configuring before it will talk to this firmware at all, that is stated in the row and repeated in [`quality_standards.md`](quality_standards.md)'s step-0 checklist. Do not substitute a "close enough" part: the drivers gate on chip IDs and fixed framebuffer dimensions, and a mismatch presents at the bench as a dead subsystem rather than as an error message.

## MCU + sensor breakouts (~$300)

| Part | Vendor / order number | Price | Notes |
|---|---|---|---|
| Nordic nRF52840 DK (PCA10056) | Mouser / Digi-Key / Adafruit / Nordic direct | ~$49 | Tier-1 MCU. Onboard Segger J-Link debugger over USB — no separate debugger needed. Has a Li-Po connector (J6/P27) and an SW9 power-source switch, so the cell below needs no adapter; the Li-Po position feeds the SoC's high-voltage regulator, which is the path the battery-gauge bench item needs. ANT+ available via the S340 multi-protocol SoftDevice. Production target migrates to **Ambiq Apollo510B** per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) — see [bom.md](bom.md). Chosen over the nRF5340 DK at this tier for Embassy / `nrf-softdevice` maturity |
| u-blox MAX-M10S GNSS breakout | **SparkFun GPS-18037** ("GNSS Receiver Breakout — MAX-M10S (Qwiic)") — **4 in stock at SparkFun on 2026-08-17**, so buy this one early or line up a distributor | ~$46 | Single-band L1 only. **Wire the UART pins, not the Qwiic connector** — the firmware reads NMEA on UARTE0 and sends UBX-RXM-PMREQ on its TX; the I²C path is unimplemented. Carries an MS621FE backup cell (BBR holds a fix + config ~2 weeks unpowered), which is why the firmware runs at the module's factory baud rather than a configured one ([§ 622](../architecture/decisions.md)). Production target migrates to Sony CXD5610 (NDA part) |
| Sharp Memory LCD 1.3" 168×144 breakout (LS013B7DH05) | Adafruit 3502 ("SHARP Memory Display Breakout — 1.3" 168x144 Monochrome") | ~$25 | The MIP display family Garmin Fenix uses. SPI, write-only, 3 KB framebuffer the MCU must hold. Static draw ~10 µA. **Resolution is load-bearing:** `drivers/sharp_mip` hard-codes a 168×144 framebuffer (`framebuffer.rs` `WIDTH`/`HEIGHT`), so a different panel silently corrupts every line-update address. Do **not** order LS013B4DN04 — that is the 96×96 panel (Adafruit 1393), obsolete/EOL. Ships with a header strip to solder |
| Bosch **BMP581** breakout | Adafruit **6407** ("BMP581 I2C or SPI Temperature and Pressure Sensor [STEMMA QT]") | ~$13 | Barometric altimeter. **Not the BMP390** this list used to name: `drivers/bmp581` gates on `CHIP_ID == 0x50` at register `0x01`, and a BMP390 answers `0x60` at `0x00` with an unrelated register map, so it fails the probe and parks the baro task — taking elevation, vert, the storm page and the GAP grade with it. Matches [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified)'s production pick, so tier 1 and tier 2 now share a driver |
| **MAX30101** optical-HR breakout | SparkFun `SEN-16474` **or** Pimoroni `PIM438` — see the sourcing note below, both were out at their own shops on 2026-08-17 | ~$20–34 | Optical HR, decided at [§ 623](../architecture/decisions.md). **MAX30101, not MAX30102** — the 30102 is red + IR only (a fingertip SpO2 part) and the **green** LED the 30101 adds is the one every wrist sensor reads a moving capillary bed with. MAX30105 is an acceptable sibling. I²C `0x57`, 400 kHz; the breakout regulates its own 1.8 V rail and steps up the LED supply, so it takes the DK's 3.3 V directly. Register map is **public**, so the silicon is the same whoever assembles the board |
| LiPo battery 500 mAh + JST-PH 2-pin | Adafruit 1578 | ~$10 | For runs off the dev-board, into the DK's Li-Po connector. Confirm the DK's J6/P27 pitch against the cell's JST-PH before assuming it seats |
| LiPo charger | Adafruit 1304 ("Micro Lipo — USB LiIon/LiPoly charger v2") | ~$7 | **The DK supplies from a Li-Po but does not charge one.** Without this the 500 mAh cell is single-use and the "percent falls monotonically across a discharge" bench item can only be run once. Ships with its own JST cable |
| Momentary tactile pushbutton (BTN5) | Generic 6mm through-hole, any breadboard assortment | ~$1 | The §350 grammar uses five buttons and the DK has four; BTN5 (manual lap / waypoint hold) is an external momentary from **P0.02 to GND** on the header — the firmware's internal pull-up means no resistor. Unwired, the lap key is simply dead (idle-high), so the rest of the grammar works without it |
| Breadboard + jumper wires + headers | Generic (Adafruit / SparkFun / Amazon) | ~$20 | Half-size breadboard, ~30× male-male + male-female jumpers, a strip of 0.1" male headers |

### Sourcing the HR breakout — the one line that needs care at checkout

A correction to an earlier reading of this. "The register map is public, so the vendor does not matter" is true of the *silicon* and misleading as *shopping advice*, because the commodity market for these modules is dominated by the **MAX30102** — the red/IR part with no green emitter. A cheap board listed as a "MAX3010x heart rate sensor" is far more likely to be the wrong one than the right one, and the two are visually near-identical.

`drivers/max30101` refuses a MAX30102 on its `PART_ID` (0x15) before writing a register, so a mis-shipped part surfaces as an honest `hr: AFE init failed WrongPart(..)` rather than as a plausible wrong pulse. That is the right failure, and it still costs the money and the shipping time. So:

- **Buy a board whose listing names the MAX30101 explicitly**, and prefer one with a schematic or a hookup guide behind it — SparkFun `SEN-16474` and Pimoroni `PIM438` both qualify, and both are carried by second-tier distributors (Opencircuit, Melopero, Botland, Mouser, Farnell) even when their own shops and Digi-Key show zero.
- **Do not buy on price alone from a marketplace listing.** The saving is a few pounds; the cost of guessing is a reorder and a fortnight.
- A **MAX30105** is a genuine substitute — same green emitter, near-identical map — but its `PART_ID` differs, so the driver will refuse it until that value is added. Cheap to do, worth knowing before it arrives rather than after.

### Before you wire it — the four things that cost a bench day

Each of these is a mismatch between a part's out-of-the-box state and what the firmware expects. All four are one-time, none is a defect, and all four present as *silence* rather than as an error.

1. **The BMP581 answers on the wrong address by default.** `drivers/bmp581` uses **0x46**; the Adafruit 6407 ships at **0x47**. Tie its `SDO` pin to GND (or solder the `addr` jumper on the back closed) before expecting a probe to succeed.
2. **The display's silkscreen does not use the datasheet's pin names.** `EIN` is EXTMODE, `EMD` is EXTCOMIN — the two the firmware drives for hardware VCOM. `DISP` needs no MCU pin (the panel runs from CLK/DI/CS alone), which is why the board crate has no pin for it. The breakout pulls EXTMODE low for software VCOM; the firmware drives it high, and a weak pull-down does not fight a push-pull GPIO — but confirm on the schematic that it is a resistor and not a strap.
3. **The GNSS module talks at 38400.** That is the M10 factory default and, since [§ 622](../architecture/decisions.md), what the firmware is configured for. If someone has previously set the module to another rate in u-center, reset it to defaults rather than changing the firmware — a BBR-held setting expires with the backup cell.
4. **Nothing on the HR line, as ordered.** The MAX30101 breakout regulates its own 1.8 V rail and steps up its LED supply on-board, so it takes the DK's 3.3 V directly. Noted because the part it replaced did not: the bare Maxim AFEs want a 1.8 V main supply against the DK's 3.0 V VDD, which would have made their I²C a level-shifting problem rather than a jumper-wire one. That is a live concern again if the [§ 623](../architecture/decisions.md) decision is ever revisited toward the production family.

### The optical-HR line — decided 2026-08-17, and what it owes

**Decision: a commodity MAX30101 breakout, recorded at [§ 623](../architecture/decisions.md).** The reasoning and the deltas the port must honour are there; this section keeps the procurement history that produced it, because the failure mode is worth not repeating.

The part this list named since the beginning was the **MAX86177**, and three separate problems stacked on it. It is on the critical path — [§ 82](../architecture/decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype)'s DoD requires a run recording **GPS + HR** — and the third problem is the one that decided it:

- **`MAX86177EVSYS#` is not a breakout.** Analog Devices ships it as two boards: `MAXSENSORBLE_EVKIT_B`, a data-acquisition motherboard with its own MCU, BLE radio and Windows GUI, plus `MAX86177_OSB_EVKIT_A`, the sensor daughterboard (six LEDs, eight SFH2704 photodiodes, an accelerometer) that mates to it over a board-to-board connector rather than a 0.1" header. The earlier "~$130 sensor breakout" framing here was wrong about the form factor as well as the price.
- **It is hard to buy.** Digi-Key lists it *Discontinued at Digi-Key*, 0 in stock, backorders not accepted, no lead time quoted.
- **Its register map is NDA-gated, and always was.** [`vendor_research.md`](vendor_research.md) established this on 2026-07-09: no public MAX86177 datasheet exists, and ADI's own EV-kit page says complete documentation follows an NDA. So `drivers/max86177`'s register addresses and configuration values are **modelled on the family idiom, not read off this part's datasheet** — buying the kit would not, on its own, make that driver correct. That finding never reached this file, the roadmap, or the driver's own doc comment, which is why the parts list kept naming the part as though it were ready to wire.

**What resolved it:** the MAX86177 is a *production* pick ([`bom.md`](bom.md)) that got imported into tier 1 without ever being argued for at tier 1. § 82 asks for a run that records HR — it explicitly accepts "raw photodiode reads + naive peak-detect" and puts the licensed Maxim algorithm after tier 1. It does not ask for the launch-pick AFE, so choosing the tier-1 part on tier-1 grounds is in scope, and § 90's production row is untouched.

The two options not taken, kept because they are the right answers to different questions:

- **`MAXREFDES280#` (~$191, stocked)** — a wrist-worn PPG band carrying the **MAX86171**, with a full public datasheet including the register map. Stays in the Maxim wrist-AFE family and the band form factor suits a wearable prototype; ten times the price, and still a new driver (MAX86171 ≠ MAX86177 register map). The bare `MAX86171EVSYS#` is *obsolete and no longer manufactured*, so this reference design is the live route to that chip if the family matters later.
- **Pull the ADI NDA forward and source the MAX86177EVSYS direct** — the only path that keeps `drivers/max86177` *and* validates it. That is the right **tier-2** move, and the wrong way to unblock a tier-1 bench run, because it makes a working prototype wait on a vendor relationship.

**What the choice cost, and it is built.** The driver landed on 2026-08-17 in the order § 623 insisted on — **lift first, write second**. `peak_detect` (374 lines) and the LED AGC had lived inside the `max86177` crate with `hr.rs` calling a concrete type; they now sit in `watch_core::ppg` behind a `PpgAfe` trait, so there is still exactly one peak detector rather than two things to tune against one wrist. `drivers/max30101` is written under it and `drivers/max86177` stays as the head start on the production part.

Two defects surfaced that only appear once a second part uses the same code, and both are worth knowing at the bench: the detector's DC thresholds were 19-bit counts with nothing recording the fact (an 18-bit part would have been judged twice as strictly, with no test failing), and a FIFO overflow slips slot phase straight past the whole-frame guard. Both fixed and pinned; the story is in [`tier1_log.md`](tier1_log.md).

**Nothing on this list is gated on firmware any more.** Every row has a driver, and the `hr` task tolerates an absent sensor by design — its timeout-bounded presence probe parks cleanly rather than stalling the executor, which is why the Renode runs work with no sensor attached. So a late-arriving HR breakout delays only § 82's DoD run, not steps 3, 4, 6 or most of 7.

## Wearability (~$35 + print time)

Not optional. § 82's DoD is an **outdoor run on a real wrist**, and [`prototyping.md`](prototyping.md#tier-1--bench-prototype-5002k-36-months) lists the chassis as a tier-1 deliverable; [`quality_standards.md`](quality_standards.md) step 7 checks it. It sat under "nice-to-have" in earlier revisions of this file, which was a misfiling.

| Item | Recommended | Price |
|---|---|---|
| 3D-printed chassis | Any FDM printer, or Shapeways / JLCPCB 3D | $0–50 per print |
| Velcro / hook-and-loop strap | Generic 25 mm sew-on or one-wrap | ~$8 |

A board-holder, not a case: no sealing, no IPX claim, no industrial design — those are the tier-2/3 exclusions below.

## Bench tools (~$320–$1020 depending on tier)

| Tool | Recommended | Price | Notes |
|---|---|---|---|
| Soldering iron | Pinecil V2 ($50) **or** Hakko FX-888D ($100) | $50–$100 | Pinecil is excellent for the money; Hakko is the lab standard |
| Solder + flux + desoldering wick | Generic | ~$25 | Lead-free 60/40 0.6mm, no-clean flux pen, copper braid |
| Multimeter | Aneng AN8009 ($30) **or** Brymen BM235 ($120) | $30–$120 | Continuity beeper + diode test required; auto-range nice |
| **Nordic Power Profiler Kit II (PPK2)** | Nordic direct / Mouser / Digi-Key | ~$120 | Per-subsystem power measurement per [decisions.md § 83](../architecture/decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem). 1 nA – 1 A dynamic range; required for sub-µA sleep-current readings the multimeter can't reach. Wire between each isolated subsystem and its power input |
| USB-UART adapter | FTDI FT232RL or CP2102 | ~$10 | For viewing serial logs separately from the dev-board's onboard CDC-ACM. Also the fastest way to sanity-check the GNSS module's baud in isolation before blaming the firmware |
| Logic analyzer | Generic 8-channel FX2 clone ($15) **or** Saleae Logic 8 ($400) | $15–$400 | FX2 clones run `sigrok` / PulseView; Saleae is night-and-day better but $400. Buy the cheap one first; upgrade only if you find yourself fighting the tool |
| ESD-safe mat + wrist strap | Generic | ~$30 | Cheap insurance against frying parts |
| Helping-hands / PCB vise | Generic | ~$15 | For holding breakouts while soldering header pins |

The nRF52840 DK has an onboard J-Link debugger over USB, so a standalone Segger debugger is **not** needed for tier 1. If we later move to a custom PCB without a built-in debugger, the J-Link EDU Mini is $20 (non-commercial licence — check terms before any commercial use). The Rust path can use the much cheaper CMSIS-DAP / DAPLink adapters with [`probe-rs`](https://probe.rs/) instead.

## Optional / nice-to-have

| Item | When | Price |
|---|---|---|
| Bench oscilloscope (Rigol DS1054Z) | Once SPI / I²C timing issues appear | ~$400 |
| Bluetooth-sniffer dongle (Nordic nRF52840 Dongle) | For debugging GATT traffic on the phone side | ~$10 |
| Spare nRF52840 DK | Insurance against bricking the first one | ~$49 |

## What's *not* on this list (deliberately)

- **PCB design tools, PCB fab orders, stencil orders, pick-and-place setup** — all gated on the §71 triggers.
- **Sony CXD5610 dual-band GNSS** — NDA part; the MAX-M10S is the tier-1 stand-in.
- **Ambiq Apollo510B** — production-target MCU per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified); tier 1 uses the nRF52840 for Embassy + `nrf-softdevice` maturity and the included onboard debugger.
- **A vibration motor or buzzer.** Not an omission — a decision. Every alert on this device is display-only, and [§ 373](../architecture/decisions.md) / [§ 375](../architecture/decisions.md) turn that into stated limits on the wrist (`WATCH CANNOT WAKE YOU`; no alarm). Haptics are a tier-2 line item, and adding one here would quietly invalidate those refusals.
- **Custom LiPo cell tooling** — $8–15k one-off; way out of tier 1.
- **Case CAD / industrial design / RF chamber time** — tier-2+ line items.
- **Sapphire crystal, IPX7 sealing, drop / vibe / thermal cycling, FCC / CE certification** — tier 3.

## Order checklist

Tick as parts arrive (don't tick to "buy"; tick when received):

- [ ] Nordic nRF52840 DK
- [ ] SparkFun GPS-18037 (MAX-M10S) breakout
- [ ] Adafruit 3502 Sharp Memory LCD breakout
- [ ] Adafruit 6407 BMP581 breakout
- [ ] MAX30101 breakout (**not** MAX30102 — no green LED)
- [ ] LiPo 500 mAh + JST-PH
- [ ] LiPo charger
- [ ] BTN5 momentary pushbutton
- [ ] Breadboard + jumpers + headers
- [ ] Velcro strap
- [ ] Soldering iron + solder + flux
- [ ] Multimeter
- [ ] Nordic Power Profiler Kit II (PPK2)
- [ ] USB-UART adapter
- [ ] Logic analyzer (any tier)
- [ ] ESD mat + wrist strap
- [ ] Helping hands / vise
