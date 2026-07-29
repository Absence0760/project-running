# Quality standards — the verification ladder + the tier-1 bench checklist

Tier 1 has exactly one formal completion bar: [decisions.md § 82](../architecture/decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype) — one real outdoor run producing a GPS+HR-tagged track that syncs end-to-end to Supabase. That bar is deliberately narrow and it is not changing. But it left two things undefined, and both cost real credibility:

1. **The verification vocabulary was never defined.** The docs and the workspace README use a four-rung ladder — *host-tested* → *build-verified* → *sim-verified* → *bench-verified* — that has never been written down anywhere. The rung that actually matters (bench-verified) has the least written about it, and 13 of the 43 feature-parity items in [`roadmap.md`](roadmap.md#feature-parity-backlog-garmin--coros-table-stakes) sit annotated "implemented" but deliberately unticked "pending bench verification" against a definition that doesn't exist.
2. **There is no falsifiable hardware-side standard for tier 1 at all.** Tier 2 has real targets (≥24 hr GPS battery, 100 % outdoor fix reliability — [`prototyping.md`](prototyping.md#tier-2--wearable-prototype-15k40k-diy-80k250k-consultant-built-918-months)). Tier 1 has a DoD about a run syncing and nothing about whether the hardware behaved while it did. [§ 83](../architecture/decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem) is explicit that the PPK2 numbers *inform* tier-2 planning and **do not gate** tier-1, and § 82 explicitly declines to set kill criteria. So the day the parts arrive, "did bring-up work?" would be decided by vibe.

This doc closes both gaps. **It does not change § 82's Definition of Done** — see [What tier 1 does not have to hit](#what-tier-1-does-not-have-to-hit). It defines what each rung means and what may be claimed at it, and it turns the bench-verification phase into a checklist someone can run against real hardware and get a yes/no or a number out of.

Read alongside [`roadmap.md`](roadmap.md) (tier structure + the parity backlog), [`parts.md`](parts.md) (what hardware will exist), [`performance_path.md`](performance_path.md) (where battery life comes from), [`prototyping.md`](prototyping.md) (what "working" means per tier), and [`tier1_log.md`](tier1_log.md) (where the evidence gets recorded). Per-step bring-up status lives in [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md).

## The four verification rungs

The ladder is about **what evidence exists**, not about how much work went in. A rung is a claim about the world, so each one has to name the evidence that earns it.

| Rung | Evidence | Ceiling |
|---|---|---|
| **host-tested** | `cargo test` green on the host for a pure `no_std` crate | Says nothing about the target, the peripherals, or the wire |
| **build-verified** | Compiles + links for `thumbv7em-none-eabihf` in the relevant feature sets; `fmt` + the clippy gate green | Says nothing about runtime behaviour |
| **sim-verified** | The unmodified release ELF ran on Renode and a named observable changed as predicted | Says nothing about real silicon, analog behaviour, the radio, or power |
| **bench-verified** | The same firmware ran on a real nRF52840 DK with the real part wired, and a recorded measurement or capture met a stated criterion | Says nothing about production silicon, in-case RF, or multi-day endurance |

### host-tested

**Earned by:** a `cargo test` pass on the host for hardware-free logic — `watch_core`, the driver crates' pure halves, `watch_render` and its ASCII-preview harness. For a parity port ([§ 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)), the tests must mirror the web `.test.ts` case-for-case, so the rung also carries "this agrees with the canonical web helper".

**Does NOT prove:** that the code compiles for the MCU target (host `std` tests can pass on code the embedded build rejects); that any register sequence matches silicon; that a wire format survives a real transport; that the numbers reach a panel. A host test over a *driver* pins what the driver believes about the part — it cannot pin what the part does.

**May be claimed:** "host-tested", "mirrors the web helper test-for-test", "the logic is pinned". Never "works", never "verified", never a bare "implemented" without the rung attached.

### build-verified

**Earned by:** a clean build for `thumbv7em-none-eabihf` across each feature set the change touches — the default (sim/UART) build, `--no-default-features --features ble`, and the sim feature set — plus `cargo fmt --check` and the CI `clippy -D warnings` gate. For the BLE build this includes linking against the S140 SoftDevice and the `memory-ble.x` script.

**Does NOT prove:** that anything runs. It does prove three specific things worth naming, because they were the real risks: the dependency stack resolves (the one plausible § 80 "blocking driver issue" for Rust + Embassy), the linker script and memory-map arithmetic are self-consistent, and the code is reachable from a genuine target build rather than living behind a host-only cfg.

**May be claimed:** "compiles and links for the target". Per [§ 210](../architecture/decisions.md#210-tier-1-ble-s140-softdevice-is-a-compile-verified-feature-gated-build--mutually-exclusive-with-the-sim-off-by-default) this is the **ceiling** for the whole SoftDevice path short of the bench — the sim cannot run proprietary Nordic firmware, so BLE can never be sim-verified and jumps host/build → bench directly.

### sim-verified

**Earned by:** running the *unmodified* release ELF on Renode (`bin/watch-sim.sh`) and capturing a named observable that changed as predicted — a specific `defmt` line, a panel dump, a fixture-driven sequence. A claim must say *what* was observed, not merely that the sim ran. The precedent for how to record it is `apps/custom_watch/sim/verification-2026-07-19/` (evidence excerpts plus an explicit verified / not-verified matrix).

`apps/custom_watch/sim/ci_smoke.py` is the same rung run non-interactively, and the `sim-firmware` CI job is what keeps it from rotting between manual passes. It carries a `--scenario` selector — `smoke` (the seven-assertion record → store → panel → stop sequence that the 2026-07-19 pass stands behind), plus `pages` (each run-view page produces a non-blank frame), `alerts` (the fuel / zone / off-course banner path) and `terrain` (the pages the flat fixture cannot arm). **The `pages` and `alerts` scenarios first ran green in CI on 2026-07-26** — all three steps executed rather than being skipped, which is worth checking explicitly since a skipped step also leaves a job green. They now carry the rung for exactly what they assert: the cycle advances with the panel following it (the `ui: page` line cross-checked against the button task's), five named pages render non-blank and byte-distinct, and an alert banner inks the hero band.

**`terrain` (added 2026-07-29) is the positive half of a claim the others could only make negatively.** A page absent from the bench_jog walk is absent for a legitimate reason — nothing arms it — so the walk alone cannot distinguish "correctly hidden" from "data-presence bit wired to the wrong field", which reads identically. `terrain` boots `mountain_loop`, marks a waypoint with the BTN5 hold (§ 357) and ramps the BMP581 model past the 20 m a climb opens at (§ 359), then asserts both pages enter the cycle and render. Its two arming steps are asserted in their own right, so a failure names the arming rather than the page. Note the fixture is bound to the scenario in `SCENARIO_FIXTURES`, not passed at the call site: run on bench_jog it would fail while the firmware was correct.

Renode **is** installable on the current authoring workstation (1.16.1, Fedora rpm), so a scenario can now be run locally before it reaches CI — `terrain` was. That lowers the cost of authoring one; it does not change what the rung means, and CI remains what keeps these from rotting between passes. Nothing else moves rung on their strength; the observable a scenario names is what earns the rung, item by item. Note also what a render assertion is *not*: a non-blank frame is not a correct number and not a legible one. Value correctness stays with the host tests, and legibility is bench-only (step 4).

**Does NOT prove — the honesty limits, which are load-bearing:**

- **BLE is out of scope entirely.** Renode cannot run the S140 SoftDevice ([§ 210](../architecture/decisions.md#210-tier-1-ble-s140-softdevice-is-a-compile-verified-feature-gated-build--mutually-exclusive-with-the-sim-off-by-default)). RAM origin, interrupt priorities, connection parameters, pairing/bonding, the `run_manifest` / `run_chunk` / settings / course-push characteristics: none of it is sim-reachable.
- **Power is out of scope entirely.** Renode does not model current. Every power claim in the workspace is a *derivation*.
- **The sensor models are synthetic and pinned to the driver, not to silicon.** The MAX86177 and BMP581 Renode models answer the register sequences the drivers issue, with a deterministic triangular PPG and a scripted altitude. That verifies the *path* — bus, FIFO demux, duty-cycle shutdown/wake, the accumulators, the render — and not register semantics, bus timing, analog noise, settling, or the real optical signal. A model that agrees with the driver's belief cannot detect a wrong belief.
- **No SAADC.** The battery-gauge sampling path is not sim-verifiable; only "the task parks cleanly and the faces render without it" is.
- **No RF, no antenna, no thermal, no mechanical.**

A sim pass is nonetheless worth a lot: the 2026-07-19 pass found a real recorder bug (the un-ported `run_recorder` #330 gap re-anchor, which froze distance for the rest of a run after a dropout), an RTC overflow that froze the recorder 8.5 min in, and a free-running HR waker re-rendering the UI 50×/s. That is what the rung is *for* — it just isn't the wrist.

**May be claimed:** "sim-verified: \<the observed behaviour\>". Never generalised to the device, and never used to tick a parity-backlog item.

### bench-verified

**Earned by:** the same firmware running on a real nRF52840 DK with the real breakout wired, where a **stated criterion from the checklist below was met and the evidence recorded** — a `defmt` capture, a PPK2 trace, a photo of the panel, a Supabase row id. "I flashed it and it seemed fine" is not the rung; the criterion and its evidence are the rung.

**Does NOT prove:**

- **Production power.** The DK burns ~30 mA at idle from its onboard J-Link, LEDs and non-sleep-optimised LDOs, which dwarfs anything the firmware does — this is exactly why [§ 83](../architecture/decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem) mandates *per-subsystem* PPK2 measurement and calls whole-device readings useless as a baseline. A bench-verified subsystem current is a tier-2 *projection input*, not a battery claim.
- **Anything about tier-2/3 silicon.** Bench results are for nRF52840 + MAX-M10S (single-band L1) + MAX86177 + BMP581-class parts on breakouts. The production targets are Apollo510B + a dual-band snapshot GNSS ([§ 90](../architecture/decisions.md#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified)); breakout results do not transfer.
- **In-case RF.** Breakouts have poor RF tuning and no case. Per [`prototyping.md`](prototyping.md#why-rf-is-the-line-item-that-surprises-everyone), getting from a working breakout fix to a working in-case fix is 2–6 weeks of an RF engineer's time. A good bench fix says nothing about the tier-2 unit.
- **Endurance, weather sealing, shock, foliage, urban canyon, or a multi-day run.** § 82 puts all of that at tier 2+.
- **Button feel.** The DK's tactile switches are not watch buttons; see the [step 7 checklist](#step-7--integration-recording-storage-controls) for what *is* testable.

**May be claimed:** "bench-verified on the nRF52840 DK: \<criterion\> = \<result\>". This is the rung that lets a parity-backlog item be ticked and the only rung that satisfies § 82.

### Rung rules

- **A rung is not inherited.** Editing a bench-verified module drops it back to whatever the *new* evidence supports. The rung belongs to the code that was tested, not to the module name.
- **A rung claim names its evidence.** A doc line that says "verified" without saying which rung and against what is a defect in the doc.
- **Rungs are not strictly sequential, but they are not substitutes.** BLE skips sim by necessity. A pure parity core may never leave host-tested and that is fine ([§ 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) — some ported cores have no wrist surface). What is never allowed is letting a lower rung stand in for a higher one in a claim.
- **Where evidence lives.** Sim evidence follows the `sim/verification-<date>/` precedent. Bench evidence belongs in a dated [`tier1_log.md`](tier1_log.md) entry — which already reserves a photo/video slot per entry for exactly this — with per-subsystem PPK2 numbers captured as § 83 requires. [`parts.md`](parts.md)'s order checklist is ticked on receipt, not on order.

## Tier-1 bench-verification checklist

One line per claim, each a yes/no or a number, ordered by the bring-up steps in [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md). **None of this gates tier-1 completion** — § 82's DoD does. This is how the bench phase is *conducted and claimed*: a failed item is a recorded finding and a tier-2 input, not an un-completion.

Where a criterion could not be justified from an existing doc it is marked **(open value)** — record the first real measurement and set the bar then, rather than inventing a precise-sounding figure now.

### Step 0 — before the board is powered

- [ ] **Every part on [`parts.md`](parts.md) received and ticked** (tick on receipt, not on order).
- [ ] **The delivered Sharp panel's resolution matches the framebuffer.** `sharp_mip` compiles a fixed 168×144 (21 text columns × 9 rows of the 8×16 font). `parts.md` lists "1.3" 168×144" but names order number **LS013B4DN04**, and those may not be the same part — confirm the delivered module's datasheet resolution *before* wiring, and correct `parts.md` (or the framebuffer constants) if they disagree. A mismatch silently corrupts every line-update address.
- [ ] **EXTMODE / EXTCOMIN strapping confirmed on the real breakout.** The driver holds EXTMODE high and drives a ~3.8 Hz PWM on EXTCOMIN so a clean framebuffer flushes zero SPI. Some breakouts hard-strap EXTMODE — if this one does, the hardware-VCOM power path is invalid and the software VCOM bit must come back.
- [ ] **First flash: toolchain end-to-end.** `bin/watch-doctor.sh` clean, `bin/watch-flash.sh` builds → flashes → streams decoded `defmt` from the real board. This is the single item that retires "no on-board verification yet".

### Step 3 — GNSS (u-blox MAX-M10S, single-band L1)

- [ ] **Cold time-to-first-fix under open sky ≤ 60 s.** From an unpowered receiver, clear sky, stationary. Source: [`prototyping.md`](prototyping.md#what-working-means-at-this-tier) tier-1 "GPS fix in <60 s outdoor". Record the actual value.
- [ ] **Warm/hot restart TTFF recorded. (open value)** No existing doc sets a tier-1 warm-start bar. Measure it (receiver re-powered within a few minutes, ephemeris still valid) and set the bar from the first measurement.
- [ ] **Sustained 1 Hz fix rate in Performance mode.** Source: `prototyping.md` "logs NMEA at 1 Hz". Confirm from the `defmt` stream over ≥ 5 continuous minutes: fix count ≈ elapsed seconds, no parser rejections.
- [ ] **Fix cadence matches the selected GNSS mode: ~1 s / ~15 s / ~60 s** for Performance / Balanced / Expedition. Sim-verified already; bench-confirm on real NMEA where the receiver, not a fixture, sets the timing.
- [ ] **The receiver actually enters backup mode on UBX-RXM-PMREQ, and wakes on the 0xFF byte.** This is the *only* place the GNSS power-down lever can be verified — the sim's feed ignores PMREQ by design. Confirm both directions: fixes stop during the window, and the first fix after the wake byte arrives inside the reacquire margin. Then measure the receiver's sleep-vs-tracking current on the PPK2 (below); that measurement is the lever's real payoff.
- [ ] **Dropout honesty over a measured jog.** Run a route with a known signal-poor stretch (underpass, dense canopy, building line). Confirm: the panel reads `STALE` / 0 signal bars during the void rather than a frozen-fresh position; and — the bug the 2026-07-19 sim pass found — **distance resumes accruing after reacquire** rather than freezing for the rest of the run (`run_recorder` #330 gap re-anchor). Record the observed dropout fraction of the jog. **The acceptable dropout rate is an open value** — tier 2's "100 % outdoor fix reliability" bar is explicitly *not* tier 1's, and a breakout antenna with no case cannot be held to it.
- [ ] **GSA-derived signal meter is honest on real sky.** Fix type 0/1 reads 0 bars even with satellites in view; 2D caps; 3D uses the full ladder.

### Step 4 — display (Sharp MIP, reflective, no backlight)

- [ ] **Panel initialises and renders the idle face on the real module** — line-update wire protocol correct at the delivered resolution, no shear, no inverted rows.
- [ ] **A resting screen flushes zero SPI lines.** The dirty-line + compare-write contract plus hardware EXTCOMIN VCOM is a load-bearing power claim; confirm on the logic analyser (no SPI traffic while the framebuffer is unchanged) and again on the PPK2 (display-rail current with a static screen).
- [ ] **Direct-sun legibility, read at arm's length, no touching the watch.** Midday direct sun. Read (a) the 32×48 numeral hero on the Distance/Pace glance pages, (b) the 16×32 medium face, (c) the 8×16 context rows, (d) an inverse-video banner (`! DRINK`, `OFF COURSE`, `STOP? BTN2`). Yes/no per tier. A reflective MIP panel *gains* contrast in sun, so a failure here is a **layout / font-size finding**, not a panel finding — record which tier failed and at what distance.
- [ ] **Headlamp legibility at night, same four tiers, same protocol.** There is no backlight at tier 1, so this is the honest night test.
- [ ] **Off-axis + sweat/rain-on-glass legibility recorded. (open value)** No doc sets a bar; record whether the hero stays readable at the wrist angle a running arm actually presents.
- [ ] **The `+` / `|` glyph repair holds on the real panel.** The Pacer page's whole purpose is a signed `+0:42` / `-1:05` delta and the VERT row's `+gain -loss`; two sim passes independently caught these rendering as `-` and as blank. Confirm on glass, not only in a framebuffer test.
- [ ] **Battery-gauge icon: no fabricated percentage on the DK.** USB-powered, the DK regulates VDD to ~3.0 V and the plausibility band must read that as **absent** (no icon, no `BAT` row) — not a confident 0 %. Then wire the 500 mAh LiPo and confirm a plausible percent appears. Note the recorded bench follow-up: a direct-VDD read at the default SAADC range (gain 1/6, 3.6 V full scale) rails below a fresh 4.2 V charge, so the cell belongs on the VDDH/5 input in high-voltage mode.

### Step 5 — optical HR (MAX86177)

- [ ] **~25 Hz sampling with a displayed BPM on-wrist.** Source: [`prototyping.md`](prototyping.md#what-working-means-at-this-tier) "Optical HR sample at 25 Hz, displays current bpm".
- [ ] **Resting BPM within ±5 bpm of a reference over a 60 s still hold. (open value on the tolerance)** No doc sets an accuracy bar and the licensed Maxim algorithm is explicitly post-tier-1 (§ 82 accepts "raw photodiode reads + naive peak-detect"). Compare against a chest strap or a manual pulse count, record the delta, and set the bar from the first measurement. The tier-1 claim is "a plausible pulse is detected and displayed", not "clinically accurate".
- [ ] **Off-wrist reads honest "no HR", never a garbage BPM off ambient light.** Lift the sensor off the skin under room light and under bright sun; confirm `--` rather than a fabricated number in both.
- [ ] **Bright-sun saturation is honest both ways.** With ambient subtraction: a corrected DC back in band recovers a real BPM; a raw sample pinned at the 19-bit full scale **stays** saturated and blank. This is the one place the ambient/dark-slot design can actually be tested — the sim model's ambient is synthetic common-mode.
- [ ] **Duty-cycling really shuts the part down and the register file survives it.** Balanced mode: 15 s on per 60 s window. Confirm the part is in shutdown between windows (PPK2 current step, not just a `defmt` line), that the FIFO is flushed on wake so pre-shutdown counts can't replay, that no re-init or AGC re-walk is needed after wake (**register retention across shutdown is currently a documented bench-verify assumption**, exercised in-sim against a model that was told to retain), and that the displayed BPM is honestly *held* then blanked at its budget rather than re-sampled.
- [ ] **LED AGC converges on real skin, across skin tones and under motion. (open value)** The AGC's step/hysteresis/clamp constants are conservative starting points flagged for on-device calibration. Record where it settles; do not claim tuned.
- [ ] **Motion-artifact rejection on a descent.** The 30–220 bpm physiological band + peak-hold SNR gate should keep `valid=false` under sustained artifact rather than reporting a spurious-fast BPM. Wrist HR on high-cadence trail descents is famously bad ([`vision.md`](vision.md) req #8) — the tier-1 claim is honest invalidity, not correctness.

### Step 6 — BLE GATT (S140 SoftDevice) — the whole rung is new at the bench

Everything here is currently **build-verified only** and can never be sim-verified ([§ 210](../architecture/decisions.md#210-tier-1-ble-s140-softdevice-is-a-compile-verified-feature-gated-build--mutually-exclusive-with-the-sim-off-by-default)). This is the largest block of untested surface in the workspace.

- [ ] **S140 hex + app flash together and boot.** Confirm the RAM origin the SoftDevice reports at boot matches `memory-ble.x`'s assumption, and that peripheral interrupt priorities at P2 clear the SoftDevice's reserved 0/1/4.
- [ ] **The phone discovers and connects to the Threkir service**, and the negotiated connection interval is ~1 s (not the 7.5 ms HID default) — the ~100× idle-radio-power lever from [`performance_path.md`](performance_path.md#ble-connection-interval-tuning--5-to-20-radio-power).
- [ ] **Just-works LESC pairing completes, one bond persists, and an unbonded central can read nothing.** Confirm the `BND1` record survives a power cycle and that a re-connect after reboot resumes encrypted without re-pairing.
- [ ] **`CFG1` and `BND1` coexist on the config page** — writing either carries the other forward, across a real erase/write cycle.
- [ ] **Live link frames notify at ~1 Hz** and decode in the app with the transport-agnostic decoder (same bytes as the UART transport).
- [ ] **Settings push applies over the radio.** A v3 `SET1` frame sets max HR / pacer goal / fuel intervals / QNH / timezone / page mask; a bad-flags frame is **rejected** (fail-closed) rather than partially applied. Confirm the timezone push flips the home clock hero `UTC` → `LOCAL`.
- [ ] **Course push over the chunked write characteristic** loads a real course; the Nav page draws it and stops reading `NO COURSE LOADED`.
- [ ] **Flash writes are SoftDevice-arbitrated.** The `ble` build aliases the run-store backend to `nrf_softdevice::Flash`. Confirm a commit *and* a mid-run checkpoint complete with the radio connected and advertising — a raw-NVMC write under an active SoftDevice is the classic way to hang or corrupt.

### Step 7 — integration (recording, storage, controls)

- [ ] **§ 82's DoD, in one run.** Outdoors, on a real wrist (Velcro is fine), the run records GPS + HR, shows pace + distance on the MIP panel, and syncs over BLE to the paired phone, which writes `{user_id}/{run_id}.json.gz` to the `runs` Storage bucket. **This is the DoD, not a checklist item among equals.**
- [ ] **The synced row matches the wrist.** Distance, elapsed, moving time, and lap count on the Supabase row agree with the panel's final numbers within rounding; the track renders as a sane line on the map; per-point `bpm` and altitude are present where the sensors were live and *empty* where they were not (never stale).
- [ ] **Laps: 1 km auto-lap and BTN4 manual lap both close and both persist.** Run-store v2 stores laps as interleaved tagged records; confirm they arrive as the registered `metadata.laps` shape.
- [ ] **Auto-pause at the 0.5 m/s gate, and a snapshot-honest state tag.** Stop dead → `AUTO`; press BTN1 → `PAU`; walk slowly through the 3 m min-move filter → steady `REC`, not a flicker.
- [ ] **The 253-point flash cap behaves at the boundary.** Run past the cap in Performance mode and confirm run-store v2 **decimates rather than truncates**: the whole run stays represented at coarser resolution, laps are never dropped, the wrist shows `! TRACK 1/k RES`, and the phone still verifies the CRC and ingests it. Then check the boundary exactly: 252, 253, 254 stored anchors.
- [ ] **All four slots fill, and eviction sacrifices the right run.** Record 5 runs without syncing; confirm the `synced`-flag victim rule sacrifices a fully-pulled run before a still-unsynced finished one.
- [ ] **A run survives a reboot mid-recording.** Pull power mid-run and confirm the 300 s / 60-point checkpoint recovers a *partial* run rather than nothing; that boot-time slot recovery re-advertises runs from a prior power cycle (footer magic + CRC scan, no RTC); that `next_run_seq` resumes above the highest recovered seq; and that the phone dates a prior-boot run sensibly rather than in the future.
- [ ] **The 256-point / 4 KiB course cap rejects an overflow rather than truncating mid-race**, and a longer course is phone-simplified before the push. Check the boundary: 255, 256, 257 points.
- [ ] **Off-course alert latches at 40 m and re-arms below 20 m** on a real GPS trace — no flapping at the boundary, and the banner is steady (never blinking, so a lost runner cannot catch a blank frame).
- [ ] **Barometric altitude and vert on real weather.** QNH re-zero (BTN3 hold on the idle face) snaps the bias, refuses honestly with `NO GPS FIX` / `NO BARO`, and never banks the step as vert. Over a flat out-and-back with a pressure trend, confirm the complementary filter subtracts drift instead of banking phantom vert; over a real climb, confirm gain is within a plausible margin of a known reference. **The filter's tuning constants are conservative starting points — record what they need, don't claim tuned.**
- [ ] **Press grammar, one-handed, with cold and gloved fingers (§350).** Debounce holds; a BTN4 tap pages right and a BTN3 tap pages left — the spatial pair, in every run view including `FIN`; a 0.5 s hold on either paging key opens the page grid *at the threshold* (mid-hold, no release timing); the grid's 3 s inactivity auto-select works and BTN1 confirms a jump (`B1 GO`); BTN2's two-press stop guard arms with a visible `STOP? BTN2` prompt and disarms after 4 s; BTN5 — the external momentary on P0.02, the DK has no fifth button — takes a lap with no perceptible latency; BTN1 dismisses a finished run. **Explicitly out of scope: button *feel*.** The DK's tactile switches are not watch buttons — actuation force, travel, and glove operability are tier-2 mechanical concerns ([`prototyping.md`](prototyping.md#tier-2--wearable-prototype-15k40k-diy-80k250k-consultant-built-918-months) "has buttons that feel like buttons"). What tier 1 can falsify is whether tap and hold are distinguishable by a tired hand at the single 0.5 s boundary — record any press that landed on the wrong tier.
- [ ] **The settings menu, one-handed (§351, directional).** Idle BTN5 opens it; BTN2/BTN3 (the UP/DOWN slots) step the cursor up/down; BTN1/BTN5 edit right/left — GNSS MODE ladders toward Expedition on right and clamps at both ends (no wrap-teleport), HIDE EMPTY is right=ON / left=OFF and **survives a power cycle** (CFG1); RE-ZERO fires on right and closes with the idle banner answering; BTN4 (the BACK slot) exits; 30 s of no presses closes it back to the clock; and no press inside it can start, pause, or lap a run.
- [ ] **The filtered page cycle is honest.** An unsynced watch cycles only data-present pages (roughly 8–12, not 37 empty-state stops); every synced-only page reads `NOT SYNCED` rather than zeros; the page-dot indicator counts the filtered set. Stays bench-gated: the sim's `pages` scenario is authored to check that each page *renders*, which is a different claim from the filter being right on a watch that has actually been synced by a phone — and the sim has no phone.
- [ ] **A waypoint mark survives a battery pull (§357).** Hold BTN5 mid-run, confirm the `WPT` page shows a distance that grows as you walk away and a bearing that points back; pull power, reboot, and confirm the mark is still there with the same coordinates. Then check what the host cannot: that the hold is distinguishable from the lap tap by a cold hand at the single 0.5 s boundary (record any press that landed on the wrong tier — a mis-tiered press here costs a lap, not just a page), and that the eight-slot store's newest-wins eviction behaves on the ninth mark.
- [ ] **The ICE card reaches a stranger (§358).** The one item on this list whose pass criterion is another person: hand the powered watch to someone who has not seen it and ask them to find the wearer's emergency contact. Record how long it took and what they pressed. Confirm the card survives a power cycle (the `ICE1` record), that a `SET1` v6 push carrying a corrupt field leaves the *previous* card standing rather than half-applying, and — the known tier-1 limit, so measure its cost rather than assuming it — how much worse the same task is while a run is recording, since the face is idle-only.
- [ ] **Climb detection on a real hill (§359).** The thresholds (20 m open, 10 m close, ≥ 2 %) are conservative starting points chosen against baro noise, not tuned against terrain — **record what they need, don't claim tuned**, exactly like the vert filter above. On a real rolling course confirm a roller never opens a climb and a saddle mid-ascent never re-zeroes the banked gain; on a pushed course with elevation, confirm the crest-ahead number shrinks monotonically toward a summit you can see and does not stop early on a shelf.
- [ ] **≥ 8 hours of continuous GPS recording on the 500 mAh LiPo.** Source: [`prototyping.md`](prototyping.md#what-working-means-at-this-tier) tier-1 "Battery powers the system for ≥8 hours continuous GPS (the dev board itself burns most of the budget)". Note the caveat *in the claim*: this is a DK-plus-breakouts figure dominated by the debugger and the non-sleep LDOs, and it is **not** a watch battery number.
- [ ] **A 24 h+ uptime soak with no freeze.** The RTC overflow the sim found froze the recorder 8.5 min in; every timer, counter and `999h` display field wants a long real run over it. Record the longest continuous recording achieved.
- [ ] **The 3D-printed chassis holds the breakouts + LiPo and takes a Velcro strap** well enough to jog in. Source: `prototyping.md` tier-1 deliverables. Not a case, not sealed, no IPX claim.

### Power instrumentation (per [§ 83](../architecture/decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem))

Five rigs, PPK2 wired **between each isolated subsystem and its power input** — never whole-device, because the DK's ~30 mA idle makes that reading meaningless. Each produces a number recorded in [`tier1_log.md`](tier1_log.md).

- [ ] **Bare-MCU deep-sleep current.** Everything else powered off.
- [ ] **GNSS module: acquisition vs tracking vs backup**, measured separately — this is what turns the UBX-RXM-PMREQ lever from a derivation into a number.
- [ ] **MAX86177 across LED-on / LED-off / readout**, and the shutdown current between duty-cycle windows.
- [ ] **Sharp MIP: static, per-line update, full-frame redraw.** Datasheet-derived sanity anchor: ~10 µA static ([`vision.md`](vision.md) req #3, [`performance_path.md`](performance_path.md#display-sharp-mip-vs-amoled--3-to-4-total-battery-life)).
- [ ] **Combined "all sensors live" rig**, still excluding the debugger and LEDs.

**Pass criterion for all five:** a number exists, and it is within an order of magnitude of the part's datasheet figure. A reading that disagrees with the datasheet by more than ~10× means **the rig is wrong**, not the datasheet — re-wire before recording. Absolute targets are deliberately absent: § 83 is explicit that these inform tier-2 planning and do not gate tier-1, and the only figures the docs commit to are tier-2/3 projections (nRF52840 ~50 µA/MHz active, Apollo-class ~3 µA sleep, MIP ~10 µA static). **Any tier-1 sleep-current target is an open value** to be set from the first clean measurement.

## Derived-not-measured numbers this checklist finally lets someone confirm or refute

These are the figures currently shipping in the firmware and its docs as **derivations, not measurements** — honest, and labelled as such (the idle face even renders the battery figure as `EST`), but nothing on the device is checkable against reality until the PPK2 rigs run. Listed so the bench phase knows exactly which claims it is there to settle.

**Battery projections (highest-value, least-supported):**

- **The ~110 / ~180 / ~220 h GNSS-mode figures** for Performance / Balanced / Expedition. Derived in `watch_core::gnss_mode`'s module docs from [`vision.md`](vision.md)'s tier-2 ~110 h target plus [`performance_path.md`](performance_path.md)'s GNSS duty-cycling lever. They already *assume* the UBX-RXM-PMREQ receiver power-down, which has never run on a receiver. Refuting these is the single most valuable bench outcome, because they are the numbers a reader is most likely to mistake for measurements.
- **The HR duty-cycle saving** (15 s per 60 s / 120 s window). Deliberately **not** folded into the GNSS-mode projections precisely because it is unmeasured — keep that separation until the PPK2 says otherwise.
- **The GNSS power-down scheduler's constants** (sleep window, 5 s reacquire margin, PMREQ self-wake backstop duration).
- **The battery-percent curve.** A piecewise-linear 1S LiPo *resting*-discharge model; a loaded cell sags below the anchors, so the displayed percent is systematically optimistic under load by an unmeasured amount.
- **The mid-run checkpoint's flash-wear estimate** (~1200 page erases in a 100 h run, ~12 % of endurance).

**Capacity limits — bench-prototype foundations, explicitly not shipping capacity:**

- **The 253-point-per-run cap over 4 × 4 KiB internal-flash slots.** A few minutes of track per run at 1 Hz. A real ultra is ~360k points; that needs the tier-2 external QSPI flash, and the retention/overflow policy for *that* store is still an open architectural choice ([`roadmap.md § Smaller considerations`](roadmap.md#smaller-considerations)). Run-store v2's decimation makes a full slot hold the whole run *coarser* rather than losing its tail — which is the right behaviour and still not capacity.
- **The 256-point / 4 KiB course cap.** Any real ultra course must be phone-simplified before the push.
- **The 64-lap storage budget, the 96-point trackback breadcrumb, and the 64-sample elevation ring.** All fixed-RAM display structures sized for a bench prototype.

**Sensor tuning constants flagged for on-device calibration:** the GPS-baro complementary filter's slew, the ambient-subtraction and raw-DC-rail thresholds, the LED AGC's step/hysteresis/clamps, and the off-wrist / saturated contact bands. Every one is a conservative starting point chosen without a sensor on a wrist.

**Publish-gate quanta (new 2026-07-25):** `elevation::PUBLISH_STEP_M` = 0.1 m is chosen as an order of magnitude above the BMP581's noise floor at the driver's configured 16× OSR + IIR coeff-7 — a **datasheet-class derivation, never measured on the part**. Set it too fine and a resting wrist wakes the CPU on noise; too coarse and the live GAP estimator, which reads a grade off ~5 m segments, sees a stepped altitude. The bench item is: log the raw baro stream over a 60 s motionless hold and record the actual peak-to-peak spread, then confirm the step still clears it. The GSV/GSA bar-count gate needs no calibration (the quantum is the drawn meter itself) but is **untestable under Renode** — every sim NMEA fixture is single-constellation GPS-only, so the multi-constellation repeat the gate exists to absorb has never been exercised.

**One structural assumption, not a number:** that the MAX86177 **retains its register file across `shutdown()`**. The firmware's wake path depends on it (no re-init, no AGC re-walk), the Renode model was written to honour it, and no silicon has confirmed it. It is called out in the step-5 checklist for that reason.

### Added 2026-07-25 (from the defect sweep, decisions § 316 + § 317)

- [ ] **Battery: move the cell onto the SAADC VDDH/5 input with high-voltage mode, then re-check the top of the charge curve.** On the DK's direct-VDD read a full 4.2 V cell saturates the converter, so the gauge now honestly reads *absent* across roughly 4.2→3.6 V rather than reporting a confident ~8 %. Pass criterion: a freshly charged cell reads near 100 %, and the percent falls monotonically across a discharge. Until this is done the gauge is blank for much of a charge cycle by design, not by defect.
- [ ] **Exercise a pipelined BLE chunk pull.** The chunk-request path is now a depth-8 queue rather than a single-value signal, so two requests in flight can no longer silently drop the first. Pass criterion: a phone that issues several `run_chunk` requests without waiting receives an answer to every one, and a deliberate overflow past the queue depth produces the `ble: chunk queue full` warning rather than a silent stall. The queue's own semantics — FIFO order, the depth, an overflow refused rather than swallowed — are **host-tested** since decisions § 320, against the same `embassy_sync` `Channel` the task builds; what the bench still owes is that a real phone over a real radio drives them, which cannot be sim-verified (no SoftDevice under Renode).
- [ ] **Confirm checkpoint ping-pong survives a real brownout.** Checkpoints alternate between two slots so a torn write leaves an intact predecessor. Pass criterion: cutting power mid-checkpoint leaves a recoverable run-so-far on flash at the next boot, repeatedly, and the recovered copy is the newer intact one.
- [ ] **Confirm a failed commit still serves the surviving checkpoint, without a reboot.** The commit now seals before it drops (decisions § 322): the superseded checkpoint keeps its directory entry until the new bytes are down, and a failed erase/write promotes that checkpoint to advertisable instead of losing the run from RAM. Pass criterion: force the commit's flash write to fail on a run that has checkpointed (a write-protected page, or a deliberate error injected at the NVMC seam), and the still-connected phone can pull the run — reading back the checkpoint's blob, verifying, at the size the manifest advertises — with no power cycle in between. Host-tested over a flash model only; whether a real NVMC failure surfaces as an `Err` at all, rather than as a silent partial write, is exactly what the bench settles.
- [ ] **Verify the settings frame's integrity fix on-device.** The `SET1` v3 CRC32 bump has landed (decisions § 319): `WatchSettings::decode` rejects a frame whose checksum does not match, and the property in `core/tests/prop_settings.rs` that recorded the defect is un-ignored and passing on the host. What the host cannot show is the radio path. Pass criterion: a settings push whose bytes are deliberately corrupted in flight is rejected by the watch — no field applied, the previous config intact — while an untouched push still applies, and the fully-populated frame survives a real GATT write without truncation. **The frame is now v6** (decisions § 336 added five fields plus a 64-bit page mask at v4; § 352 the resting HR at v5; § 358 the ICE / medical-ID card at v6, spending `flags2`'s last bit) and a full push is **192 bytes**, not 49 — still one write at the 256-byte ATT MTU the `ble` task configures, so nothing chunks, but the size to confirm on the wire is the v6 one, and it is the first that leaves only ~64 bytes of MTU headroom. Cannot be sim-verified (no SoftDevice under Renode).
- [ ] **Exercise the WKT1 workout push end-to-end.** The structured-workout runner (decisions § 354) is host-tested and its engine + banners are sim-verified over the sim's demo workout, but the radio leg cannot be (no SoftDevice under Renode). Pass criterion: a chunked workout push over the real `workout` characteristic arms the Workout page and a bench jog walks its steps (auto-advance on both axes, `! REP` / `! STEP END` banners, the lap button skipping the active step); a deliberately corrupted chunk stream is rejected with the previously armed workout intact; and a manual pause verifiably freezes the step clock while a standing rest inside a timed recovery does not.
- [ ] **Confirm run-store v3 rejects a corrupted footer on real flash.** The blob CRC now covers the footer's totals as well as the track (§ 321), so bit-rot in `distance_m` / `moving_s` / `elapsed_s` can no longer sync a run with silently wrong numbers. Pass criterion: a committed blob whose summary bytes are deliberately disturbed on flash fails `recover_slot` at boot and is never advertised, and a phone handed the same bytes counts the pull failed rather than saving a run. Also confirm the compat decision on real hardware: a v1/v2 blob left in a slot from an earlier firmware is rejected by the version gate and its slot is reused, not read as corrupt.

## What tier 1 does not have to hit

This section exists so the checklist above cannot be misread as scope creep past [§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)'s owner-personal boundary, or as importing tier-2's targets.

**Stated plainly: [§ 82](../architecture/decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype)'s Definition of Done remains the Definition of Done. This checklist is how bench verification gets conducted and claimed — it is not a new gate on tier-1 completion.** One outdoor run that produces a GPS+HR-tagged track and syncs end-to-end completes tier 1, even with checklist items open. Open items become recorded findings and tier-2 inputs.

Tier 1 explicitly does **not** have to hit:

- **Any power or battery target.** § 83 is explicit: the PPK2 numbers inform tier-2 planning and do not gate tier-1 completion. § 82's "what this does not require" said the same. The ~110 h headline is a tier-2/3 *product* target from [`vision.md`](vision.md) req #1; the ≥ 8 h figure in the checklist is a DK-and-breakouts sanity check from `prototyping.md`, not a watch claim.
- **Tier 2's ≥ 24 hr GPS battery life** or **100 % outdoor fix reliability**. Those are the tier-2 wearable-prototype bars ([`prototyping.md`](prototyping.md#tier-2--wearable-prototype-15k40k-diy-80k250k-consultant-built-918-months), [`roadmap.md § Tier 2`](roadmap.md#tier-2--wearable-prototype-gated)) and tier 2 is gated on § 71's three triggers. Importing either into tier 1 would be exactly the goal-post drift § 82 was written to prevent.
- **Dual-band L1+L5 GNSS or foliage/canyon accuracy.** Tier 1 is single-band MAX-M10S by design; dual band is the Sony CXD5610 / u-blox X20P migration ([`vision.md`](vision.md) req #2).
- **In-case RF performance, an antenna design, or a chamber measurement.** Tier-2+ ([`prototyping.md`](prototyping.md#why-rf-is-the-line-item-that-surprises-everyone)).
- **IPX7, a sealed enclosure, case CAD, drop/vibe/thermal, or FCC/CE.** Tier-2/3 line items; the printed chassis is a board-holder, not a case.
- **Field validation under stress** — foliage, urban canyon, a multi-hour ultra, a 100 km event. § 82 puts all of that at tier 2+.
- **More than one qualifying run.** § 82 pins the bar at one deliberately; a second run is "reassuring, not decision-changing". The checklist's soak and boundary items are *characterisation*, not additional DoD runs.
- **A finished UI, data-screen customisation, OTA, vector maps, or ANT+.** Strict tier-1 scope is GPS + HR + display + sync (§ 82); § 84 and § 85 own OTA and maps at tier 2.
- **Kill criteria.** § 82 declined to set them and this doc does not add any. An owner-personal investigation ends when the owner stops investigating; a red checklist item is data, not a termination trigger.

## Pinning

- Decision recording this doc: [decisions.md § 314](../architecture/decisions.md).
- Definition of Done: [§ 82](../architecture/decisions.md#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype) (unchanged).
- Power methodology: [§ 83](../architecture/decisions.md#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem).
- BLE verification ceiling: [§ 210](../architecture/decisions.md#210-tier-1-ble-s140-softdevice-is-a-compile-verified-feature-gated-build--mutually-exclusive-with-the-sim-off-by-default).
- Evidence destinations: [`tier1_log.md`](tier1_log.md) (bench), `apps/custom_watch/sim/verification-<date>/` (sim), [`parts.md`](parts.md) (receipt).
