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
- **HR paths** (zones with live BPM, duty-cycling, off-wrist, ambient) — no
  MAX86177 model; the Zones page's honest no-HR state is what the sim shows.
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
