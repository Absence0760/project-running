# Renode sim verification pass — 2026-07-19

First sim pass since Renode landed on the workstation (v1.16.1 rpm,
dotnet-based; `defmt-print` 1.1.0). Everything below ran the release
thumbv7em ELF via `bin/watch-sim.sh` (headless, `DEFMT_LOG=debug`), buttons
injected through the monitor macros, panel state captured with
`sysbus.spi3.display DumpFrame`. Decoded-log excerpts live beside this file;
frame dumps are transcribed inline (PPMs are not committed).

## Verified

| Claim | Evidence |
|---|---|
| bench_jog end-to-end (no regression since 2026-07-08) | fixes parse + flow, distance accrues (422 m / 285 s and 157 m to a clean stop), run dashboard renders (hero clock, pace rows, honest `--` HR/VERT, `8 SATS PERF`) — `bench_jog.log` |
| Course follow + off-course alert + re-arm | `nav: OFF COURSE (41 m off, 179 m along)` each lap, `nav: back on course (0 m along)` at the next lap start |
| Fuel alerts on moving-time cadence | `record: alert Drink` / `Eat` on the sim 30/45 s cadence, 8 s TTL clears |
| BTN3 page cycle is 32 pages incl. PlanAdaptive, wraps to Dashboard | 33 presses walked every page (one press timed long → single page-back, exercising `Page::prev` mid-run) then `RaceDay → Dashboard` |
| BTN4 manual lap; BTN2 two-press stop guard | `button: Lap -> Lap`, `BTN2 armed — press again within 4s`, `BTN2 -> stop (confirmed)` |
| Flash run-store end-to-end commit (the step-7 "still owed" capture) | `run_flash: stored run 0 (500 B) in slot 0` on stop; boot scan `run store armed at 0xfc000` |
| mountain_loop: GAP on sustained 18–26 % grades | Pace page: raw AVG 16:34 /KM vs `GAP 2:48 /KM` (GPS-alt fed) |
| mountain_loop: elevation mini-profile accrues | ElevationProfile page renders two full 1600→1800→1600 cycles, hero 1744 |
| mountain_loop: varying GSV/GGA sat counts flow | sats=7..11 across 2 800 fixes — `mountain_loop.log` |
| Pacer finish-latch at goal distance | delta froze at −668 s crossing the 1 km demo goal |
| gps_dropout: honest idle staleness | `GPS STALE 6S`, position/alt rows hold last-known |
| gps_dropout: signal meter 0 bars on fix-type 0/1 despite sats in view | healthy 3/4 bars (GSA fix 3, 8 sats) → dropout 0/4 bars with GSV still showing 8 in view (fixture now carries GSA transitions + a mid-void GSV) |
| gps_dropout: recorder staleness + reacquire | run view mid-void: elapsed runs, auto-pause, `STALE 13S PERF`; distance frozen exactly for the void, resumes on reacquire — **after the #330 re-anchor fix below; the pre-fix firmware froze distance permanently** |
| Idle BTN3 short = GNSS mode cycle | Performance → Balanced → Expedition → Performance with interval + battery-est labels |
| Idle BTN3 long = QNH re-zero, honest refusal | `button: BTN3 long -> qnh re-zero requested` → 2x `NO BARO` banner (parked baro task answers) |
| Uptime-anchored paths past 512 s / 1024 s | 44-min continuous recording, monotonic timestamps, 3 125 m — after the sim RTC1 model fix below |

### Barometric path (added by the BMP581 model — `bmp581.log`)

| Claim | Evidence |
|---|---|
| The baro task runs instead of parking | `baro: BMP581 streaming`; chip-id probe, soft-reset and the OSR/IIR/ODR config sequence all answered |
| Scripted altitude round-trips through the firmware | model at 1600 m → `baro: alt=1599.9999m` (0.1 mm, same ISA constants both sides) |
| ELEVATION published every sample | 1 Hz `baro: alt=… gain=… loss=…` throughout every run |
| GPS-baro complementary filter / auto-QNH engages | pure baro `1599.9999` → `1624.18` on the seed sample, matching the fixture's GGA altitude 1624.0 |
| Face ALT row prefers barometric altitude | static 2400 m set while the fixture's GPS altitude is ~1700 m → ALT row reads `2324 M` (bias-corrected baro), not the fix |
| VERT +gain/-loss accrues on a climbing profile | mountain_loop + a 1600→1800 m triangle: `gain=133.8728m loss=20.082764m`, panel row `+133 -23 M` |
| Elevation mini-profile sparkline is baro-driven | ElevationProfile page renders a full-width climb, context row `ELEV D+61 D-0` |
| QNH re-zero `SET <alt>` (was bench-gated) | `baro: qnh re-zero -> Applied(1624.0)` → 2x `SET 1624M` banner **and** the ALT row snaps 1600 → 1624 M |
| QNH re-zero `NO GPS FIX` (was bench-gated) | same press inside the gps_dropout void → `qnh re-zero -> NoGps`, 2x `NO GPS FIX` banner over `GPS STALE 10S`, ALT unchanged |
| Phantom-vert moving gate banks nothing while stopped | idle recorder + 43 m of scripted climb → `gain=0.0m`; BTN1 starts the run and the next commit lands (`gain=3.0166016m`) |

## Firmware bugs found and fixed

**1. 1 Hz GPS-dropout reacquire froze distance for the rest of the run.**
`watch_core::record` never ported `run_recorder`'s #330 re-anchor
(`_gpsReanchorAfterSeconds = 10`): at 1 Hz the fixed 100 m one-hop cap
rejected the post-gap reacquire fix, the anchor never rebased, and every
later delta only grew — observed in-sim as distance frozen from 559.6 s to
the end of the session. Fixed at the source (gap ≥ 10 s rebases the anchor
without crediting the un-sampled distance, 1 Hz path only — throttled modes
self-heal via their scaled ceiling and are untouched); locked with two host
regression tests; re-verified in-sim (freeze now lasts exactly the 40 s
void, `gps_dropout.log`).

**2. Vert banked nothing on any real climb.** The baro task gated the vert
accumulator on `state == Recording`, but `RecordState::Paused` also covers a
fix whose displacement merely failed the point-acceptance min-move filter
(`TRACK_THRESHOLD_M`, 3 m) — a GPS sampling artifact, not a stop. A runner
power-hiking at 1–2 m/s covers under 3 m per 1 Hz fix, so the state alternates
fix by fix and every Paused sample re-based the deadband reference before the
pending gain could cross it: a climb slower than 3 m/s *vertical* — i.e. every
real climb — banked exactly zero. Invisible until a barometer existed in the
sim. Fixed at the source with the host-tested `Snapshot::is_moving()`, which
reads the receiver's own speed (stamped before the min-move filter can flip the
state, and zeroed by start/pause/stop), so a genuine stop still banks nothing.
Four host regression tests; the climb one fails "got 0" against the old gate.

**3. Every `+` on the panel rendered as a minus.** Read straight off the
emulated panel: the VERT row showed `-139 -17 M` for 139 m of ascent. The
format string is `+{gain} -{loss} M` — the generated font's `+` glyph was
byte-identical to `-`, because at the 8x16 cell size its vertical stem is under
one device pixel wide and its coverage falls below the threshold in every
column. Reproducible with and without antialiasing. `gen_font.py` now
supersamples any glyph that packs identically to a different glyph (2 glyphs
change; a whole-font supersample would have changed 89 of 95) and fails loudly
if a collision survives; two host tests pin the invariant. This also un-breaks
the Pacer page, where `+0:42` and `-0:42` were the same pixels.

## Sim-harness issues found and fixed

1. **Stock Renode froze `Instant` at 512 s** — `platforms/cpus/nrf52840.repl`
   declares rtc1 with 3 compare channels (real RTC1 has 4; embassy-nrf's
   time driver parks its half-period tick on CC[3]) and the model's OVRFLW
   event is an unimplemented tag. Both period-increment legs dead →
   `Instant::now()` wrapped every 2^24 ticks and froze the recorder 8.5 min
   in (every prior sim-verified run was shorter). Fixed with
   `sim/NRF52840_RTC_Overflow.cs` (upstream v1.16.1 model + real OVRFLW,
   phase-locked ascending LimitTimer) re-registered in `watch.resc` with
   4 channels. Verified monotonic past both 512 s and 1024 s.
2. **`gps_dropout.nmea` carried no GSA** — `FIX_QUALITY` was never published,
   so the honest signal meter read 0 bars even with a 3D fix and the
   "0 bars despite sats in view" claim was untestable. The fixture now
   carries GSA fix-type transitions (3 → 1 → 3) and a mid-void GSV.
3. **The stock `twi1` is the legacy TWI byte interface** — it maps none of the
   EasyDMA TWIM registers embassy-nrf's driver programs (ENABLE=6, TXD/RXD
   PTR+MAXCNT, the LASTTX/LASTRX shortcuts), so every I²C transaction hung
   with no STOPPED event and both sensor tasks' timeout-probes concluded the
   part was absent. `sim/NRF52840_TWIM.cs` is a real TWIM master (generic — it
   dispatches to whatever `II2CPeripheral` sits at the addressed slave);
   `sim/BMP581.cs` is the sensor behind it.
4. **Two monitor hazards, both of which killed a run mid-capture** — the
   Renode monitor treats a closed stdin as `quit`, so `echo cmd | ncat <port>`
   *ends the emulation*; and `/tmp/watch-sim.latest` is shared across
   concurrent sims, so a second sim silently repoints it. Drive one long-lived
   connection to your own instance's `monitor.port`.

## Not sim-verifiable (unchanged claims)

- **Real-analog barometer behaviour** — the BMP581 model serves a scripted
  altitude, so sensor noise, self-heating, IIR/OSR settling and the register
  map itself stay bench-gated. What the model proves is the *path*: driver
  sequence, task, accumulator, filter, face and banners (see the barometric
  table above). The one path still unverified is a `read_pressure_pa` that
  returns `Ok(None)` for a sustained stretch — the model's 50 Hz ODR always
  has a sample ready by the 1 Hz poll.
- ~~**HR paths**~~ — **now verified**, see the MAX86177 section below.
- **BLE / SoftDevice** (GATT link, run sync, settings/course push) — the
  SoftDevice cannot run under Renode; compile-only as before.
- Power draw, GNSS receiver power-down, real-analog GPS/HR behaviour.

## Reproduce

```
bin/watch-sim.sh                              # bench_jog, autostart
bin/watch-sim.sh --fixture mountain_loop      # vert/GAP terrain
bin/watch-sim.sh --fixture gps_dropout --no-autostart   # idle face first
bin/watch-monitor.sh                          # then: runMacro $btn1..$btn4
# long-press BTN3:  python "click(24, 1.5)"
# panel capture:    sysbus.spi3.display DumpFrame @/tmp/frame.ppm
```

---

# MAX86177 optical-HR model — HR path sim-verified

Second pass, same day. The sim gained a **MAX86177 model** (`sim/Max86177.cs`)
behind a new **nRF52840 TWIM master model** (`sim/NRF52840_TWIM.cs`), so the
optical-HR path above stops being bench-gated. Evidence:
[`max86177_hr.log`](max86177_hr.log) (decoded defmt + the model's own register
traffic) and [`max86177_panels.txt`](max86177_panels.txt) (panel captures
transcribed back through the `sharp_mip` font table).

## Why two models

Renode's stock platform declares `twi0` as `I2C.NRF52840_I2C`, which models
only the **legacy TWI** register interface. embassy-nrf's `Twim` driver
programs **TWIM**: `ENABLE=6`, EasyDMA `TXD/RXD PTR+MAXCNT+AMOUNT`, the
`LASTTX/LASTRX` SHORTS chain, completion via `EVENTS_STOPPED`. None of that
exists on the stock model, so every I2C transaction went nowhere and the hr
task's presence probe timed out — the sim genuinely had no I2C at all, not
just no sensor. `NRF52840_TWIM.cs` is a generic master (it dispatches to
whatever `II2CPeripheral` is registered at the addressed slave); an address
with nothing behind it raises ANACK, so an unpopulated bus still fails fast.

## Synthetic waveform + monitor knobs

Deterministic, derived from the sample index off a 100 Hz virtual-clock timer
— no wall-clock, no randomness:

```
MEAS1 = clamp19(DcBaseline*pa/64 + tri(n)*PulseAmplitude*pa/64 + AmbientLevel)
MEAS2 = clamp19(AmbientLevel)
```

`pa` is the live `LEDA_CURRENT` code, so the LED drive really moves the signal
and the firmware's AGC loop closes end to end. Ambient is **common-mode across
both slots**, which is what makes ambient subtraction exercisable, and
`clamp19` pins at the 19-bit full scale so pushing ambient at the rail clips
MEAS1 the way a real converter does. Knobs, settable live from the monitor:

```
sysbus.twi0.max86177 AmbientLevel 300000      # ambient bleed, both slots
sysbus.twi0.max86177 PulseAmplitude 0         # 0 = no pulse (off-wrist)
sysbus.twi0.max86177 DcBaseline 200           # reflected DC at drive 0x40
sysbus.twi0.max86177 PulsePeriodSamples 83    # BPM = 6000 / period
```

Defaults are a nominal worn wrist at ~72 BPM with the DC deliberately **below**
the AGC's target band, so the auto-gain visibly walks up and settles.

## Verified

| Claim | Evidence |
|---|---|
| HR reaches the face with a plausible BPM | `hr: bpm 70 → 71 → 72` by 16.7 s against the 72.3 BPM synthetic rate; dashboard HR row `72 BPM Z1` |
| Zone banking accrues during a recording | Zones page `Z1 0:18` banked (72 bpm is Z1 under the default 190 max-HR ladder), Z2–Z5 `0:00` |
| Duty-cycling really shuts the part down | `hr: window closed; sensor shut down until 60s` ↔ model-side `shut down — sampling stopped, FIFO frozen, registers retained` |
| …on the 15 s / 60 s Balanced cadence | window opens at exactly 60/120/180/240/300/360 s, closes at 75/135/195/255/315/375 s — six clean cycles |
| FIFO flush on wake | `FIFO flushed (0 word(s) dropped)` on every wake — 0 because shutdown genuinely stopped filling it, which is the point |
| Register retention across shutdown | after wake the part streams correctly-tagged MEAS1/MEAS2 again with **no re-init and no AGC re-walk** (drive stays at the settled `0x60`) |
| Detector resets per window, honest while re-converging | each wake logs `contact OffWrist` → `Worn` → `bpm 72` within ~3 s; nothing is published as valid before it re-converges |
| Staleness bounded and honest between windows | at uptime ~100 s the sensor is demonstrably shut down (closed at 75 s, reopens at 120 s) and the face still reads `72 BPM Z1` — the held value, age ~32 s inside the 60 s budget — then `75 BPM` once the window reopens |
| Ambient subtraction recovers a real BPM | ambient 0 → 300 000 (raw ≈ 435 k, sub-rail): brief drop-out then **`bpm 72` again at 75.6 s with the ambient still applied**; panel `72 BPM Z1` |
| Honest `Saturated` at the ADC rail | ambient → 520 000 pins raw at the 19-bit full scale: `hr: contact Saturated` + `no trusted pulse`, panel HR row `--`. **No fabricated reading** |
| AGC steps toward target and holds | `LED drive 0x40 → 0x48 → 0x50 → 0x58 → 0x60` then holds for the next 90 s (settled DC 135 k, inside the 130 k–300 k band) |
| AGC sheds drive as ambient approaches the raw ceiling | under the rail the drive walks `0x60 → 0x08` one step per second and **holds at `min_pa`** — the documented honest floor |
| …and recovers when ambient clears | ambient → 0 walks `0x08 → 0x60` back and `bpm 72` returns at 164 s |
| Off-wrist blanks honestly | pulse → 0 with DC out of band: `no trusted pulse` then `contact OffWrist`, panel HR row `--` |

## Firmware bug found and fixed

**The HR task republished an unchanged reading at 50 Hz, waking the whole UI.**
With a sensor actually present, the drain loop ran every 20 ms and
unconditionally `send`-ed an `HrSample` to `state::HR`. The screen task waits
on `HR.changed()`, so it woke and re-rendered 50 times a second forever,
whatever the pulse was doing — precisely the free-running waker README § Power
discipline rules out ("no gratuitous wakers"; "the screen task is event-driven
… the CPU sleeps seconds apart"). It was invisible until now because the sim
had no MAX86177 and the task parked.

Fixed at the source: publish only what carries new information
(`watch_core::hr_duty::should_publish`). `HrSample::at_s` is in whole seconds,
so a steady pulse still publishes once per second — `shown_bpm`'s hold budget
ages exactly as before — while a changed BPM (or losing the pulse) differs
immediately and is never delayed. Four host regression tests pin it, including
that suppressing a byte-identical resend provably cannot move `shown_bpm` for
any mode or observation time.

Measured effect in-sim: before the fix the emulated CPU was saturated by the
redundant wakes and the sim ran ~9× slower than real time (20 s of firmware
time in 170 s of host time); after it the same workload runs at ~1:1.

## Found here, fixed alongside — the `+` glyph

**The generated font rendered `+` identically to `-`.** Transcribing panel
captures against `drivers/sharp_mip/src/font.rs` showed `'+'` and `'-'` were
byte-identical (both a single `0x7E` row at y=8) — the `+` glyph's vertical
stroke fell under the rasteriser's coverage threshold at 8x16. `'='` and `'_'`
are fine, so it was one bad glyph, not a systemic threshold problem.
User-visible consequence: the **Pacer** page's whole purpose is a *signed*
delta (`+0:42` ahead vs `-1:05` behind) and the two rendered the same, and the
idle face's `VERT +gain -loss` row lost its sign too.

Found independently from both directions the same day — this HR pass (panel
transcription) and the BMP581 baro pass, whose `VERT` row read `-139 -17 M`
for 139 m of *ascent*. Fixed on the barometer branch: `gen_font.py` now
supersamples only the glyphs that collide with another glyph (two changed — a
whole-font supersample would have altered 89 of 95, an owner-visible UI
change) and the generator fails loudly if any collision survives
regeneration.

## Model limitations (bench-verify targets)

- **Register semantics are pinned to the driver, not to the datasheet.** The
  driver's register map is itself hand-rolled and flagged as a bench-verify
  target; the model matches the pinned init sequence host test. So this pass
  proves the firmware is **self-consistent** end to end — it cannot prove the
  addresses/encodings match real silicon.
- **Register retention across shutdown is honoured deliberately.** The
  firmware assumes SHDN keeps the register file (its duty-cycle wake never
  re-inits the MEAS2 block). The model implements that assumption, so the
  duty-cycle result above is conditional on it holding on real silicon —
  still a bench-verify item, now at least explicit and exercised.
- **No bus timing.** Transfers complete in zero virtual time inside the task
  register write; there is no per-byte I2C clocking, no FIFO almost-full
  interrupt (the firmware polls the counter), and no ADC conversion latency.
- **The waveform is a clean triangle, not a PPG.** No dicrotic notch, no
  motion artifact, no skin-tone/perfusion variation, no LED thermal drift. It
  exercises the *pipeline*, not the detector's real-world robustness.
- **Contact/AGC constants are unvalidated.** `CONTACT_DC_MIN/MAX`,
  `RAW_RAIL_DC` and the `AgcConfig` band are bench-verify values in the
  driver; the model's default DC/pulse levels were chosen to sit inside them,
  so the two are consistent by construction rather than by measurement.
- Still not sim-verifiable: real optical/analog behaviour, LED power draw, and
  anything needing the SoftDevice.

## Reproduce

```
bin/watch-sim.sh --phone-port 7796                     # HR streams immediately
bin/watch-sim.sh --no-autostart --phone-port 7796      # then BTN3 = Balanced, BTN1 = start
# in the monitor (bin/watch-monitor.sh):
sysbus.twi0.max86177 AmbientLevel 300000    # ambient subtraction still yields a BPM
sysbus.twi0.max86177 AmbientLevel 520000    # raw at the rail -> honest Saturated
sysbus.twi0.max86177 PulseAmplitude 0       # off-wrist -> honest blank
```
Barometer (all monitor commands; the sensor is `sysbus.twi1.bmp581`):

```
sysbus.twi1.bmp581 SetAltitudeMeters 1650                 # static altitude
sysbus.twi1.bmp581 StartTriangleProfile 1600 1800 417 660 # climb/descend, mm/s
sysbus.twi1.bmp581 StopProfile                            # freeze where it is
sysbus.twi1.bmp581 SetSeaLevelPa 101800                   # move the QNH reference
sysbus.twi1.bmp581 AltitudeMeters                         # inspect
```

The triangle profile is advanced by a 1 Hz timer on the machine's virtual-time
clock — no wall-clock, no randomness, so a given firmware + fixture + profile
replays identically. The `417/660 mm/s` rates above track `mountain_loop`'s own
GPS altitude ramp, so the GPS-baro complementary filter is exercised rather
than swamped by an artificial divergence.
