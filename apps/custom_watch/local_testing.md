# Local testing — custom_watch firmware

How to build, flash, test, and debug the watch firmware on a connected Nordic nRF52840 DK. Optimised for "plug in the board, type one command, see GPS fixes streaming in the terminal within 60 seconds."

## TL;DR — the four commands you'll actually run

Once parts have arrived and you've done the first-time setup below:

```
bin/watch-doctor.sh    # verify toolchain + board detection; run once per machine
bin/watch-flash.sh     # build + flash + stream defmt logs (the inner loop)
bin/watch-test.sh      # host-side unit tests, no board required
bin/watch-sim.sh       # boot the firmware on an emulated nRF52840 DK (Renode), no board required
```

No parts yet? `bin/watch-test.sh` and `bin/watch-sim.sh` work today with zero hardware — see [Simulating without a board](#simulating-without-a-board-renode).

All three are thin wrappers around `cargo` and `probe-rs`. If you prefer the unwrapped form, `cd apps/custom_watch && cargo run --release` is what `bin/watch-flash.sh` actually does — same outcome, more typing.

## What "testing" means on embedded vs web/mobile

The web stack tests one way: Vitest unit tests and Playwright e2e tests, both running in headless processes on your dev machine. The mobile stack tests two ways: Dart unit tests (host process) plus Flutter `integration_test` (real-or-emulated device).

Embedded firmware has a sharper split:

- **Host tests** run on your development machine via `cargo test`. They cover any logic that doesn't touch a peripheral — NMEA parsers, recording state machines, signal-processing helpers, anything in the `drivers/` crates that's pure data manipulation. These give you instant feedback (sub-second), run in CI without any hardware, and are the same workflow you already know from web/backend.
- **On-target tests** run on the actual nRF52840 DK. Anything that reads a sensor, drives the display, talks to the radio, or relies on hardware timers belongs here. They're slower (you have to flash the board before running) and require a board plugged in. They're the embedded equivalent of mobile e2e tests.
- **Simulator runs** sit between the two: `bin/watch-sim.sh` boots the real firmware ELF on an emulated nRF52840 DK (Renode) as an interactive bring-up and debugging surface for the peripheral-touching paths host tests can't reach; `sim/ci_smoke.py` drives the same launcher non-interactively and asserts on named observables, which is the tier CI runs. Both stop where Renode does — no BLE radio, no sensor analog, no power. See [Simulating without a board](#simulating-without-a-board-renode).

The line between the two is enforced architecturally: pure-logic crates in `apps/custom_watch/drivers/` build for the host (`x86_64-unknown-linux-gnu`) and `cargo test` normally. The `app/` and `boards/` crates build for `thumbv7em-none-eabihf` and need a board. Aim to keep 60–70% of firmware code host-testable — it's the single most effective lever for keeping the inner loop fast.

## Prerequisites (install once per dev machine)

[`bin/watch-doctor.sh`](../../bin/watch-doctor.sh) verifies each of these. Install + run the doctor, fix what it flags, re-run until green.

1. **Rust toolchain** — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` (or `dnf install rustup && rustup-init` on Fedora).
2. **The Cortex-M4F build target** — `rustup target add thumbv7em-none-eabihf`. This is what the nRF52840 actually runs.
3. **probe-rs** — `cargo install probe-rs-tools --locked`. Open-source replacement for Segger's J-Link tools. Includes `probe-rs run` (flash + run + stream logs) and `probe-rs attach` (stream logs from an already-running board). (The older `cargo install probe-rs --features cli` form still works, but `probe-rs-tools` is the current canonical name.)
4. **udev rules for USB access on Linux** — copy [the official probe-rs rules](https://probe.rs/docs/getting-started/probe-setup/#udev-rules) into `/etc/udev/rules.d/` and `sudo udevadm control --reload`. Without these, non-root users can't talk to the debug probe and `probe-rs list` will report nothing even when the board is plugged in.
5. **`cargo-watch` (optional but nice)** — `cargo install cargo-watch`. Lets you auto-reflash on file save with `cargo watch -x 'run --release'`.
6. **Renode + `defmt-print` (optional, for `bin/watch-sim.sh`)** — Renode installs machine-wide from the GitHub-releases rpm (`sudo dnf install -y ./renode-<version>-1.x86_64.rpm`; the workstation-level CLAUDE.md records the version pin + rationale); `defmt-print` decodes the sim's RTT byte stream: `cargo install defmt-print --locked`. Neither is checked by `bin/watch-doctor.sh` — `bin/watch-sim.sh` verifies both itself and says what's missing.

## First-time setup, after the workspace is scaffolded

If `apps/custom_watch/Cargo.toml` doesn't exist yet, see step 2 of [`README.md`](README.md) in this directory — the testing workflow below only becomes useful once that scaffold lands.

After scaffolding:

1. Plug the nRF52840 DK into a USB port using a **data cable** (not power-only). The onboard Segger J-Link enumerates as `/dev/ttyACM*` on Linux, `/dev/cu.usbmodem*` on macOS.
2. Run `bin/watch-doctor.sh` from the repo root. All five checks should pass and your board should appear in the "Connected debug probes" section.
3. Run `bin/watch-flash.sh`. You should see the user LED on the DK toggling within ~5 seconds, plus `defmt` log lines streaming in your terminal. Ctrl-C to exit; the board keeps running whatever was last flashed.

If step 3 hangs at "Flashing", unplug the board, wait 5 seconds, plug it back in, and retry. If `probe-rs list` shows nothing even after re-plugging, the udev rules from prerequisite #4 probably aren't installed.

## Day-to-day commands

All commands assume you're in `apps/custom_watch/` unless prefixed with `bin/`. The `bin/` wrappers all `cd` into the workspace internally and forward extra args through to the underlying tool. Each wrapper also has a root pnpm alias (`pnpm watch:doctor`, `pnpm watch:flash`, `pnpm watch:test`, `pnpm watch:sim`, ...) — same scripts, listed under the `//-- watch --` group in the root `package.json`.

| What | From the workspace | From the repo root | Hardware? |
|---|---|---|---|
| Verify toolchain + board detection | — | `bin/watch-doctor.sh` | Board if checking detection |
| Compile-check the whole workspace | `cargo build` | `bin/watch-build.sh` | No |
| Build a release binary | `cargo build --release` | `bin/watch-build.sh` | No |
| Run host-side unit tests | `cargo test` | `bin/watch-test.sh` | No |
| Boot the firmware on an emulated DK + stream defmt logs | — | `bin/watch-sim.sh` | No |
| Build + flash + stream logs (inner loop) | `cargo run --release` | `bin/watch-flash.sh` | Yes |
| Flash a specific binary | `cargo run --release --bin sensor_smoke` | `bin/watch-flash.sh --bin sensor_smoke` | Yes |
| Auto-reflash on file save | `cargo watch -x 'run --release'` | — | Yes |
| Stream logs without reflashing | `probe-rs attach --chip nRF52840_xxAA` | `bin/watch-logs.sh` | Yes |
| Erase the chip (factory reset) | `probe-rs erase --chip nRF52840_xxAA` | — | Yes |

You can also add Cargo aliases in `apps/custom_watch/.cargo/config.toml` to shorten the bare-cargo commands further — e.g. `cargo flash` as an alias for `cargo run --release` — once the workspace is scaffolded.

## Debugging firmware in real time

`defmt` is the logging crate. In firmware code, `defmt::info!("got fix: lat={} lon={}", lat, lon);` produces a structured log line that streams over RTT (Real-Time Transfer — Segger's debug-USB protocol) to your terminal during `cargo run` or `probe-rs attach`. Log levels are `trace`, `debug`, `info`, `warn`, `error`; the active level is set per build profile in `Cargo.toml` and can also be overridden at flash time via the `DEFMT_LOG` env var.

For full GDB-style debugging:

```
probe-rs run --chip nRF52840_xxAA target/thumbv7em-none-eabihf/release/app
```

In VS Code, the official [probe-rs debugger extension](https://probe.rs/docs/tools/debugger/) provides breakpoints, watch expressions, and a register view. The repo's root `.gitignore` excludes `.vscode/` so each developer keeps their own IDE config; bootstrap a working setup by saving the following to `apps/custom_watch/.vscode/launch.json`:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "probe-rs-debug",
            "request": "launch",
            "name": "Debug app (release)",
            "cwd": "${workspaceFolder}",
            "chip": "nRF52840_xxAA",
            "flashingConfig": {
                "flashingEnabled": true,
                "resetAfterFlashing": true,
                "haltAfterReset": true
            },
            "coreConfigs": [
                {
                    "coreIndex": 0,
                    "programBinary": "./target/thumbv7em-none-eabihf/release/app",
                    "rttEnabled": true,
                    "rttPollingInterval": 1
                }
            ],
            "preLaunchTask": "cargo build --release"
        }
    ]
}
```

…and pair it with a `tasks.json` for the build step:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "cargo build --release",
            "type": "shell",
            "command": "cargo build --release",
            "group": { "kind": "build", "isDefault": true },
            "problemMatcher": ["$rustc"]
        }
    ]
}
```

## Without a board

If the nRF52840 DK is plugged into your other laptop, in the post, or otherwise unavailable, you can still:

- Compile the whole workspace (`cargo build` or `bin/watch-build.sh`)
- Run host-side unit tests (`cargo test` or `bin/watch-test.sh`) — this includes the NMEA parser, recording state machine, and any pure-logic driver code
- Run lint + format (`cargo clippy --all-targets`, `cargo fmt --check`)
- Build the release binary for `thumbv7em-none-eabihf` and inspect the size (`cargo size --release --bin app`)

- Boot the whole firmware on an emulated nRF52840 DK (`bin/watch-sim.sh` — next section)

You **cannot**:

- Run `cargo run` (it requires a board to flash to)
- Test BLE (nrf-softdevice needs the real radio — Renode doesn't model it faithfully; the phone link's sim transport below is the stand-in). This includes the step-7 run-sync `run_manifest` / `run_chunk` GATT characteristics, which only exist on the `--features ble` build.
- Test the on-device flash run store against real NVMC. The store arms and a `runMacro $btn2` stop does commit a blob under Renode's NVMC model (see the Renode section), so the write path is exercised — but whether a real erase/write failure surfaces as an `Err` rather than a silent partial write is a bench item
- Test real sensor analog behaviour (the HR/baro breakouts have no Renode device models yet — the display does)
- Measure actual power consumption

## Simulating without a board (Renode)

`bin/watch-sim.sh` boots the firmware on [Renode](https://renode.io/)'s emulated nRF52840 DK — no board, no probe-rs. It builds the `thumbv7em-none-eabihf` release ELF that `watch-flash.sh` flashes with three sim-only Cargo features — `sim-autostart`, `sim-buttons`, and `sim-course` (see below), starts headless Renode with [`apps/custom_watch/sim/watch.resc`](sim/watch.resc), and streams decoded defmt logs to your terminal until Ctrl-C — same UX as `watch-flash.sh`. Rationale + design in [decisions.md § 208](../../docs/architecture/decisions.md#208-firmware-simulation-runs-the-unmodified-elf-on-renode-with-a-custom-defmt-rtt-drain).

**The `sim-autostart` feature.** Recording starts on **BTN1** on real hardware (see the `button` task; BTN2 stops). The `app` crate's default-OFF `sim-autostart` feature restores the old "start the run on the first GPS fix" path in the `record` task; `watch-sim.sh` builds with it so the sim records without needing a button. A hardware flash (default features) needs a real BTN1 press. Pass `--no-autostart` to drop the feature and boot to the idle face instead — needed to exercise anything that only exists *before* a run starts (the BTN3 GNSS-mode picker), with `runMacro $btn1` starting the run when you're ready.

**The `sim-buttons` feature — driving BTN1/BTN2/BTN3/BTN4 in the sim.** The hardware `button` task waits on `wait_for_falling_edge`, which the nRF52840 drives from the GPIO **SENSE/DETECT + PORT-event** mechanism — and Renode's nRF52840 GPIO model implements the pin-level IN register but *not* SENSE/DETECT, so that edge future never wakes under the sim (no amount of button/GPIO poking reaches it). The default-OFF `sim-buttons` feature (also built by `watch-sim.sh`) swaps the button task for a variant that **polls** the pin levels, which Renode can drive. Two ways to press a button:

1. **Click it in the `--gui` window.** The watch-screen window draws a BTN1–BTN4 bezel under the LCD; the display model implements Renode's `IAbsolutePositionPointerInput`, so the analyzer forwards mouse presses on those boxes to the same gpio0 pins the macros drive (mouse down = press, mouse up = release; the box inverts while held).
2. **From the monitor** — run `bin/watch-monitor.sh` in a second terminal (it finds the running sim's monitor port itself; the raw route is `ncat localhost <port>` with the port from the "Renode up" line). Note the monitor is a telnet socket, not a window: even under `--gui` there's no typeable window, and the defmt-log terminal is output-only — typing there does nothing:

```
runMacro $btn1    # start / pause / resume; dismiss a finished run home; grid: cursor back
runMacro $btn2    # stop the recording (commits the run to flash)
runMacro $btn3    # mid-run: cycle the run view (Dashboard -> Distance -> Pace ->
                  # Lap -> Zones -> Pacer -> Nav -> BackToStart); on the idle
                  # face: cycle the GNSS recording mode (Performance ->
                  # Balanced -> Expedition)
runMacro $btn3l   # hold BTN3 ~0.7 s — mid-run: page back; idle face: QNH re-zero
runMacro $btn3h   # hold BTN3 ~1.7 s — mid-run: open the page-grid overview
                  # (still the QNH re-zero on the idle face)
runMacro $btn4    # take a manual lap
```

Each macro pulls the button's input pin low via `gpio0 OnGPIO`, then releases it — ~0.3 s for a press, the `$btn3l` / `$btn3h` holds longer; a bare `btn3` does *not* run a macro, use `runMacro $btn3`. Watch the defmt stream for `button: BTN3 -> page Distance` etc., or dump the panel before/after (below) to see the page switch. To drive the grid: `runMacro $btn3h` opens it, each `runMacro $btn3` steps the cursor, and `runMacro $btn4` jumps — or wait ~3 s and it auto-selects the cursor. These two features plus `sim-course` (below) are the only places the sim ELF differs from the flashed one; the hardware build keeps the low-power SENSE button path.

**The `sim-course` feature — the canned breadcrumb course.** The Nav run-view page follows a course (`watch_core::course`), but no course-push path exists yet — so the default-OFF `sim-course` feature bakes in a canned one: the west + south edges of the `bench_jog.nmea` rectangle. The fixture's east + north legs deliberately leave it, so every ~2-minute lap exercises the whole surface — on-course following, `nav: OFF COURSE (41 m off, 179 m along)` (WARN, fires whatever page is up), and `nav: back on course` as the loop closes. Cycle BTN3 to the Nav page to watch the breadcrumb panel, the position marker, and the 2x OFF COURSE banner on the emulated screen. A hardware flash (default features) carries no course and the Nav page reports `NO COURSE LOADED`.

```
bin/watch-sim.sh                      # build + boot the default binary, headless
bin/watch-sim.sh --gui                # also open the live watch-screen window
bin/watch-sim.sh --bin sensor_smoke   # boot a specific binary
bin/watch-sim.sh --fixture mountain_loop  # a named fixture from sim/nmea/ (default: bench_jog)
bin/watch-sim.sh --nmea my_route.nmea # substitute the GPS fixture (full path)
bin/watch-sim.sh --phone-port 9900    # move the phone-link TCP port (default 7788)
bin/watch-sim.sh --no-autostart       # boot to the idle face; BTN1 starts the run
```

What runs for real in the sim, end to end: the Embassy executor and RTC1 time driver; GPIO (LED1 toggles logged at INFO as `gpio0.led0: LED1 on/off`); the GPS pipeline (canned NMEA → UARTE0 → `ublox_nmea` parser → `watch_core` fix accumulator); the Sharp MIP display (SPIM3 → the C# panel model — `--gui` shows the live screen, or dump a frame from the monitor: `sysbus.spi3.display DumpFrame "/tmp/frame.ppm"`); and the phone link (status frames on UARTE1 → TCP, the mobile app's dev Sim Watch screen connects here). What doesn't: BLE, power, and the HR/baro sensor analog side.

**The flash run store in the sim.** At boot you'll see `run_flash: NVMC present, run store armed at 0xfc000` — Renode *does* model the nRF52840 NVMC, so the store's controller probe passes and it arms. The store writes to flash on a run **stop**, which the sim can now trigger via `runMacro $btn2` (the `sim-buttons` feature) — the recorder reaches `Finished` and runs `commit`. Points stage in RAM as the run records; after the tier-1 253-point cap (~4 min at 1 Hz) you'll see a one-shot `record: run N hit tier-1 flash point cap` warning and further points stop staging while the recording totals keep accruing. On a board without an NVMC (or a Renode platform lacking one) the probe would instead log `run_flash: no NVMC controller (sim?) — run store disabled` and every store op no-ops; recording is unaffected either way (L4 best-effort). The `run_manifest` / `run_chunk` sync characteristics are `--features ble`-only and can't run in the sim at all (no SoftDevice).

Moving parts, all inside [`sim/`](sim/):

- **`watch.resc`** — the Renode script: loads the `nrf52840` CPU platform + the DK LEDs inline (the stock `nrf52840dk_nrf52840` board repl is *not* used — its non-inverted Button peripherals drive the pins low at reset, which the firmware's pulled-up inputs would read as "pressed"), declares SPIM3 with EasyDMA + the display model, loads the ELF, arms the defmt drain, logs LED1 state changes, defines the `btn1`/`btn2`/`btn3`/`btn4` injection macros, bridges the phone-link UART to TCP, exposes the GPS UART as a pty.
- **`defmt_rtt.py`** — gets defmt logs out. Renode's bundled `segger-rtt.py` hooks the SEGGER *C library's* function symbols, which the pure-Rust `defmt-rtt` crate doesn't have; this script instead polls the `_SEGGER_RTT` control block in emulated RAM, appends new bytes to a capture file, and advances the read offset. The wrapper tails that file through `defmt-print -e <elf>` for live decoded output.
- **`SharpMipDisplay.cs`** — a runtime-compiled Renode peripheral modelling the Sharp Memory LCD: decodes the exact line-update protocol `drivers/sharp_mip` encodes (CS-GPIO framing, 1-based line addresses, white-is-1 polarity) into a video framebuffer, plus a clickable BTN1–BTN4 bezel drawn under the LCD (the class is also the machine's `IAbsolutePositionPointerInput`, wired to gpio0 via its `buttonPort` constructor arg). `showAnalyzer sysbus.spi3.display` is the window `--gui` opens; `DumpFrame` writes a PPM of the LCD area only (no bezel) for headless checks.
- **`nmea/bench_jog.nmea`** — a synthetic ~2-minute rectangular jog loop (GGA+RMC pairs with valid checksums, 1 Hz fix rate like a real MAX-M10S). The wrapper loops it into the emulated `uart0` forever; the GPS task parses it into fixes that drive both the on-screen face and the phone-link frames, so the whole data path is exercised against a deterministic feed. This is the **default** fixture.
- **`nmea/mountain_loop.nmea`** — a synthetic ~13-minute mountain loop (~800 GGA+RMC pairs, same checksummed 1 Hz format) that climbs the East + North legs and descends the West + South legs of a rectangle, encoding **~200 m of cumulative vert gain and ~200 m of loss** over sustained 18–26 % grades before returning to the valley start. Where `bench_jog` is dead flat, this feed exercises the elevation / vert accumulator (`VERT +gain -loss` on the run dashboard; the idle face keeps its clock row once a fix arrives, per decisions §289) and drives the **grade-adjusted-pace path** hard — on the steep climb legs the Pace page's `GAP` row reads visibly faster than raw pace, and on the descents visibly slower. Satellite count also varies (11 in the valley, dropping to 7–8 near the summit with a correspondingly higher HDOP, re-emitted in periodic `$GPGSV` sets) so the fix-quality path sees movement too. Select it with `--fixture mountain_loop` (or `NMEA_FIXTURE=mountain_loop`). Note the canned `sim-course` breadcrumb is derived from the `bench_jog` rectangle, so the Nav page's off-course geometry only lines up under the default fixture.

The phone link mirrors the step-6 BLE design without the radio: the firmware's `phone` task writes one `watch_core::link` NDJSON status frame per second to UARTE1, Renode serves it as a TCP socket (`tcp://localhost:7788`; the Android emulator reaches it at `10.0.2.2:7788`), and the mobile app's dev-only **Settings → Developer → Sim watch link** screen (loopback-backend gate) renders the live values. `ncat localhost 7788` shows the raw frames.

Sim artifacts (Renode log, raw defmt capture) are kept in a `/tmp/watch-sim.XXXXXX` dir printed on exit. Each run picks a random monitor telnet port (recorded in the run dir's `monitor.port`, printed in the "Renode up" line) — `bin/watch-monitor.sh` attaches an interactive Renode monitor to the newest running sim to press buttons, poke registers, pause the machine, or dump display frames mid-run; `ncat localhost <port>` is the manual equivalent.

The pointer `watch-monitor.sh` follows is **per checkout**: `/tmp/watch-sim.latest-<checkout>-<hash>`, derived from the working tree's root (`watch_sim_latest_link` in `bin/lib/common.sh`, overridable with `WATCH_SIM_LATEST`). It used to be one shared `/tmp/watch-sim.latest`, which meant two concurrent sims — two git worktrees, two people, two agents — overwrote each other's pointer, and `watch-monitor.sh` would attach to the *wrong* Renode. A sim started from another worktree is deliberately unreachable by a bare `bin/watch-monitor.sh`; pass its port explicitly if you really want it.

Gotchas, learned the slow way:

- **`sim/defmt_rtt.py` must stay ASCII-only and Python-2 compatible.** Renode embeds IronPython 2: one em dash in a comment aborts the include (`Non-ASCII character '\xe2'`), and the failure is only visible on the monitor console, not in the Renode log. The wrapper guards this (pty-as-sentinel + a grep for "defmt-rtt drain active"), but if you edit the file, keep it plain ASCII.
- **The Renode monitor treats a closed stdin as `quit`.** So `echo 'sysbus.spi3.display DumpFrame "/tmp/f.ppm"' | ncat localhost <port>` runs the command *and then shuts the emulator down* — ncat closes stdin the moment the echo is consumed, and the run dies mid-scenario. Ctrl-D in an interactive `bin/watch-monitor.sh` does the same (Ctrl-C detaches cleanly; Ctrl-D does not). To script a single command, hold stdin open long enough for the reply: `{ echo '<cmd>'; sleep 2; } | ncat localhost <port>`.
- **Monitor errors never reach the Renode log file.** If `watch-sim.sh` dies with "Renode never created the GPS pty", re-run the include interactively to see the real error: `renode --console -e "include @apps/custom_watch/sim/watch.resc"`.
- **The UICR warning at boot is expected.** embassy-nrf checks the UICR region to configure the reset pin; Renode doesn't model UICR, the read returns zeros, and the firmware logs a WARN about not being able to reprogram it. Harmless in the sim; it does not appear on real hardware.
- **Sim uptime used to wrap to zero at virtual t = 512 s; `sim/watch.resc` fixes it, so don't boot the firmware on the stock platform.** RTC1 is a 24-bit counter at 32768 Hz (2^24 / 32768 = 512 s), and embassy-nrf extends it to a 64-bit monotonic `Instant` by counting half-periods off COMPARE[3] and the OVRFLW event. Stock Renode drops both: `nrf52840.repl` declares rtc1 with `numberOfEvents: 3` so the CC[3] write vanishes, and the model's OVRFLW is a log-only tagged flag that never fires. With neither firing, `Instant::now()` — and with it the defmt timestamps, GPS-fix freshness, and the recorder's clock — jumped back to ~0 after 512 virtual seconds, which reads like a reboot in the log (timestamps restart, but no boot banner, tasks keep running, state preserved) and quietly broke every uptime-keyed path. `sim/watch.resc` re-registers rtc1 as `sim/NRF52840_RTC_Overflow.cs` with `numberOfEvents: 4` — the upstream v1.16.1 model plus a real OVRFLW event — so a sim launched through `bin/watch-sim.sh` runs past 8.5 minutes with an honest clock (verified monotonic past 512 s and 1024 s in the 2026-07-19 pass, `sim/verification-2026-07-19/`). The trap that remains: `include @…/nrf52840.repl` by hand, or any scenario that skips `watch.resc`, gets the stock model and the wrap back.

## Building + flashing the BLE (SoftDevice) firmware

README step 6 (the real phone radio) lives behind the **`ble` Cargo feature** and is **not** part of the default or sim build — the Renode sim can't run it (the Nordic S140 SoftDevice is proprietary firmware Renode doesn't model), and CI never builds it. It is **compile-and-link-verified only**; nothing on this path has run on hardware yet.

Build it:

```
cargo build --release --no-default-features --features ble
```

`--no-default-features` is required: it drops the default `single-core-cs` feature so the SoftDevice owns `critical-section` instead of cortex-m (two impls is a link error). `build.rs` sees `CARGO_FEATURE_BLE` and swaps `memory.x` for `memory-ble.x`, linking the app above the SoftDevice's flash + RAM region. The default build's memory map is unchanged.

Flashing needs the SoftDevice programmed **once** alongside the app (the app expects it present at boot):

1. Download the S140 7.3.0 SoftDevice hex from Nordic (bundled in the nRF5 SDK / DK download).
2. `probe-rs download s140_nrf52_7.3.0_softdevice.hex --binary-format hex --chip nRF52840_xxAA`
3. Flash the app as usual (`bin/watch-flash.sh` / `cargo run --release --no-default-features --features ble`).

Bench-verification checklist (none of this is confirmed yet):

- **RAM origin.** `memory-ble.x` over-reserves 31 KiB of RAM. On boot the SoftDevice logs the actual required RAM start (`sd_ble_enable: app RAM start should be 0x200...`). Tune `RAM : ORIGIN` down to that; over-reserving only wastes RAM, it doesn't misbehave.
- **Interrupt priorities.** The SoftDevice reserves NVIC priorities 0/1/4; `main` puts GPIOTE, the RTC time driver, and every peripheral IRQ on P2. Confirm nothing faults or gets starved.
- **Advertising + notify.** Scan for "Threkir", connect, subscribe to the `d1f6a7e1-…` characteristic, and confirm one NDJSON status frame per second — the same bytes the UART/sim transport emits. The phone-side BLE decoder (flutter_blue_plus) is not built yet; the sim's TCP Sim Watch screen remains the read surface until it is.

## CI parity

The CI workflow at `.github/workflows/ci.yml` has a `build-firmware` job (per [decisions.md § 80](../../docs/architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)) that runs on every PR:

```
rustup show                                            # installs toolchain per rust-toolchain.toml
cargo build --release --target thumbv7em-none-eabihf
cargo test --target <HOST_TRIPLE> --workspace --exclude app --exclude nrf52840_dk
cargo clippy --workspace --release --target thumbv7em-none-eabihf -- -D warnings

# the two off-by-default feature sets, build + clippy each
cargo build  --release --target thumbv7em-none-eabihf -p app --no-default-features --features ble
cargo clippy --release --target thumbv7em-none-eabihf -p app --no-default-features --features ble -- -D warnings
cargo build  --release --target thumbv7em-none-eabihf -p app --features sim-autostart,sim-buttons,sim-course,dev-blink
cargo clippy --release --target thumbv7em-none-eabihf -p app --features sim-autostart,sim-buttons,sim-course,dev-blink -- -D warnings

cargo fmt --check
```

The `ble` and sim feature sets are gated because the default-only job let them rot: `ble` had already accumulated a dead-code warning (`FRAME_GAP` in the phone task, whose whole module is unreachable once the radio owns the link) that no default build could see, so the "compile-and-link-verified" claim behind the BLE run-sync vertical had nothing defending it. `ble` needs its own `--no-default-features` invocation — the S140 SoftDevice provides `critical-section`, so it is mutually exclusive with the default `single-core-cs`. The sim set is the one `bin/watch-sim.sh` builds, so a sim-only regression fails a PR instead of the next sim session.

All of those run on a stock Ubuntu CI runner with no hardware, with Cargo registry + `target/` cached across PRs via `actions/cache` keyed on the `Cargo.toml` + `rust-toolchain.toml` hashes (uncached cold builds are ~3-5 min; cached re-runs are seconds). On-target tests stay manual / local until tier 2+ where we'd connect a HIL (hardware-in-the-loop) rig to a self-hosted runner.

### The Renode sim in CI

`build-firmware` defends the **build-verified** rung of the four-rung verification contract in [decisions.md § 314](../../docs/architecture/decisions.md); two further jobs defend **sim-verified**. **`sim-firmware`** ("Simulate custom_watch firmware (Renode)") runs the `smoke` scenario and is **in the `CI gate` required-check list**, because that sequence has a manual verification pass behind it (`sim/verification-2026-07-19/`) and a long green history on hosted runners. **`sim-scenarios`** runs `pages` + `alerts` and is deliberately **not** required yet: they first executed 2026-07-26, and blocking every PR in the repo on two-run-old assertions is the risk worth avoiding. It is strict within itself, so a regression still fails loudly — it just does not gate. Fold it into `needs:` once it has run green over a stretch of unrelated PRs. It installs the pinned Renode portable build + `defmt-print`, builds the sim feature set, boots it under the emulator via the same `bin/watch-sim.sh` the manual sessions use, and asserts on decoded defmt output:

```
# on ubuntu-latest, timeout-minutes: 25
curl … renode-1.16.1.linux-portable-dotnet.tar.gz   # sha256-pinned
cargo install defmt-print --locked --version '^1.1' # cached between runs
DEFMT_LOG=debug cargo build --release --bin app \
  --features sim-autostart,sim-buttons,sim-course,dev-blink

# one step per scenario, each in its own out-dir; smoke gates, the other two do not
python3 …/ci_smoke.py --scenario smoke  --out-dir "$RUNNER_TEMP/watch-sim-ci/smoke"  --budget 300
python3 …/ci_smoke.py --scenario pages  --out-dir "$RUNNER_TEMP/watch-sim-ci/pages"  --budget 300
python3 …/ci_smoke.py --scenario alerts --out-dir "$RUNNER_TEMP/watch-sim-ci/alerts" --budget 300
```

Three steps rather than one `--scenario all` so a red step *names* the surface that broke without anyone opening a log — which matters more here than anywhere else in CI, because Renode is not installable on every contributor machine and CI is usually the only executor. Keeping `smoke` its own step is the load-bearing part of that split: a red `smoke` beside a green `pages` points at the pipeline, and the reverse points at the new scenario code. The cost is one emulator boot per step, which is what the budgets are sized against: 3 × 300 s = 15 min inside the 25 min cap, leaving ~10 min for the Renode fetch, the toolchain and a cold cargo build. The budget sits *below* the job timeout deliberately — overrunning it exits through the harness's own diagnostic dump, where the job timeout kills the runner bare. **A scenario added to the harness needs a step added to the workflow**; the `all` default is not what CI runs.

Each step writes into its own subdirectory of `$RUNNER_TEMP/watch-sim-ci`, so the single `if: failure()` upload still carries every scenario's evidence and no two scenarios overwrite each other's `sim-output.log` / `frame.ppm` / `renode.log`.

`sim/ci_smoke.py` is the harness — runnable locally too (it needs `renode` + `defmt-print` on PATH, so a Linux dev box, not a Mac). It drives `watch-sim.sh` and fails with a named expectation when an assertion's log line or artifact doesn't arrive.

The `smoke` scenario is the original seven-assertion sequence, and the one with a manual verification pass behind it ([`sim/verification-2026-07-19/`](sim/verification-2026-07-19/README.md)):

| Assertion | Log / artifact it waits on |
|---|---|
| flash run store arms at boot | `run_flash: run store armed at 0x…` |
| the canned NMEA parses into a fix with ≥ 4 satellites | `gps: fix lat=… sats=N` |
| that first fix starts a recording | `record: sim-autostart on first fix` |
| distance accumulates past 20 m | `record: recording dist=<m>` (DEBUG — hence `DEFMT_LOG=debug`) |
| the run face renders on the panel | monitor `DumpFrame` → a PPM with ≥ 200 dark **and** ≥ 200 light pixels (all-light = nothing drawn, all-dark = a broken decode) |
| two BTN2 presses stop the run and commit it | `button: BTN2 armed` then `run_flash: stored run N (M B) in slot S`, M > 0 |
| nothing panicked | no `panicked` line in the decoded stream |

Every wait is on a specific log line with a per-assertion deadline rather than a fixed sleep, and the fixture + sensor models are virtual-time driven with no randomness (see [`sim/verification-2026-07-19/README.md`](sim/verification-2026-07-19/README.md)), so the run replays identically. The one exception is the ~1.5 s gap between the two BTN2 presses, which has to land inside the firmware's 4 s stop-confirm window and so can't wait on the "armed" line; a missed injected press is retried up to three times. On failure the job uploads the decoded stream, `renode.log`, the raw defmt capture, the monitor transcript, and the panel dump as the `custom-watch-sim-logs` artifact.

### Scenarios — running one at a time

`--scenario` selects which sequence runs. Default `all`; the process exits non-zero if any selected scenario fails.

```
python3 apps/custom_watch/sim/ci_smoke.py                        # all of them
python3 apps/custom_watch/sim/ci_smoke.py --scenario smoke       # just the proven path
python3 apps/custom_watch/sim/ci_smoke.py --scenario pages
python3 apps/custom_watch/sim/ci_smoke.py --scenario alerts

# a named fixture from sim/nmea/, a moved out-dir, a tighter wall-clock cap
python3 apps/custom_watch/sim/ci_smoke.py --scenario pages \
  --fixture mountain_loop --out-dir /tmp/watch-pages --budget 300

python3 apps/custom_watch/sim/ci_smoke.py --scenario alerts --phone-port 9900
```

| Scenario | What it proves | What it still doesn't |
|---|---|---|
| `smoke` | The recording pipeline end to end: NMEA → parser → fix accumulator → recorder → distance, one run face on glass, and the two-press stop committing a CRC'd blob to a flash slot. | Nothing about the *other* 32 pages, and nothing about an alert firing. |
| `pages` | That the run-view page cycle actually renders — BTN3 walks the filtered mask and each page produces a non-blank frame instead of a blank or a panic. It is a **render** assertion, so it catches a page whose face code faults, divides by zero on empty data, or draws nothing; it does not check that a number is *right*. | Correctness of any displayed value (that's the host tests on `watch_core`), legibility, glyph shape at a given font tier, or one-handed press ergonomics. |
| `alerts` | That the alert path fires from real recorded state and reaches the panel — the `watch_core::alerts` engine's fuel / zone / pace reminders off the recorder's own event cadence, and the `nav` task's off-course latch and re-arm — as an inverse-video banner, without disturbing the recording underneath it (the L4 contract). | Whether a tired runner *notices* it. There is no vibration motor at tier 1, so an alert is display-only by construction and "unmissable" is a bench/wrist claim, never a sim one. |

`--budget` is a hard wall-clock cap for the run, not a per-assertion deadline (those are per-assertion and tighter). It exists so a wedged emulator fails with the harness's own diagnostics — last 40 lines of decoded output plus the tail of `renode.log` — rather than hanging until something outside kills it. Locally you can leave it at the default; in CI it is set per step, and always below the job's own `timeout-minutes`.

Use `--out-dir` when running more than one scenario by hand: each run clears `sim-output.log`, `frame.ppm` and the `watch-sim.latest` pointer in its out-dir first, so two scenarios sharing one out-dir destroy each other's evidence.

### What the sim cannot prove, in the four-rung vocabulary

The rungs are defined in [`docs/custom_watch/quality_standards.md`](../../docs/custom_watch/quality_standards.md). A green run of any scenario earns **sim-verified** for the observable it named, and that rung's ceiling is: *says nothing about real silicon, analog behaviour, the radio, or power*. Concretely, and none of this changes as scenarios are added:

- **BLE can never be sim-verified.** Renode does not model the S140 SoftDevice ([decisions.md § 210](../../docs/architecture/decisions.md)), so the whole radio path — RAM origin, interrupt priorities, connection interval, pairing/bonding, `run_manifest` / `run_chunk` / settings / course-push — jumps host/build-verified straight to bench-verified. There is no sim scenario that could cover it.
- **The sim models no power at all.** Renode does not simulate current, so a green run is **not a battery claim**. Every power and runtime figure in this workspace — the ~110 / ~180 / ~220 h GNSS-mode projections included — is a derivation awaiting a PPK2.
- **The sensor models are pinned to the drivers, not to silicon.** The MAX86177 and BMP581 models answer the register sequences the drivers issue, with a deterministic waveform and a scripted altitude. That verifies the *path*; a model built from the driver's beliefs cannot detect a wrong belief. No register semantics, no bus timing, no analog noise or settling.
- **No SAADC**, so the battery-gauge sampling path is unreachable; only "the task parks cleanly and the faces still render" is checkable.
- **No RF, no antenna, no thermal, no mechanical, no legibility.** A `pages` pass says a page drew pixels — not that a numeral is readable in direct sun at arm's length, which is a step-4 bench item.

A green `sim-firmware` means the firmware is self-consistent end to end under the emulator. The bench-verify list in [`sim/verification-2026-07-19/README.md`](sim/verification-2026-07-19/README.md) § Model limitations and the tier-1 checklist in `quality_standards.md` are untouched by it. Never write "verified" without the rung and the observable.

**Not in the `CI gate` aggregator yet.** The job is deliberately absent from `ci-gate`'s `needs:` list, so it reports but does not block merges. Promoting it is a follow-up once it has been observed green on a few real runs — Renode is not installable on every contributor machine, so its first hosted-runner execution is its first execution.

## Common errors

**"No debug probes found"** — the board isn't plugged in, the USB cable is power-only (try a different cable), udev rules aren't installed (Linux), or the J-Link firmware on the DK has wedged. For the last one, power-cycle the board while holding the reset button — that triggers the [J-Link On-Board recovery procedure](https://www.segger.com/products/debug-probes/j-link/).

**"target 'thumbv7em-none-eabihf' not found"** — `rustup target add thumbv7em-none-eabihf` not run yet. `bin/watch-doctor.sh` catches this.

**"Failed to attach to RTT"** — happens occasionally when reflashing while logs are streaming. Solution: `probe-rs reset --chip nRF52840_xxAA` and retry.

**Logs garbled or out of order** — RTT buffer overflowed because the firmware is logging faster than your USB can drain. Either reduce log frequency in firmware (`defmt::trace!` for high-rate events instead of `defmt::info!`) or drop the active log level via the `DEFMT_LOG` env var.

**`cargo run` hangs after "Flashing"** — usually a power issue with the DK. Unplug, wait 5 seconds, replug, retry. If persistent, check that the DK's `SW6` power switch is set to `VDD` and not `Source`.

**"Mass storage interface error"** — the J-Link mass-storage interface is enabled and conflicting with probe-rs. Disable it via the [J-Link Commander](https://www.segger.com/downloads/jlink/) command `MSDDisable`, then power-cycle the board. Persists across reboots once disabled.

**`cargo` complains about thumbv7em features it doesn't recognise** — your Rust toolchain is too old. `rustup update stable` and try again.

**`watch-sim.sh`: "defmt-print not on PATH"** — `cargo install defmt-print --locked`. It's a host-side cargo tool, so it rides `cargo install-update` afterwards.

**`watch-sim.sh`: "Renode never created the GPS pty" or "defmt-rtt drain did not arm"** — a monitor-level error aborted `sim/watch.resc`, and those errors don't reach the Renode log. Re-run the include under `renode --console` to see it (see § Simulating without a board). The commonest cause is a non-ASCII character introduced into `sim/defmt_rtt.py`.

**`watch-sim.sh`: Renode aborts with `AddressAlreadyInUse`** — a stale Renode instance is holding a port. The wrapper picks a random monitor port per run and kills its own instance via pid-file on exit, so this normally means a Renode from some other context is lingering: `pgrep -f '^dotnet /opt/renode'` and kill what you find. (Note when hunting: `pkill -f Renode.dll` matches *your own shell's* command line — anchor the pattern as above.)

**Successful flash but no LED blink, no defmt logs, or immediate chip reset.** Probable cause: the chip variant string in `apps/custom_watch/.cargo/config.toml` doesn't match the actual silicon on the DK. The scaffold uses `nRF52840_xxAA` (the standard variant in PCA10056); some boards or chip revisions ship as `nRF52840_xxAA-B` or other variants whose flash base addresses + ROM layouts differ slightly. probe-rs picks its flash algorithm from the chip string — a mismatch can "flash successfully" but the binary then references hardware that doesn't exist in that variant, causing immediate reset or silent no-op. **Diagnostic:** `probe-rs list` to see what probe-rs detects, `probe-rs chip list nRF52` to see known variants. **Fix:** update the `--chip` argument in the `.cargo/config.toml` runner line to match. `bin/watch-doctor.sh` prints the configured chip string on every run so you can spot a mismatch before it bites.
