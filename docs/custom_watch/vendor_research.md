# Vendor research — § 88 Layer 1 findings

This doc fulfils the **Layer 1 (free public research, zero commercial commitment)** items of [decisions.md § 88](../architecture/decisions.md#88-vendor-engagement-is-tiered-across-project-maturity), as tracked in [`roadmap.md` § Vendor engagement](roadmap.md#vendor-engagement-tiered-per--88). Research date: **2026-07-09**; every source below was accessed on that date. All findings are from free public sources — no vendor contact, no NDA, no membership.

Headline: all three items produced a decision-relevant answer, and two of them **contradict assumptions recorded in § 88 / [`bom.md`](bom.md)** — the ANT+ Alliance membership that Layer 3 budgets for no longer exists (Garmin wound the program down in mid-2025), and the MAX86177 "public datasheet" § 88 assumed is actually NDA-gated (only sibling parts have full public datasheets).

## 1. ANT+ Alliance — competitor adoption, program state, trajectory

### What § 88 wanted to know

Would Garmin (which owns the ANT+ program via Garmin Canada / the former Dynastream) refuse a competing watch maker? § 88 Layer 3 budgeted "$2–5k/year + Garmin review" for an eventual Adopter membership at tier-2 greenlight.

### Findings

**Competitor adoption is real and documented.** The public directory at thisisant.com lists directly competing watch makers as ANT+ certified:

- **COROS APEX** (a watch competing head-on with Garmin's Fenix line) is listed as ANT+ **Certified**, with Bike Cadence / Bike Power / Bike Speed / Speed & Cadence / Heart Rate / Running Dynamics profiles ([thisisant.com/directory/apex](https://www.thisisant.com/directory/apex)). The COROS Trainer is also certified.
- **Wahoo** (Wahoo Fitness App) is ANT+ certified ([thisisant.com/directory/wahoo-fitness-app](https://www.thisisant.com/directory/wahoo-fitness-app)).
- **Polar** sensors (OH1, Verity Sense) are listed and broadcast ANT+ ([thisisant.com/directory/polar-oh1](https://www.thisisant.com/directory/polar-oh1), [/directory/polar-verity-sense](https://www.thisisant.com/directory/polar-verity-sense)) — though Polar *watches* pair sensors over BLE only ([support.polar.com](https://support.polar.com/us-en/what-is-ant-in-polar-products)).
- **Suunto**: modern Suunto watches (9 onward) are BLE-only for sensor pairing; Suunto dropped ANT+ ([forum.suunto.com](https://forum.suunto.com/topic/6455/s9-ant-to-ble-bridges)). Their presence in the directory is legacy-era.
- **Apple**: the Apple Watch has never supported ANT+ in any generation ([discussions.apple.com](https://discussions.apple.com/thread/251563396)). Absence by Apple's choice, not Garmin's refusal.

So the historical answer to "would Garmin refuse?" is **no** — the program certified COROS, the most direct competitor imaginable.

**The program § 88 budgeted for no longer exists.** Garmin announced in January 2025 that it is winding down the ANT+ ecosystem ([DC Rainmaker, 2025-01](https://www.dcrainmaker.com/2025/01/the-begining-of-the-end-for-ant-wireless.html)):

- Membership programs and fees: discontinued.
- ANT+ certification: submissions closed 2025-03-31, final certifications issued by 2025-06-30. **New products can no longer be ANT+ certified, by anyone.**
- Engineering support: ended 2025-06-30.
- New device profiles: none will be created; new metrics arrive BLE-only.
- All ANT+ documentation: made freely available online (the previous tier-gated access is gone). The "Become an Adopter" click-through at [thisisant.com/my-ant/join-adopter](https://www.thisisant.com/my-ant/join-adopter) still works as of the access date, is explicitly **free** ("There is no fee to become an ANT+ Adopter"), and grants device profiles, reference code, and simulators.
- ANT+ stays available on dual ANT+/BLE silicon (Nordic parts included) for legacy interop.

The stated driver is the EU Radio Equipment Directive delegated regulation 2022/30 (mandatory 2025-08-01): adding the required authentication/encryption to ANT+ profiles would break backward compatibility with the installed base, and there was no industry appetite to fund a rebuild ([garminrumors.com](https://garminrumors.com/why-ant-is-fading-the-shift-to-new-wireless-standards/), [the5krunner](https://the5krunner.com/2025/01/04/ant-is-doomed-to-die-a-slow-death/)).

**Trajectory.** The market was already drifting BLE-only before the wind-down: Suunto and Polar watches pair sensors over BLE only, Apple never supported ANT+, and every current sensor of note (HR straps, foot pods, power meters) broadcasts BLE alongside or instead of ANT+. The wind-down converts the drift into an end state: ANT+ is now a frozen legacy protocol with a large installed base of straps and bike sensors, shrinking at replacement rate.

### What this means for us

- **The "would Garmin refuse?" uncertainty is closed twice over**: historically they didn't refuse (COROS was certified), and the question is now moot because certification no longer exists for anyone.
- **§ 88 Layer 3 as written is obsolete.** There is no membership to buy and no Garmin review to pass. The $2–5k/year line item disappears. Layer 3 should be re-scoped when a § 71 trigger fires: the remaining questions are trademark/logo use (the ANT+ *brand* presumably still can't be claimed without a certification that can no longer be granted) and long-term silicon availability of dual-protocol parts.
- **The T2 "ANT+ sensor pairing" parity item survives, demoted.** It is now *technically cheaper* (documentation and reference code are free; the nRF52840's S340 SoftDevice already speaks ANT) but *strategically weaker* (frozen protocol, no certification badge available, market moving BLE-only). Recommended posture: **BLE sensor pairing is the primary rail** (already T1/T2 in the parity backlog); ANT+ reception ships as a best-effort legacy-compatibility feature for the installed base of chest straps our target ultra runners own — no logo claims, no dependency on any Garmin relationship. If firmware effort gets tight at tier 2, ANT+ is the item to cut, not BLE.

Sources (all accessed 2026-07-09): [thisisant.com/directory/apex](https://www.thisisant.com/directory/apex) · [thisisant.com/my-ant/join-adopter](https://www.thisisant.com/my-ant/join-adopter) · [dcrainmaker.com — The Beginning of the End for ANT+ Wireless](https://www.dcrainmaker.com/2025/01/the-begining-of-the-end-for-ant-wireless.html) · [the5krunner.com — ANT+ Is Doomed to Die a Slow Death](https://the5krunner.com/2025/01/04/ant-is-doomed-to-die-a-slow-death/) · [garminrumors.com — Why ANT+ Is Fading](https://garminrumors.com/why-ant-is-fading-the-shift-to-new-wireless-standards/) · [support.polar.com — What is ANT+ in Polar products](https://support.polar.com/us-en/what-is-ant-in-polar-products) · [discussions.apple.com — ANT+ Compatibility](https://discussions.apple.com/thread/251563396)

## 2. Sony CXD5610 GNSS — public family brief

### What § 88 wanted to know

Power consumption, mode breakdowns, package options — enough for tier-2 BOM planning without the NDA datasheet.

### Findings

Sony's public product brief for the **CXD5610GF** ([sony-semicon.com PDF](https://www.sony-semicon.com/files/62/pdf/p-23_CXD5610_1015.pdf)) and the GNSS family page ([sony-semicon.com/en/products/lsi-ic/gps.html](https://www.sony-semicon.com/en/products/lsi-ic/gps.html)) give:

| Spec | Public figure |
|---|---|
| Bands | Dual-band L1 + L5 |
| Constellations | GPS, GLONASS, Galileo, BeiDou, QZSS; plus SBAS and NavIC |
| Power, L1+L5 simultaneous | **9 mW** |
| Power, L1 only | **6 mW** |
| Power, L5 only | **8 mW** |
| Sensitivity | −163 dBm hot start, −167 dBm tracking |
| TTFF | Cold 24 s, hot 1 s (hot-start position calc < 1 s at −130 dBm) |
| Memory | Embedded 16 Mbit NVM — **no external flash required** |
| Low power state | "Ultra-low leak current in the Deep Sleep state" (no figure given) |
| Host IO | 1.8 V / 1.2 V |
| Package (GF) | XFBGA 54-pin, 3.66 × 3.15 mm (family page says 3.2 × 3.7 × 0.5 mm; same part, rounding differs) |
| Temperature | −40 °C to +105 °C |
| Other | A-GNSS supported, UDR (untethered dead reckoning) supported |

Family variants: **CXD5610GF** (22 nm FD-SOI, the wearable pick) and **CXD5610GG** (larger 8.0 × 7.0 × 1.4 mm BGA, 8 mW L1 / 11 mW L1+L5, AEC-Q100 automotive). Adjacent parts: CXD5605AGF (single-band L1, 7 mW, the previous wearable generation) and the newer CXD5642GF (single-band L1, 2.9 × 2.9 mm). Off-the-shelf modules built on Sony GNSS silicon exist — Telit SE868SY-D, REYAX RYS8839 — and the Sony Spresense board has a dual-band GNSS add-on, which is a viable no-NDA evaluation path.

**Not in the public material:** acquisition-mode power, duty-cycled/intermittent-fix power profiles, and per-constellation-mix power tables. Those stay behind the NDA datasheet (§ 88 Layer 2).

**Corrections to `bom.md`.** The BOM row says "~9 mA tracking, ~25 mA acquisition (vendor datasheet)". The public brief specifies **9 mW** (milliwatts, L1+L5 simultaneous reception) — the mA figures don't match any public Sony number and the acquisition figure is not publicly documented at all. The BOM row should be restated in mW against this brief when next touched.

**Which shipping watches use it: could not confirm.** No public teardown ties the CXD5610 to a named shipping watch. The evidence trail actually points away from Sony for current flagships:

- COROS's multiband watches (Vertix 2, Vertix 2S, APEX 2 Pro, PACE 3) use the **Airoha AG3335M** — COROS confirmed this, and COROS replaced its earlier Sony (single-band CXD5603/5605-era) parts in the process ([logiqx gps-guides — COROS Vertix 2](https://logiqx.github.io/gps-guides/devices/coros/vertix-2/), [logiqx gps-details — Airoha devices](https://logiqx.github.io/gps-details/chipsets/airoha/devices.html)).
- A 2025 Garmin Fenix 8 teardown found a **Synaptics SYN4778**, a supplier change ([the5krunner — Fenix 8 teardown](https://the5krunner.com/2025/04/22/garmin-fenix-8-teardown-details-including-a-new-gnss-chipset/)); earlier Garmin models used Sony CXD5603GF/CXD5605GF (single-band) and Airoha for multiband ([logiqx gps-details — Garmin chipsets](https://logiqx.github.io/gps-details/devices/garmin/chipsets/)).
- Confirmed Sony wearable design wins in public teardowns are the older single-band parts (e.g. CXD5605 in the Huawei Watch GT 2, per a TechInsights floorplan analysis).

So "Sony GNSS silicon is widely reported in modern Garmin teardowns" (the `bom.md` framing) was true of the 2019–2022 single-band generation; **no public evidence places the dual-band CXD5610 in any current Garmin/COROS flagship**. This stays an open question for the Layer-2 Sony conversation.

### What this means for us

The public brief is sufficient for tier-2 BOM planning on the tracking-power axis — 9 mW dual-band is excellent and beats the Airoha AG3335M's public positioning. But the missing acquisition/duty-cycle numbers are exactly the ones an ultra watch's battery budget hinges on (fix-interval modes are the T2 "selectable GNSS / battery modes" parity item), so the Layer-2 NDA request stays justified. The absence of verifiable CXD5610 wearable design wins, while COROS/Garmin demonstrably ship Airoha and Synaptics, strengthens the case for keeping the **Airoha AG3335M alternate** (already qualified in `bom.md` per § 90) as a genuinely co-equal candidate — it has proven wearable design wins and a more accessible sourcing path (Quectel LC29H module) if Sony NDA engagement stalls.

Sources (all accessed 2026-07-09): [Sony CXD5610GF product brief (PDF)](https://www.sony-semicon.com/files/62/pdf/p-23_CXD5610_1015.pdf) · [Sony GNSS family page](https://www.sony-semicon.com/en/products/lsi-ic/gps.html) · [logiqx gps-guides — COROS Vertix 2](https://logiqx.github.io/gps-guides/devices/coros/vertix-2/) · [logiqx gps-details — Garmin chipset identification](https://logiqx.github.io/gps-details/devices/garmin/chipsets/) · [the5krunner — Fenix 8 teardown](https://the5krunner.com/2025/04/22/garmin-fenix-8-teardown-details-including-a-new-gnss-chipset/) · [Neowin — Sony L1/L5 receiver LSIs at 9 mW](https://www.neowin.net/news/sonys-new-receiver-lsis-for-wearables-support-both-l1-and-l5-bands-while-consuming-only-9-mw/)

## 3. ADI/Maxim MAX86177 — datasheet availability and public specs

### What § 88 wanted to know

Confirm public availability of the datasheet; extract the register-interface style, FIFO depth, channel count, LED drivers, supply rails, low-power states and currents, and package for the tier-1 driver work.

### Findings

**The § 88 premise "already public" is wrong.** There is no freely downloadable MAX86177 datasheet. ADI's own MAX86177EVSYS page states: *"Complete documentation is available upon completion of a Non-Disclosure Agreement (NDA)"* ([analog.com — MAX86177EVSYS](https://www.analog.com/en/resources/evaluation-hardware-and-software/evaluation-boards-kits/max86177evsys.html)). Repeated attempts to fetch a `MAX86177.pdf` from analog.com and distributor mirrors returned nothing; sibling premium parts (MAX86174A/B) ship only "ABRIDGED DATA SHEET" documents publicly. The full register map — the thing the tier-1 driver actually needs — is NDA-gated.

**What IS public** (product page + EV-kit material, consistent across ADI and distributor listings):

| Spec | Public figure |
|---|---|
| Architecture | Quad-channel ultra-low-power optical data-acquisition AFE (PPG) |
| Receive side | **4** low-noise charge-integrating front-ends, each with an independent **20-bit ADC** and ambient-light-cancellation circuits, operating simultaneously |
| Transmit side | **2** high-current 8-bit programmable LED drivers, supporting up to **6 LEDs** |
| FIFO | **512-word** built-in FIFO |
| Interface | **Both I²C- and SPI-compatible** |
| Supply rails | **1.8 V** main supply; **3.1–5.5 V** LED-driver supply |
| Package | 28-bump WLP (7 × 4), **2.83 × 1.89 mm**, −40 °C to +85 °C |
| EV system | MAX86177EVSYS: wrist-band form factor, 6 LEDs (2 × OSRAM SFH7016 red/green/IR 3-in-1) + 8 photodiodes (OSRAM SFH2704) + accelerometer, BLE logging |

**Not publicly confirmed:** shutdown/standby current for this specific part (no figure anywhere public), the register map, sample-rate tables, and FIFO record format. The closest family reference with a **full public datasheet including the register map** is the **MAX86171** ([analog.com MAX86171.pdf](https://www.analog.com/media/en/technical-documentation/data-sheets/MAX86171.pdf), also mirrored by Mouser): quad-channel, 3 LED drivers, 256-word FIFO, < 1 µA shutdown, same 1.8 V + 3.1–5.5 V rail structure and same register-driven autonomous-FIFO design idiom. The `bom.md` "sub-µA standby" claim is plausible by family extrapolation (MAX86171 < 1 µA; MAX86178 quotes 0.5 µA) but is **not** confirmed for the MAX86177 itself.

**Corrections to `bom.md`.** The BOM row describes the MAX86177 as "4-LED, 2-PD". Public material says the true shape is the other way around: **2 LED drivers** (up to 6 LEDs, multiplexed) on the transmit side and **4 photodiode readout channels** on the receive side (the EV kit hangs 8 discrete photodiodes off them). Also "sub-µA standby" should carry an "unverified for this part" caveat until the NDA datasheet is in hand.

### What this means for us

The tier-1 "Step 5 — Optical HR bring-up. MAX86177 over I²C" plan has a dependency that Layer-1 research was expected to clear but didn't: **no public register map exists**, so a register-level Rust driver can't be written from public sources. Two viable paths, in preference order per the § 92 optimise-for-end-state principle:

1. **Pull the ADI NDA forward for this one part.** § 88 Layer 2 already schedules ADI contact (they're "friendlier to small inquiries" per § 88); an NDA/documentation request is lighter than the HR-algorithm-licensing conversation and could be made at the same time or slightly earlier. The EV system (MAX86177EVSYS, orderable from DigiKey/Mouser) plus NDA docs is the straight route to the launch-pick part.
2. **Bench-prototype on the MAX86171 instead.** Full public datasheet with register map, same family idioms (charge-integrating channels, autonomous FIFO, dual I²C/SPI), same rails — a driver written against it ports to the MAX86177 with register-map deltas once the NDA lands. This keeps tier-1 unblocked with zero vendor engagement, at the cost of a later porting pass.

Either way, `roadmap.md` step 5 and the `bom.md` HR row should note the NDA gate when next edited (per the task scope, this doc records the finding; the roadmap/BOM edits belong to the parent session).

Sources (all accessed 2026-07-09): [analog.com — MAX86177 product page](https://www.analog.com/en/products/max86177.html) · [analog.com — MAX86177EVSYS (NDA statement)](https://www.analog.com/en/resources/evaluation-hardware-and-software/evaluation-boards-kits/max86177evsys.html) · [Farnell — MAX86177EVSYS datasheet PDF](https://www.farnell.com/datasheets/4127434.pdf) · [analog.com — MAX86171 full public datasheet (PDF)](https://www.analog.com/media/en/technical-documentation/data-sheets/MAX86171.pdf) · [DigiKey — MAX86177EVSYS listing](https://www.digikey.com/en/products/detail/analog-devices-inc-maxim-integrated/MAX86177EVSYS/17885184) · [Maxim (archived staging) — MAX86177 quad-channel AFE](https://www.stg-maximintegrated.com/en/products/sensors/MAX86177.html)

## Follow-ups this research creates (for the parent session / next planning pass)

- **§ 88 Layer 3 re-scope**: the ANT+ Alliance membership + fee + Garmin review no longer exist; the residual questions are trademark use and dual-protocol silicon longevity.
- **`bom.md` corrections**: CXD5610 power row (mW not mA; acquisition figure unsourced), MAX86177 row (2 LED drivers / up to 6 LEDs / 4 readout channels, not "4-LED, 2-PD"; standby current unverified).
- **Tier-1 step 5 decision**: MAX86171 bench substitute vs early ADI NDA — decide before ordering the HR sensor part of the parts list.
- **Open question**: which shipping watch, if any, uses the CXD5610 — take into the Layer-2 Sony FAE conversation; meanwhile treat Airoha AG3335M as a co-equal candidate, not a fallback.
