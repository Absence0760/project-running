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

## Firmware bug found and fixed

**1 Hz GPS-dropout reacquire froze distance for the rest of the run.**
`watch_core::record` never ported `run_recorder`'s #330 re-anchor
(`_gpsReanchorAfterSeconds = 10`): at 1 Hz the fixed 100 m one-hop cap
rejected the post-gap reacquire fix, the anchor never rebased, and every
later delta only grew — observed in-sim as distance frozen from 559.6 s to
the end of the session. Fixed at the source (gap ≥ 10 s rebases the anchor
without crediting the un-sampled distance, 1 Hz path only — throttled modes
self-heal via their scaled ceiling and are untouched); locked with two host
regression tests; re-verified in-sim (freeze now lasts exactly the 40 s
void, `gps_dropout.log`).

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

## Not sim-verifiable (unchanged claims)

- **VertAccumulator / VERT row / complementary filter / QNH `SET <alt>` +
  `NO GPS FIX` banner variants** — the vert accumulator lives in the baro
  task and Renode has no BMP581 model; the sim's honest state is `NO BARO`
  and a `--` VERT row (both observed). Bench-gated.
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
