# Parts list — tier 1 bench prototype

Single shopping list for building the tier-1 bench prototype from scratch. Total ~$1k–$2k including tools. Sourced from the cost analysis in [`prototyping.md`](prototyping.md).

Order numbers / vendor SKUs below are starting points — re-verify stock + current price + lifecycle status at the vendor before ordering. See also the procurement caveat at the top of [`bom.md`](bom.md). Prices last checked **2026-08-17**; the audit that set them is recorded in [`tier1_log.md`](tier1_log.md).

**Every row here is checked against the firmware that will drive it**, not against the BOM's production picks — the two diverge on purpose (§ 90 names production silicon; tier 1 uses what has a driver and a debugger). Where a part needs configuring before it will talk to this firmware at all, that is stated in the row and repeated in [`quality_standards.md`](quality_standards.md)'s step-0 checklist. Do not substitute a "close enough" part: the drivers gate on chip IDs and fixed framebuffer dimensions, and a mismatch presents at the bench as a dead subsystem rather than as an error message.

## MCU + sensor breakouts (~$300)

| Part | Vendor / order number | Price | Notes |
|---|---|---|---|
| Nordic nRF52840 DK (PCA10056) | Mouser / Digi-Key / Adafruit / Nordic direct | ~$49 | Tier-1 MCU. Onboard Segger J-Link debugger over USB — no separate debugger needed. Has a Li-Po connector (J6/P27) and an SW9 power-source switch, so the cell below needs no adapter; the Li-Po position feeds the SoC's high-voltage regulator, which is the path the battery-gauge bench item needs. ANT+ available via the S340 multi-protocol SoftDevice. Production target migrates to **Ambiq Apollo510B** per [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) — see [bom.md](bom.md). Chosen over the nRF5340 DK at this tier for Embassy / `nrf-softdevice` maturity |
| u-blox MAX-M10S GNSS breakout | **SparkFun GPS-18037** ("GNSS Receiver Breakout — MAX-M10S (Qwiic)") — **buy it from Digi-Key** (270 in stock on 2026-08-17); SparkFun's own shop had 4, which is where this row's earlier "order early" note came from | ~$46 | Single-band L1 only. **Wire the UART pins, not the Qwiic connector** — the firmware reads NMEA on UARTE0 and sends UBX-RXM-PMREQ on its TX; the I²C path is unimplemented. Carries an MS621FE backup cell (BBR holds a fix + config ~2 weeks unpowered), which is why the firmware runs at the module's factory baud rather than a configured one ([§ 622](../architecture/decisions.md)). Production target migrates to Sony CXD5610 (NDA part) |
| Sharp Memory LCD 1.3" 168×144 breakout (LS013B7DH05) | Adafruit 3502 ("SHARP Memory Display Breakout — 1.3" 168x144 Monochrome") | $24.95 | The MIP display family Garmin Fenix uses. SPI, write-only, 3 KB framebuffer the MCU must hold. Static draw ~10 µA. **Resolution is load-bearing:** `drivers/sharp_mip` hard-codes a 168×144 framebuffer (`framebuffer.rs` `WIDTH`/`HEIGHT`), so a different panel silently corrupts every line-update address. Do **not** order LS013B4DN04 — that is the 96×96 panel (Adafruit 1393), obsolete/EOL. Ships with a header strip to solder |
| Bosch **BMP581** breakout | Adafruit **6407** ("BMP581 I2C or SPI Temperature and Pressure Sensor [STEMMA QT]") | $9.95 | Barometric altimeter. **Not the BMP390** this list used to name: `drivers/bmp581` gates on `CHIP_ID == 0x50` at register `0x01`, and a BMP390 answers `0x60` at `0x00` with an unrelated register map, so it fails the probe and parks the baro task — taking elevation, vert, the storm page and the GAP grade with it. Matches [§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified)'s production pick, so tier 1 and tier 2 now share a driver |
| **MAX30101** optical-HR breakout | SparkFun `SEN-16474` — **backorder at SparkFun on 2026-08-17, and the longest-lead line on this list; order it first.** Pimoroni `PIM438` is the alternate ($19.10 at Digi-Key, 0 stock, no backorders) but see note 4 before choosing it | ~$19–34 | Optical HR, decided at [§ 623](../architecture/decisions.md). **MAX30101, not MAX30102** — the 30102 is red + IR only (a fingertip SpO2 part) and the **green** LED the 30101 adds is the one every wrist sensor reads a moving capillary bed with. MAX30105 is an acceptable sibling and the driver takes one as-is. I²C `0x57`, 400 kHz, 18-bit ADC; the SparkFun board regulates its own 1.8 V rail and **boosts the LED supply to ~5 V**, which the green emitter needs (note 4). Register map is **public**, so the silicon is the same whoever assembles the board — the *board* is not |
| LiPo battery 500 mAh + JST-PH 2-pin | Adafruit 1578 | $7.95 | For runs off the dev-board, into the DK's Li-Po connector. Confirm the DK's J6/P27 pitch against the cell's JST-PH before assuming it seats |
| LiPo charger | Adafruit 1304 ("Micro Lipo — USB LiIon/LiPoly charger v2") | $5.95 | **The DK supplies from a Li-Po but does not charge one.** Without this the 500 mAh cell is single-use and the "percent falls monotonically across a discharge" bench item can only be run once. Ships with its own JST cable |
| Momentary tactile pushbutton (BTN5) | Generic 6mm through-hole, any breadboard assortment | ~$1 | The §350 grammar uses five buttons and the DK has four; BTN5 (manual lap / waypoint hold) is an external momentary from **P0.02 to GND** on the header — the firmware's internal pull-up means no resistor. Unwired, the lap key is simply dead (idle-high), so the rest of the grammar works without it |
| Breadboard + jumper wires + headers | Generic (Adafruit / SparkFun / Amazon) | ~$20 | Half-size breadboard, ~30× male-male + male-female jumpers, a strip of 0.1" male headers |

### Do these parts actually work together? — checked 2026-08-17

Every row above was chosen against the firmware. This section is the *other* question: whether the set is electrically coherent as one bench rig. Checked against vendor schematics where they exist, and the answers are in this table so a future session does not re-derive them.

| Interface | Verdict | On what evidence |
|---|---|---|
| **Supply rail** | Works at the DK's **3.0 V** — but see note 0, the battery case is the one that bites | Sharp 3502 takes 3-5 V (own 3 V regulator + level shifting); BMP581 6407 takes 3-5 V (regulator to 3 V, all pins level-shifted); MAX-M10S takes the rail **direct, no regulator**, and its 2.7-3.6 V window covers 3.0 V; SEN-16474 makes its own 1.8 V and boosts its own LED rail |
| **Logic levels** | Coherent at 3.0 V in every direction | The three breakouts with level shifters are 3-5 V safe; the GPS ties `V_IO` to the same rail it is powered from, so its UART swings at exactly what we feed it |
| **I²C addressing** | No collision is even possible | HR (`0x57`) and baro (`0x46`) sit on **separate** TWI instances — `TWISPI0` on P0.26/27 and `TWISPI1` on P1.10/11 — deliberately, so HR traffic never contends with the barometer |
| **Pin conflicts** | None | Nothing in the map below touches the DK's QSPI flash (P0.17-P0.22), NFC (P0.09/P0.10), LF crystal (P0.00/P0.01) or the interface MCU's UART (P0.05-P0.08) |
| **MCU resources** | Comfortable | The panel's 3 KB framebuffer against 256 KB of RAM; SPI3, UARTE0/1, TWISPI0/1, SAADC, PWM0, TIMER1 and PPI 0/1 each claimed once (the last three sit outside the S140 SoftDevice's reservations) |
| **Battery connector** | **Unconfirmed — the one open item.** Nordic documents Li-Po connectors J6/P27 but no public source states whether they are populated or at what pitch | Order a JST-PH 2-pin pigtail (~$2) as insurance, and check the board before cutting anything |
| **Run time** | **~20-25 h, derived not measured** | The MAX-M10S datasheet's own figures: 7.0 mA typical at VCC plus 2.2 mA at V_IO in acquisition, and **3.0 V is its typical operating point** (range 2.7-3.6 V), so ~10-13 mA depending on constellation config — far less than a GNSS receiver's reputation suggests. Add ~6 mA MCU, ~2 mA board overhead and under 1 mA for display, baro and duty-cycled HR: roughly 20 mA against 500 mAh. Comfortable for § 82's one outdoor run; nowhere near the multi-day story, which is the point of tier 2. The PPK2 is what turns this into a number |

**Wiring map** — from `boards/nrf52840_dk/src/lib.rs`, which is the authority; this table is a copy and the crate wins if they ever disagree.

| Signal | nRF pin | Peripheral |
|---|---|---|
| GNSS module TX → nRF RX | **P1.01** | UARTE0, 38400 8N1 |
| nRF TX → GNSS module RX | **P1.02** | UARTE0 (carries UBX power-down frames) |
| Display SCK / MOSI / CS | **P1.13 / P1.14 / P1.12** | SPI3, 2 MHz, mode 0, **LSB-first** |
| Display EXTCOMIN (`EMD`) / EXTMODE (`EIN`) | **P1.06 / P1.07** | PWM0 drives VCOM; EXTMODE is held high |
| HR SDA / SCL | **P0.26 / P0.27** | TWISPI0, `0x57` |
| Baro SDA / SCL | **P1.10 / P1.11** | TWISPI1, `0x46` after the SDO/jumper change |
| BTN5 (lap / waypoint) | **P0.02** → GND | Internal pull-up; no resistor |
| BTN1-4 | P0.11 / P0.12 / P0.24 / P0.25 | The DK's own buttons; nothing to wire |

The display's `DISP` pin needs no MCU connection, and the phone-link UART (P1.03/P1.04) is the wired dev bridge — the real phone path is BLE, so leave it unwired unless you are driving the sim harness.

### Sourcing the HR breakout — the one line that needs care at checkout

A correction to an earlier reading of this. "The register map is public, so the vendor does not matter" is true of the *silicon* and misleading as *shopping advice*, because the commodity market for these modules is dominated by the **MAX30102** — the red/IR part with no green emitter. A cheap board listed as a "MAX3010x heart rate sensor" is far more likely to be the wrong one than the right one, and the two are visually near-identical.

**The driver refuses a MAX30102, but not by its part number — that check was never able to.** Every part in the MAX3010x family reports `0x15` in `PART_ID`, so an id read cannot tell them apart, and this file claimed otherwise until [§ 624](../architecture/decisions.md) corrected it. What `drivers/max30101` does instead is check the green channel by *capability*: `init` writes `LED3_PA` and reads it back, and a part with no third LED cannot hold it, so a mis-shipped MAX30102 surfaces as `hr: AFE init failed NoGreenChannel(..)` before anything streams. A second, optical check (`watch_core::ppg::EmitterCheck`) covers the case where a reserved register echoes the write anyway — full LED drive with a lit photodiode and no reflected signal earns a named `error!` line rather than a mystery. Both are worth having and neither refunds the shipping time. So:

- **Buy a board whose listing names the MAX30101 explicitly**, and prefer one with a schematic or a hookup guide behind it — SparkFun `SEN-16474` and Pimoroni `PIM438` both qualify, and both are carried by second-tier distributors (Opencircuit, Melopero, Botland, Mouser, Farnell) even when their own shops and Digi-Key show zero.
- **Buy from a distributor, not a marketplace listing.** At Digi-Key, Mouser, Farnell/CPC or Distrelec the part number is what you are contractually sold; on a marketplace it is what the listing says. The saving is a few pounds; the cost of guessing is a reorder and a fortnight.
- A **MAX30105** is a genuine substitute — same green emitter, near-identical map — and the driver **accepts one as-is**: it reports the same family id and holds `LED3_PA`, so both checks pass. (This file previously said the driver would refuse it until its id was added. It will not, and that is the right outcome.)

### Before you wire it — the five things that cost a bench day

Each of these is a mismatch between a part's out-of-the-box state and what the firmware expects. All five are one-time, none is a defect, and all five present as *silence* rather than as an error.

0. **Running off the battery drops the SoC's logic level to 1.8 V until you say otherwise, and that is the configuration the DoD run needs.** The nRF52840 fed on **VDD** runs in normal mode and its GPIO high is the rail you gave it. Fed on **VDDH** it runs in high-voltage mode, where VDD — and therefore every GPIO's logic high — comes from an internal regulator set by `UICR.REGOUT0`, which on an erased UICR **defaults to 1.8 V**. SW9's Li-Po position is exactly that path, so the untethered build is the one that comes up at 1.8 V against breakouts that are all 3-5 V logic parts. This is not a marginal-levels problem in one direction only: the GPS driving its 3 V UART into a 1.8 V input is **over-voltage on the pin**. Program `REGOUT0` to **3.0 V** once, before wiring anything — 3.0 V rather than 3.3 V because a nearly-flat 1S cell cannot sustain 3.3 V through the regulator's dropout, and because it matches what the board supplies on USB, so behaviour does not change with the power source. The firmware reports the state at boot (`supply: ...`, `app/src/supply.rs`) and deliberately does **not** write it: the write needs a reset to take effect, and a write that does not stick is a reset loop.

1. **The BMP581 answers on the wrong address by default.** `drivers/bmp581` uses **0x46**; the Adafruit 6407 ships at **0x47**. Tie its `SDO` pin to GND (or solder the `addr` jumper on the back closed) before expecting a probe to succeed.
2. **The display's silkscreen does not use the datasheet's pin names.** `EIN` is EXTMODE, `EMD` is EXTCOMIN — the two the firmware drives for hardware VCOM. `DISP` needs no MCU pin (the panel runs from CLK/DI/CS alone), which is why the board crate has no pin for it. The breakout pulls EXTMODE low for software VCOM; the firmware drives it high, and a weak pull-down does not fight a push-pull GPIO — but confirm on the schematic that it is a resistor and not a strap.
3. **The GNSS module talks at 38400.** That is the M10 factory default and, since [§ 622](../architecture/decisions.md), what the firmware is configured for. If someone has previously set the module to another rate in u-center, reset it to defaults rather than changing the firmware — a BBR-held setting expires with the backup cell.
4. **Nothing on the HR line, as ordered.** The MAX30101 breakout regulates its own 1.8 V rail and steps up its LED supply on-board, so it takes the DK's 3.0 V rail directly. **Verified on SparkFun's schematic, and it is the reason to prefer that board:** `SEN-16474` carries an SP6214 1.8 V LDO for the AFE *and* a PAM2401 boost with a 750 k/100 k feedback divider — about **5.1 V** — for `VDD_LED`. That boost is not a nicety. The MAX30101's **green** emitter is specified for a `VLED+` of **4.5-5.5 V** (red and IR are happy from 3.1 V), so a 3.3 V board with no boost under-drives the one wavelength this whole part was chosen for, and the symptom is a weak or absent pulse that looks exactly like bad skin contact. Pimoroni's `PIM438` advertises only "3.3 V or 5 V compatible" and publishes no schematic — if you buy it instead, check for a boost before blaming the wrist.

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
