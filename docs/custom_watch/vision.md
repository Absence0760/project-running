# Vision — why ultra, and what falls out of that

## Why ultra-marathon specifically

The general-purpose smartwatch market (Apple Watch, Samsung Galaxy Watch, Pixel Watch) is owned by phone OEMs whose moat is OS integration, not running. Competing there means competing on notifications, payments, voice assistants, and app stores — none of which we can win.

The road-running and triathlon segments are owned by Garmin (Forerunner 165 / 265 / 965), Polar, and COROS. The fight there is brand + features-per-dollar; the incumbents have a 20-year head start on both.

The **ultra-marathon segment** is the only one where the incumbents have a structural weakness we could exploit:

1. **Battery life is a hard requirement, not a marketing line.** A back-of-pack 100-miler can take 30+ hours. Backcountry self-supported FKTs run 2–5 days. A watch that dies at hour 26 is a safety problem, not a feature gap. This pushes the entire stack toward bare-metal C on a low-power MCU — exactly the territory Wear OS / watchOS can't touch.
2. **The competitive set is small.** Garmin Fenix / Enduro, COROS Vertix, Suunto Vertical. Three SKUs from three companies. The pricing ($600–$1,100) reflects how non-commodity the segment is.
3. **The buyer is technically literate and forum-active.** Ultra runners are the demographic most likely to read a teardown blog post and switch on the basis of a single feature (dual-band GNSS, better foliage accuracy, free maps, repairable battery). That makes word-of-mouth a real growth channel — unlike the road segment where the buying decision is driven by visibility at race expos.
4. **The software differentiation is real.** Garmin's UI is widely considered hostile (nested menus, confusing data screens, inconsistent terminology). The app we've already built — clean course-overlay, sane settings, real spectator tracking — is a credible front-end for someone else's hardware.

What we'd *not* be: a general-purpose smartwatch, a phone replacement, a fitness-tracker. The wrist device is a **tool for the run**, not a tool for the rest of the day.

## Product requirements that fall out of the ultra niche

| # | Requirement | Why | Drives |
|---|---|---|---|
| 1 | **100+ hour GPS battery life** | 100mi events take 18–36 hours; multi-day FKTs need 3x buffer for backcountry safety | Low-power MCU (Ambiq Apollo4 / Nordic nRF5340), MIP display not AMOLED, custom RTOS not Wear OS, ~600–800 mAh battery |
| 2 | **Dual-band GNSS (L1+L5) with multi-constellation** | Single-band GPS drifts 5–15m in tree canopy / canyons; dual-band cuts that to 1–3m. Ultra courses are mostly trail and runners care about distance accuracy across 100km+ | Sony CXD5610 or u-blox X20P, not the commodity MAX-M10S |
| 3 | **Always-on display readable in direct sun, no backlight** | Headlamp + AMOLED at full brightness kills battery; sunlight washes out OLED entirely | Sharp Memory LCD (MIP) — what Garmin Fenix uses. ~10–100 µA always-on draw. Trade: lower colour gamut, lower refresh rate |
| 4 | **5 physical buttons (Garmin Fenix layout), no touchscreen** | Touchscreens fail with sweat, gloves, rain, gel-coated fingers. Dropping the touch stack also drops ~$2–5 BOM, ~5–50 µA always-on idle draw, the cap-touch glass overlay, and a firmware touch driver — every layer of the touch stack is a fail point we don't need. Locked in [decisions.md § 81](../decisions.md#81-custom-watch-input-is-5-physical-buttons-in-the-garmin-fenix-layout-no-touchscreen) | Left side (3): LIGHT (top), UP, DOWN. Right side (2): START/STOP (top), BACK/LAP. Asymmetric on purpose — the left/right split is a learned visual cue runners already know from Garmin Fenix / Polar Vantage / Suunto Vertical |
| 5 | **Offline vector maps with course following** | Cell signal is unreliable in the places ultras happen. The course breadcrumb is the safety feature | 16 GB external SPI NAND flash for PMTiles archives + constrained-subset MapLibre-style vector renderer on the MCU. Decision in [§ 85](../decisions.md#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu-16-gb-external-nand-flash) (full PMTiles over the easier middle option), driven by [§ 86](../decisions.md#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) (end-state quality first) |
| 6 | **IPX7+ water resistance** | Rain, river crossings, sweat | Sealed case + gasket; charging via inductive pad (no exposed contacts) |
| 7 | **Barometric altimeter** | Trail elevation gain is a primary stat; GPS altitude alone is 20–50m noisy. Also drives storm detection | Bosch BMP390 (already standard in this class) |
| 8 | **Optical heart rate that survives rough terrain** | Wrist-mounted HR is famously unreliable during high-cadence trail descents; ultras need HR for pacing, not just bragging | Goodix GH3026 or Maxim MAX86177 (the part Garmin moved to in 2023). Still won't match a chest strap; we'd also support ANT+ chest strap pairing |
| 9 | **Solar charging panel (stretch)** | Adds 10–30% runtime in direct sun (Garmin's published Fenix 7X Solar uplift). The underlying transparent-solar-cell technology comes from several suppliers (e.g. Sunpartner / Crystalsol families); Garmin's Powerglass brand wraps their version. Availability to third parties at our volumes needs a real supplier conversation, not an assumption | Custom glass stack, +$40–80 BOM, +6 months of glass-supplier qualification |
| 10 | **Hot-swappable battery (stretch / repairable)** | Multi-day FKTs; right-to-repair as a brand position | Mechanical complexity, harder to seal — almost no consumer watches do this. Differentiator if we pull it off |

The first 8 are table stakes for the segment. Items 9 and 10 are where we'd actually differentiate.

## What we'd be competing against

| Watch | GPS battery (best-case mode) | Display | GNSS | Price | Notable gap |
|---|---|---|---|---|---|
| Garmin Fenix 7X Solar | ~89hr | 1.4" MIP | Dual-band | $900 | Hostile UI, slow OS updates |
| Garmin Enduro 3 | ~110hr | 1.4" MIP | Dual-band | $900 | Same UI; slimmer, lighter |
| COROS Vertix 2 / 2S | ~140hr / ~118hr | 1.4" MIP | Dual-band | $700 | UI is better than Garmin; map UX still weak |
| Suunto Vertical | ~85hr (Performance mode) | 1.4" MIP | Dual-band | $700 | Smallest software ecosystem of the three |
| Apple Watch Ultra 2 | ~12hr (workout, normal-power) | AMOLED | Dual-band | $800 | Battery life makes it a non-starter for 100mi |

> **Important caveat on battery numbers.** Vendor "GPS hours" figures are almost always quoted for the *best-case* mode — typically single-band GPS only, no music, no maps loaded, no HR active. Switching to multi-band / all-systems GNSS (the configuration ultra runners actually want, for foliage and canyon accuracy) typically cuts the figure by 40–60%. The Garmin Fenix 7X Solar at "89hr GPS" drops to ~36hr in the multi-band-with-music configuration most runners actually use. Verify mode-for-mode before comparing, and treat the figures above as headline marketing numbers, not as what you'd see on the wrist during a 100-miler.

Our target (best-case headline): match or beat the Garmin Enduro 3 on battery (~110hr GPS, single-band), match the COROS Vertix 2 on UI quality (the bar is low), beat all four on map UX (vector tiles, offline-by-default, course following that doesn't feel like a 2010 GPS unit). Price target $500–$600 to undercut the segment by a meaningful margin while still leaving 40–50% gross margin on a sane production run.
