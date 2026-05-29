# Parts list — tier 1 bench prototype

Single shopping list for building the tier-1 bench prototype from scratch. Total ~$1k–$2k including tools. Sourced from the cost analysis in [`prototyping.md`](prototyping.md).

Order numbers / vendor SKUs below are starting points — re-verify stock + current price + lifecycle status at the vendor before ordering. See also the procurement caveat at the top of [`bom.md`](bom.md).

## MCU + sensor breakouts (~$280)

| Part | Vendor / order number | Price | Notes |
|---|---|---|---|
| Nordic nRF52840 DK (PCA10056) | Mouser / Digi-Key / Adafruit / Nordic direct | ~$50 | Tier-1 MCU. Onboard Segger J-Link debugger over USB — no separate debugger needed. ANT+ available via the S340 multi-protocol SoftDevice (BLE + ANT+ concurrent). Production target migrates to **Ambiq Apollo510B** per [§ 90](../decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) — see [bom.md](bom.md). Chosen over the nRF5340 DK at this tier because the nRF52840 has more mature Embassy / Zephyr / `nrf-softdevice` support and stronger ANT+ tooling |
| u-blox MAX-M10S GPS breakout | SparkFun GPS-21086 ("MAX-M10S Breakout") | ~$40 | Single-band L1 only. Production target migrates to Sony CXD5610 (NDA part). Fine for verifying the firmware NMEA-parser + fix-acquisition logic |
| Sharp Memory LCD 1.3" 168×144 breakout (LS013B4DN04) | Adafruit "Sharp Memory Display Breakout" | ~$35 | The MIP display family Garmin Fenix uses. SPI interface. Static draw ~10 µA |
| Maxim MAX86177 evaluation kit | Analog Devices `MAX86177EVSYS#` (verify current order number on the AD product page) | ~$130 | Optical HR AFE. Raw signal is fine for bench bring-up; the production HR algorithm needs licensing or in-house DSP work |
| Bosch BMP390 breakout | Adafruit BMP390 "Precision Altimeter" (P/N 4816) | ~$15 | Barometric altimeter. Production target migrates to **Bosch BMP581** per [§ 90](../decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) (~85% lower current, capacitive vs piezoresistive) — BMP390 breakouts are cheap and well-supported, fine for tier-1 bench bring-up |
| LiPo battery 500 mAh + JST-PH 2-pin | Adafruit 1578 | ~$10 | For runs off the dev-board |
| Breadboard + jumper wires + headers | Generic (Adafruit / SparkFun / Amazon) | ~$20 | Half-size breadboard, ~30× male-male + male-female jumpers, a strip of 0.1" male headers |

## Bench tools (~$320–$1020 depending on tier)

| Tool | Recommended | Price | Notes |
|---|---|---|---|
| Soldering iron | Pinecil V2 ($50) **or** Hakko FX-888D ($100) | $50–$100 | Pinecil is excellent for the money; Hakko is the lab standard |
| Solder + flux + desoldering wick | Generic | ~$25 | Lead-free 60/40 0.6mm, no-clean flux pen, copper braid |
| Multimeter | Aneng AN8009 ($30) **or** Brymen BM235 ($120) | $30–$120 | Continuity beeper + diode test required; auto-range nice |
| **Nordic Power Profiler Kit II (PPK2)** | Nordic direct / Mouser / Digi-Key | ~$120 | Per-subsystem power measurement per [decisions.md § 83](../decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem). 1 nA – 1 A dynamic range; required for sub-µA sleep-current readings the multimeter can't reach. Wire between each isolated subsystem and its power input |
| USB-UART adapter | FTDI FT232RL or CP2102 | ~$10 | For viewing serial logs separately from the dev-board's onboard CDC-ACM |
| Logic analyzer | Generic 8-channel FX2 clone ($15) **or** Saleae Logic 8 ($400) | $15–$400 | FX2 clones run `sigrok` / PulseView; Saleae is night-and-day better but $400. Buy the cheap one first; upgrade only if you find yourself fighting the tool |
| ESD-safe mat + wrist strap | Generic | ~$30 | Cheap insurance against frying parts |
| Helping-hands / PCB vise | Generic | ~$15 | For holding breakouts while soldering header pins |

The nRF52840 DK has an onboard J-Link debugger over USB, so a standalone Segger debugger is **not** needed for tier 1. If we later move to a custom PCB without a built-in debugger, the J-Link EDU Mini is $20 (non-commercial licence — check terms before any commercial use). The Rust path can use the much cheaper CMSIS-DAP / DAPLink adapters with [`probe-rs`](https://probe.rs/) instead.

## Optional / nice-to-have

| Item | When | Price |
|---|---|---|
| Bench oscilloscope (Rigol DS1054Z) | Once SPI / I²C timing issues appear | ~$400 |
| 3D printer access (or Shapeways / JLCPCB 3D) | For Velcro-strap enclosure prototypes | $0–$50 per print |
| Bluetooth-sniffer dongle (Nordic nRF52840 Dongle) | For debugging GATT traffic on the phone side | ~$10 |
| Spare nRF52840 DK | Insurance against bricking the first one | ~$50 |

## What's *not* on this list (deliberately)

- **PCB design tools, PCB fab orders, stencil orders, pick-and-place setup** — all gated on the §71 triggers.
- **Sony CXD5610 dual-band GNSS** — NDA part; the MAX-M10S is the tier-1 stand-in.
- **Ambiq Apollo510B** — production-target MCU per [§ 90](../decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified); tier 1 uses the nRF52840 for Embassy + `nrf-softdevice` maturity and the included onboard debugger.
- **Custom LiPo cell tooling** — $8–15k one-off; way out of tier 1.
- **Case CAD / industrial design / RF chamber time** — tier-2+ line items.
- **Sapphire crystal, IPX7 sealing, drop / vibe / thermal cycling, FCC / CE certification** — tier 3.

## Order checklist

Tick as parts arrive (don't tick to "buy"; tick when received):

- [ ] Nordic nRF52840 DK
- [ ] u-blox MAX-M10S breakout
- [ ] Sharp Memory LCD breakout
- [ ] MAX86177 eval kit
- [ ] BMP390 breakout
- [ ] LiPo 500 mAh + JST-PH
- [ ] Breadboard + jumpers + headers
- [ ] Soldering iron + solder + flux
- [ ] Multimeter
- [ ] Nordic Power Profiler Kit II (PPK2)
- [ ] USB-UART adapter
- [ ] Logic analyzer (any tier)
- [ ] ESD mat + wrist strap
- [ ] Helping hands / vise
