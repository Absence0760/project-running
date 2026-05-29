# Performance path — where the watt-hours actually come from

A frank look at what "performance" means on an ultra-marathon watch, what the actual levers are for moving the metric that matters (battery life), and which tech-stack choices buy you real gains versus which are bikeshedding.

The single number that decides whether your watch is competitive in the ultra-marathon segment is **how many hours of GPS-on, HR-on, display-on runtime it gets from a charge.** Garmin's Fenix 7X Solar headline is ~89 hours single-band. The COROS Vertix 2 headline is ~140 hours. To compete in the segment you have to land in that ballpark. Every other metric — responsiveness, fix accuracy, HR fidelity — matters, but battery is the gate.

This doc ranks the tech-stack choices that move the battery number, from biggest impact to smallest, with concrete magnitudes wherever they can be cited. The pattern is depressingly consistent: **hardware choices dominate, and software micro-optimisations are second-order.**

## The big levers (multi-X impact)

These are the choices that change your battery life by a factor of two or more. They're all hardware. You make them once, at the chip-selection stage, and you live with the consequences.

### Display: Sharp MIP vs AMOLED — 3 to 4× total battery life

This is the single largest decision on the whole watch. A Sharp Memory LCD in always-on mode draws about 10 microamps. An AMOLED in always-on mode draws 5 to 10 milliamps. That's a ratio of 500 to 1000 times. The watch spends most of its life with the display on, so this delta cascades into something close to 3–4× total battery life.

This is why every ultra watch on the market uses Sharp MIP and every general-purpose smartwatch uses AMOLED. The trade is that MIP has a tiny colour gamut (8 colours), refreshes at about 10 Hz, and looks "old" next to AMOLED in a side-by-side demo. The trade is worth it for the ultra segment because the buyer cares about hour 26 of the 100-miler, not how the watch looks at REI.

### MCU: Ambiq Apollo510B vs Nordic nRF52 — ~25× active power

The Ambiq Apollo family uses sub-threshold voltage design — it runs the silicon below the conventional threshold voltage, trading some max-clock speed for active current. The Apollo4 introduced this approach (~4 µA/MHz active, ~3 µA sleep with RTC); **Apollo510B** is the current production-target part per [§ 90](../decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) and improves on Apollo4 by another ~2× on the same workload (Cortex-M55 + Helium MVE @ 250 MHz, integrated BLE 5.4 network processor). The nRF52840 is roughly 50 µA/MHz active. That's a ~25× active-power difference at the chip level between nRF52840 and Apollo510B.

Apollo4 family parts are what Fitbit Charge 6, Garmin Venu 3, and Huawei GT series moved to for exactly this reason; Apollo510B is the post-2025 generation. The nRF52840 is what you'd use for a bench prototype (because Zephyr and Embassy both support it first-class and the dev kit costs $50) and migrate away from for shipping silicon — see [§ 80](../decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) + [§ 92 Resolution](../decisions.md#resolution-2026-05-28--hybrid--92-long-term-goal---80-tier-1-preserved-as-deliberate-first-prototype-compromise) for the tier-1 framing.

### GNSS: dual-band snapshot chip vs single-band always-on — 2 to 3× GPS power

The way GPS chips traditionally work is to keep the radio receiver on continuously while tracking satellites. The way modern chips work is to wake the radio briefly, capture a snapshot of raw samples, post-process those samples to a fix, then sleep again. Sony's CXD5610 family supports both modes; older chips like the u-blox MAX-M10S only support continuous tracking.

For an ultra watch this is roughly a 2–3× reduction in GPS power at the same fix rate, or roughly 5–10× improvement in foliage / canyon accuracy at the same power budget. Either way it's huge. The trade is that snapshot mode adds a few hundred milliseconds of latency to each fix, which doesn't matter for a watch logging 1 Hz GPS.

### Sensor coprocessor — 2 to 3× always-on power

Modern wearable MCUs ship with a dedicated low-power core specifically for always-on sensor work. The Apollo510B has an integrated 48 MHz BLE 5.4 network processor (separate from the M55 application core); Apollo4 had the same shape with a different radio. The nRF5340 has a separate network core that can be repurposed. Discrete coprocessors (Bosch BHI260, STMicro LSM6DSV) handle step counting, basic HR, and motion classification at sub-microamp power while the main CPU stays in deep sleep.

The architectural rule is: **the main CPU never wakes for routine sensor reads.** It only wakes when the coprocessor signals something interesting — a step-count threshold, a heart-rate excursion, a motion event. For an always-on watch where the user only looks at the screen a few times an hour, this is a 2–3× improvement in the "watch is on your wrist doing nothing visible" power draw, which is most of the day.

## The medium levers (10 to 50% impact)

These are firmware-architecture decisions. They're software, but they're the kind of software decisions you make at the framework level — not micro-optimisations. Get them right early and you save a refactor; get them wrong and you'll be chasing leaks for months.

### DMA-driven I/O vs CPU polling — 5 to 10× active CPU time on sensor reads

When you read 100 bytes from a sensor over SPI, you have two options. Option A: write a loop that reads each byte one at a time, keeping the CPU awake for the whole transaction. Option B: hand the transaction to the DMA controller, sleep the CPU, and wake on the DMA-complete interrupt.

For typical sensor reads at 1–100 Hz, the active-CPU-time difference is 5–10×. Both Zephyr and Embassy default to DMA for SPI and I²C; the firmware mistake is writing a polling driver in C "just to get it working" and never going back.

### Tickless RTOS — 10 to 30% idle power

A traditional RTOS has a periodic scheduler tick (typically 1 kHz). Every millisecond the CPU wakes to check whether any task has work to do. If nothing has work, it sleeps again. The overhead of those wake-and-check cycles, at microamp-scale precision, is non-trivial.

A tickless RTOS sleeps until something has work to do. No periodic checks. The CPU might genuinely sleep for seconds at a time between sensor interrupts. Zephyr supports tickless mode (`CONFIG_TICKLESS_KERNEL`); Embassy is async-first so it's automatically tickless. Classic FreeRTOS is not tickless by default.

### Display partial updates — 10 to 30% display power

Sharp MIP displays support per-line updates. You don't have to redraw the whole screen for a small change; you can redraw only the lines that actually changed. LVGL handles dirty-region tracking automatically. A naive "redraw the whole screen every refresh" loop wastes most of the display-power budget.

### Multi-rail power tree — 10 to 30% device-wide

A naive power design puts everything on a single 3.3V LDO regulator. The display gets 3.0V (waste), the MCU gets 1.8V (waste), the radio gets 1.7V (waste). The voltage drop across the regulator burns as heat.

A proper design uses a PMIC with multiple regulated rails — typically a buck converter for the high-current display, an LDO for the MCU, and a separate rail for the radio. Each component gets its preferred voltage; the wasted headroom disappears. Saves 10–30% device-wide.

This is a PCB-design decision, not a firmware one. Worth noting because it's invisible until you're at tier 2+, and the urge to skip it on cost grounds is strong.

### BLE connection-interval tuning — 5 to 20% radio power

The default BLE connection interval is 7.5 ms — designed for HID devices like mice and keyboards. For a watch that syncs to the phone every few minutes, an interval of 1000 ms or longer is fine, and it cuts BLE radio power by ~100× for idle connections.

The Embassy `nrf-softdevice` crate and the Zephyr Bluetooth host both expose this; you change the connection parameters in your GATT service config.

## The small levers (don't optimise here first)

These are the choices that occupy a disproportionate amount of online discussion and don't matter much. The reason this section exists is so you can stop reading internet arguments about them and get back to the medium levers, which do matter.

**RTOS choice (Zephyr vs FreeRTOS vs RTIC vs bare-metal).** Within ±10% of each other for a sensible firmware. All of them sleep fine if you tell them to. Pick on tooling and ecosystem, not on perf.

**Language choice (C vs Rust vs C++).** Within ±5%. Both `rustc` and `clang` compile through LLVM to the same instruction stream. The reason to pick Rust is memory safety and modern tooling — not performance. The reason to pick C is the larger driver ecosystem — not performance. (See [decisions.md §80](../decisions.md) for why this project picked Rust + Embassy anyway.)

**Compiler choice (gcc vs clang vs IAR).** Within ±5%. The differences are real but small. Pick on which one your toolchain supports natively.

**UI library (LVGL vs Slint vs hand-rolled).** Within ±5% if you're disciplined either way (dirty-region tracking, no full redraws, no smooth animations). Pick on ergonomics, not perf.

**File system (LittleFS vs FATFS).** Within ±5%. LittleFS is just *better* for flash wear levelling; pick it for that reason, not for speed.

**Compiler flags (`-O2` vs `-O3` vs `-Os`).** Within ±5%. On a power-constrained MCU, `-Os` (optimise for size) often *beats* `-O3` because smaller code means more fits in the instruction cache and less time spent waiting on flash. Don't over-think this.

## What tier 1 should actually optimise for

Tier 1 uses a Nordic nRF52840 dev kit with the onboard debugger powered on, breakout boards instead of integrated silicon, a Sharp MIP breakout instead of a custom-cut display, and a CR2032 or 500 mAh LiPo instead of a custom cell. You will not measure ultra-watch battery life on this hardware. The dev board alone burns ~30 mA at idle just from the onboard debugger LEDs and the power LDOs that aren't optimised for sleep.

That's fine. Tier 1's job is not to hit production performance; it's to get the firmware architecture right so that the performance wins land at tier 2 when you migrate to production silicon.

The architectural rules to internalise during tier 1:

**Write everything DMA-driven and interrupt-driven from day one.** Polling is a habit that's painful to refactor out later. Async/await in Embassy makes this almost free; Zephyr's `k_work` patterns get there with discipline.

**Design with a sensor-coprocessor split in mind**, even though the nRF52840 doesn't have a great one. Structure code so the always-on path (steps, HR, baro) is isolated from the screen-on path (UI, GPS). Then when you migrate to Apollo510B (production target per [§ 90](../decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified)) or a discrete coprocessor, the boundary already exists.

**Plan for partial display updates** even though the bench prototype probably doesn't need them. LVGL's dirty-region invalidation is the right pattern; Slint's reactive UI model gets you there for free.

**Sleep aggressively.** Every wake event should be justifiable. `WFI` (wait-for-interrupt) is your friend. If you find yourself adding `Timer::after(Duration::from_millis(10)).await` to "give other tasks a chance," you've already lost the architecture battle — fix the root cause (probably a missing interrupt wire-up) instead.

**Pick a framework that natively expresses "sleep until something happens" instead of "tick every 10 ms and check."** Both Zephyr (tickless mode) and Embassy (async-first) qualify. FreeRTOS classic does not.

## The tier-1 to production migration path

When tier 1 is done and you've decided to push to tier 2, the migration looks roughly like this:

| Subsystem | Tier 1 | Production target | Power impact |
|---|---|---|---|
| MCU | Nordic nRF52840 | Ambiq Apollo510B per [§ 90](../decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified) | ~25× active-power improvement (Apollo4 → Apollo510B is another ~2× on top of Apollo4's ~10× vs nRF52840) |
| GNSS | u-blox MAX-M10S (single-band) | Sony CXD5610 (dual-band snapshot mode) | ~2× power, ~5× accuracy in foliage |
| Display | Sharp MIP 1.3" breakout | Sharp MIP custom-cut to case | Same chip family, same draw |
| Sensor coprocessor | None (main CPU does everything) | Apollo510B integrated 48 MHz BLE network processor or discrete BHI260 | ~2–3× always-on power |
| Battery | 500 mAh off-shelf LiPo | Custom 600 mAh pouch shaped to case | Same chemistry, different form |
| Power tree | Single 3.3V LDO on dev board | Multi-rail PMIC | 10–30% device-wide |

Each of these is a real chip swap with real firmware work. The firmware-architecture rules above (DMA, async, coprocessor split, partial updates, aggressive sleep) are what let the work be portable — the same `gps_task` should work on both MCUs with only a HAL change, the same display driver should work on both display footprints with only a pin remap.

That portability is the actual deliverable of tier 1.

## What "performance" doesn't mean here

A few things people sometimes mean by "watch performance" that aren't relevant to this analysis:

**UI responsiveness.** Sharp MIP is a 10 Hz display, so the user experience cap is "screen updates within 100 ms of a button press." That's easy to hit in any framework. There's no smooth-60fps target to chase.

**Boot time.** The watch is never off. It boots once per battery charge, every 4–6 days. Boot time doesn't matter.

**Sync throughput.** The watch syncs a couple of MB of GPS data to the phone over BLE once or twice a day. BLE peak throughput is sufficient and the user doesn't care if it takes 30 seconds.

**Map render throughput.** This one's marginally relevant — vector map pan / zoom should feel snappy, and a slow renderer is one of the things that makes Garmin and COROS look dated. But the bar is "doesn't feel sluggish," not "60 fps." A bench-prototype-quality renderer hits the bar; production polish gets it to "smooth."

Almost all the discussion you'll find online about "improving embedded performance" — choice of compiler flags, choice of allocator, choice of math library, choice of trigonometry approximation — is irrelevant to this watch. The thing that decides whether your watch competes is the four big-lever decisions at the top of this doc. The medium levers are the difference between "competes" and "wins." Everything else is rounding error.
