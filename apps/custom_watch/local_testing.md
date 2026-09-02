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

No parts yet? `bin/watch-test.sh`, `bin/watch-sim.sh` and `bin/watch-shots.sh` work today with zero hardware — see [Simulating without a board](#simulating-without-a-board-renode).

All four are thin wrappers around `cargo` and `probe-rs`. If you prefer the unwrapped form, `cd apps/custom_watch && cargo run --release` is what `bin/watch-flash.sh` actually does — same outcome, more typing.

## What "testing" means on embedded vs web/mobile

The web stack tests one way: Vitest unit tests and Playwright e2e tests, both running in headless processes on your dev machine. The mobile stack tests two ways: Dart unit tests (host process) plus Flutter `integration_test` (real-or-emulated device).

Embedded firmware has a sharper split:

- **Host tests** run on your development machine via `cargo test`. They cover any logic that doesn't touch a peripheral — NMEA parsers, recording state machines, signal-processing helpers, anything in the `drivers/` crates that's pure data manipulation. These give you instant feedback (sub-second), run in CI without any hardware, and are the same workflow you already know from web/backend.
- **On-target tests** run on the actual nRF52840 DK. Anything that reads a sensor, drives the display, talks to the radio, or relies on hardware timers belongs here. They're slower (you have to flash the board before running) and require a board plugged in. They're the embedded equivalent of mobile e2e tests.
- **Simulator runs** sit between the two: `bin/watch-sim.sh` boots the real firmware ELF on an emulated nRF52840 DK (Renode) as an interactive bring-up and debugging surface for the peripheral-touching paths host tests can't reach; `sim/ci_smoke.py` drives the same launcher non-interactively and asserts on named observables, which is the tier CI runs. Both stop where Renode does — no BLE radio, no sensor analog, no power. See [Simulating without a board](#simulating-without-a-board-renode).

The line between the two is enforced architecturally: the pure-logic crates — `core/` (`watch_core`), `render/` (`watch_render`) and the four crates under `apps/custom_watch/drivers/` — build for the host (`x86_64-unknown-linux-gnu`) and `cargo test` normally. Only the `app/` and `boards/` crates are target-bound; they build for `thumbv7em-none-eabihf` and need a board, which is exactly the `--exclude app --exclude nrf52840_dk` CI runs its test job with. Aim to keep 60–70% of firmware code host-testable — it's the single most effective lever for keeping the inner loop fast.

## Prerequisites (install once per dev machine)

[`bin/watch-doctor.sh`](../../bin/watch-doctor.sh) verifies each of these. Install + run the doctor, fix what it flags, re-run until green.

1. **Rust toolchain** — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` (or `dnf install rustup && rustup-init` on Fedora).
2. **The Cortex-M4F build target** — `rustup target add thumbv7em-none-eabihf`. This is what the nRF52840 actually runs.
3. **probe-rs** — `cargo install probe-rs-tools --locked`. Open-source replacement for Segger's J-Link tools. Includes `probe-rs run` (flash + run + stream logs) and `probe-rs attach` (stream logs from an already-running board). (The older `cargo install probe-rs --features cli` form still works, but `probe-rs-tools` is the current canonical name.)
4. **udev rules for USB access on Linux** — copy [the official probe-rs rules](https://probe.rs/docs/getting-started/probe-setup/#udev-rules) into `/etc/udev/rules.d/` and `sudo udevadm control --reload`. Without these, non-root users can't talk to the debug probe and `probe-rs list` will report nothing even when the board is plugged in.
5. **`cargo-watch` (optional but nice)** — `cargo install cargo-watch`. Lets you auto-reflash on file save with `cargo watch -x 'run --release'`.
6. **Renode + `defmt-print` (optional, for `bin/watch-sim.sh`)** — Renode installs machine-wide from the GitHub-releases rpm (`sudo dnf install -y ./renode-<version>-1.x86_64.rpm`; the workstation-level CLAUDE.md records the version pin + rationale); `defmt-print` decodes the sim's RTT byte stream: `cargo install defmt-print --locked`. Neither is checked by `bin/watch-doctor.sh` — `bin/watch-sim.sh` verifies both itself and says what's missing.

## First-time setup

The Cargo workspace at `apps/custom_watch/` landed 2026-05-28 (step 2 of [`README.md`](README.md) in this directory), so everything below runs against a real tree — only the on-board half waits on parts.

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
| Screenshot every screen the sim can arm (PNGs + an HTML contact sheet) | — | `bin/watch-shots.sh` | No |
| Build + flash + stream logs (inner loop) | `cargo run --release` | `bin/watch-flash.sh` | Yes |
| Flash a specific binary | `cargo run --release --bin app` | `bin/watch-flash.sh --bin app` | Yes |
| Auto-reflash on file save | `cargo watch -x 'run --release'` | — | Yes |
| Stream logs without reflashing | `probe-rs attach --chip nRF52840_xxAA` | `bin/watch-logs.sh` | Yes |
| Erase the chip (factory reset) | `probe-rs erase --chip nRF52840_xxAA` | — | Yes |

You can also add Cargo aliases in `apps/custom_watch/.cargo/config.toml` to shorten the bare-cargo commands further — e.g. `cargo flash` as an alias for `cargo run --release`.

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

`bin/watch-sim.sh` boots the firmware on [Renode](https://renode.io/)'s emulated nRF52840 DK — no board, no probe-rs. It builds the `thumbv7em-none-eabihf` release ELF that `watch-flash.sh` flashes with five sim-only Cargo features by default — `sim-autostart`, `sim-alerts`, `sim-buttons`, `sim-course`, `sim-workout` — plus `dev-blink`, and a sixth, `sim-screens`, only when `--screens` asks for it (see below), starts headless Renode with [`apps/custom_watch/sim/watch.resc`](sim/watch.resc), and streams decoded defmt logs to your terminal until Ctrl-C — same UX as `watch-flash.sh`. Rationale + design in [decisions.md § 208](../../docs/architecture/decisions.md#208-firmware-simulation-runs-the-unmodified-elf-on-renode-with-a-custom-defmt-rtt-drain).

**The `sim-autostart` feature.** Recording starts on **BTN1** on real hardware (see the `button` task; BTN2 stops). The `app` crate's default-OFF `sim-autostart` feature restores the old "start the run on the first GPS fix" path in the `record` task; `watch-sim.sh` builds with it so the sim records without needing a button. A hardware flash (default features) needs a real BTN1 press. Pass `--no-autostart` to drop the feature and boot to the idle face instead — needed to exercise anything that only exists *before* a run starts (the BTN3 GNSS-mode picker), with `runMacro $btn1` starting the run when you're ready.

**The `sim-buttons` feature — driving BTN1–BTN5 in the sim.** The hardware `button` task waits on `wait_for_falling_edge`, which the nRF52840 drives from the GPIO **SENSE/DETECT + PORT-event** mechanism — and Renode's nRF52840 GPIO model implements the pin-level IN register but *not* SENSE/DETECT, so that edge future never wakes under the sim (no amount of button/GPIO poking reaches it). The default-OFF `sim-buttons` feature (also built by `watch-sim.sh`) swaps the button task for a variant that **polls** the pin levels, which Renode can drive. Two ways to press a button:

1. **Click it in the `--gui` window.** On a Renode build that cannot start its own UI (the macOS arm64 build: renode/renode#886), `--gui` detects the failed launch and delivers the same thing another way — it relaunches headless and opens the `bin/watch-view.sh` live window automatically (see below). The watch-screen window renders a device — the panel at 3x inside a shaded case — with BTN1–BTN5 as clickable keys riding the case sides, each at the physical position its §350 function occupies on the §81 Garmin-Fenix layout — BTN1 upper-right (start/pause), BTN4 lower-right (page right), BTN2 mid-left (stop; the timer modal while idle, § 375), BTN3 lower-left (page left), BTN5 upper-left (lap; the settings menu while idle). The display model implements Renode's `IAbsolutePositionPointerInput`, so the analyzer forwards mouse presses on those boxes to the same gpio0 pins the macros drive (mouse down = press, mouse up = release; the box inverts while held).
2. **From the monitor** — run `bin/watch-monitor.sh` in a second terminal (it finds the running sim's monitor port itself; the raw route is `ncat localhost <port>` with the port from the "Renode up" line). Note the monitor is a telnet socket, not a window: even under `--gui` there's no typeable window, and the defmt-log terminal is output-only — typing there does nothing:

```
runMacro $btn1    # start / pause / resume; dismiss a finished run home; grid: confirm (GO)
runMacro $btn2    # stop the recording (press twice; commits the run to flash); grid: cancel
runMacro $btn3    # page LEFT in any run view (Dashboard <- Distance <- Pace <- ...);
                  # on the idle face: cycle the GNSS recording mode
                  # (Performance -> Balanced -> Expedition)
runMacro $btn4    # page RIGHT in any run view (Dashboard -> Distance -> Pace -> ...);
                  # on the idle face: walk the three idle faces one way
                  # (home -> diagnostics -> ICE -> home, §291 + §358)
runMacro $btn3h   # hold BTN3 ~0.8 s — run view: open the page-grid overview;
                  # idle face: QNH re-zero
runMacro $btn4h   # hold BTN4 ~0.8 s — the same grid open, right-hand key
runMacro $btn5    # take a manual lap; on the idle face: open the settings
                  # menu (§351 — $btn2/$btn3 cursor up/down, $btn5/$btn1
                  # edit left/right, $btn4 exit, 30 s inactivity auto-closes)
runMacro $btn5h   # hold BTN5 ~0.8 s — mark a waypoint at the recorder's
                  # current anchor (§357); refused outside a run
```

Each macro pulls the button's input pin low via `gpio0 OnGPIO`, then releases it — ~0.3 s for a press, the `$btn3h` / `$btn4h` holds longer; a bare `btn3` does *not* run a macro, use `runMacro $btn3`. Watch the defmt stream for `button: BTN4 -> page Distance` etc., or dump the panel before/after (below) to see the page switch. To drive the grid: `runMacro $btn3h` (or `$btn4h`) opens it, `runMacro $btn3` / `runMacro $btn4` step the cursor backward / forward, and `runMacro $btn1` jumps — or wait ~3 s and it auto-selects the cursor. These two features plus `sim-alerts`, `sim-course`, `sim-workout` (both below), `dev-blink`, and `sim-screens` under `--screens` are the only places the sim ELF differs from the flashed one; the hardware build keeps the low-power SENSE button path.

**The `sim-workout` feature — the canned demo workout.** The §354 structured-workout rail executes phone-pushed steps (`WKT1`, `ble`-only like the course push), so the default-ON-in-the-launcher `sim-workout` feature arms a canned 5-step plan over the same `state::WORKOUT` channel: warmup, 2 x (50 m rep / 30 s timed recovery), cooldown, short enough that bench_jog walks it in ~2 minutes with the `! REP 1/2` / `! STEP END` / `! WKT DONE` banners firing. Pass `--no-workout` to drop it — its step banners are unconditional alerts sharing the single banner slot, so a scenario that does not assert on the workout sheds it, the same way it sheds the course arms with `--no-course`. `ci_smoke.py` derives both from the scenario's declared rails rather than listing exclusions ([decisions.md § 465](../../docs/architecture/decisions.md)): the point is keeping ONE writer on the slot a scenario's assertions read, not finding a quiet window, which the engine now guarantees on its own. A hardware flash carries no workout until a real push and its Workout page reads `NOT SYNCED`.

**The `sim-course` feature — the canned breadcrumb course.** The Nav run-view page follows a course (`watch_core::course`). The real phone→watch push exists — the `CRS1` frame (`watch_core::course_store`, v3, CRC-sealed) over the chunked `course` GATT characteristic, encoded phone-side by `watch_course.dart` — but it is `ble`-only and so unreachable in the sim, so the default-OFF `sim-course` feature bakes in a canned one: the west + south edges of the `bench_jog.nmea` rectangle. The fixture's east + north legs deliberately leave it, so every ~2-minute lap exercises the whole surface — on-course following, `nav: OFF COURSE (41 m off, 179 m along)` (WARN, fires whatever page is up), and `nav: back on course` as the loop closes. Cycle BTN3 to the Nav page to watch the breadcrumb panel, the position marker, and the 2x OFF COURSE banner on the emulated screen. A hardware flash (default features) carries no course and the Nav page reports `NO COURSE LOADED`.

```
bin/watch-sim.sh                      # build + boot the default binary, headless
bin/watch-sim.sh --gui                # also open the live watch-screen window
bin/watch-sim.sh --bin app            # boot a named binary (`app` is the only one today)
bin/watch-sim.sh --fixture mountain_loop  # a named fixture from sim/nmea/ (default: bench_jog)
bin/watch-sim.sh --nmea my_route.nmea # substitute the GPS fixture (full path)
bin/watch-sim.sh --phone-port 9900    # move the phone-link TCP port (default 7788)
bin/watch-sim.sh --no-autostart       # boot to the idle face; BTN1 starts the run
bin/watch-sim.sh --no-alerts          # drop `sim-alerts` for a watch with no
                                      # banner over the hero rows (what the
                                      # screenshot walk boots with)
bin/watch-sim.sh --screens            # add `sim-screens`: three canned composed
                                      # data screens, one per layout (§364)
```

**The NMEA feed loops, and the loop point is not a no-op.** When the feeder reaches the end of the file it starts again from the top, which teleports the runner from the fixture's last position back to its first — metres for a loop fixture like bench_jog, ~354 m for `gps_dropout`. The recorder handles that correctly (a jump past `MAX_JUMP_M` at a one-fix interval is a teleport and credits nothing), but any *assertion* about distance that runs past the loop is reading a scenario the fixture does not describe: it is how a #330-broken recorder eventually resumes, once the runner has walked back inside the stale anchor's jump cap. `ci_smoke.py`'s `dropout` finds the restart in the published-fix stream and refuses to read past it.

There is deliberately **no flag to stop the feed after one pass.** One was built and removed: however the feed is stopped, the firmware stops receiving sentences that were written before it stopped, so the fixture silently loses its tail — `gps_dropout` delivered its clean opening leg and then nothing, and the void never ended. Holding the writing fd open past the last line did not change it. Whatever buffers between the feeder and the emulated UARTE only drains while the writer is still writing.

What runs for real in the sim, end to end: the Embassy executor and RTC1 time driver; GPIO (LED1 toggles logged at INFO as `gpio0.led0: LED1 on/off`); the GPS pipeline (canned NMEA → UARTE0 → `ublox_nmea` parser → `watch_core` fix accumulator); the Sharp MIP display (SPIM3 → the C# panel model — `--gui` shows the live screen, or dump a frame from the monitor: `sysbus.spi3.display DumpFrame "/tmp/frame.ppm"`); and the phone link (status frames on UARTE1 → TCP, the mobile app's dev Sim Watch screen connects here). What doesn't: BLE, power, and the HR/baro sensor analog side.

**The flash run store in the sim.** At boot you'll see `run_flash: run store armed at 0xfc000, N run(s) recovered (M interrupted)` — Renode *does* model the nRF52840 NVMC, so the store's controller probe passes and it arms. The store writes to flash on a run **stop**, which the sim can now trigger via `runMacro $btn2` (the `sim-buttons` feature) — the recorder reaches `Finished` and runs `commit`. Points stage in RAM as the run records; on reaching the tier-1 253-point cap (~4 min at 1 Hz) the writer **decimates rather than truncates** (run-store v2, §285) — you'll see `record: run N slot full — track thinned to 1/k resolution, whole run kept`, the stored points thin by 2, the incoming stream thins to match, and the wrist shows `! TRACK 1/k RES`. Recording never stops staging. On a board without an NVMC (or a Renode platform lacking one) the probe would instead log `run_flash: no NVMC controller (sim?) — run store disabled, recording unaffected` and every store op no-ops; recording is unaffected either way (L4 best-effort). The `run_manifest` / `run_chunk` sync characteristics are `--features ble`-only and can't run in the sim at all (no SoftDevice).

Moving parts, all inside [`sim/`](sim/):

- **`watch.resc`** — the Renode script: loads the `nrf52840` CPU platform + the DK LEDs inline (the stock `nrf52840dk_nrf52840` board repl is *not* used — its non-inverted Button peripherals drive the pins low at reset, which the firmware's pulled-up inputs would read as "pressed"), declares SPIM3 with EasyDMA + the display model, loads the ELF, arms the defmt drain, logs LED1 state changes, defines the eight button-injection macros (`btn1`..`btn5` plus the `btn3h` / `btn4h` / `btn5h` holds), bridges the phone-link UART to TCP with `flushOnConnect` so a client attaching mid-run gets the present rather than the boot, exposes the GPS UART as a pty.
- **`defmt_rtt.py`** — gets defmt logs out. Renode's bundled `segger-rtt.py` hooks the SEGGER *C library's* function symbols, which the pure-Rust `defmt-rtt` crate doesn't have; this script instead polls the `_SEGGER_RTT` control block in emulated RAM, appends new bytes to a capture file, and advances the read offset. The wrapper tails that file through `defmt-print -e <elf>` for live decoded output.
- **`SharpMipDisplay.cs`** — a runtime-compiled Renode peripheral modelling the Sharp Memory LCD: decodes the exact line-update protocol `drivers/sharp_mip` encodes (CS-GPIO framing, 1-based line addresses, white-is-1 polarity) into a video framebuffer drawn at 3x inside a shaded watch shell (case, bezel ring, recessed glass), plus clickable BTN1–BTN5 keys riding the case sides at their §81 Fenix-analog positions and labelled with their §350 functions (the class is also the machine's `IAbsolutePositionPointerInput`, wired to gpio0 via its `buttonPort` constructor arg). `showAnalyzer sysbus.spi3.display` is the window `--gui` opens. Two dumps, and they are different artifacts: **`DumpFrame`** writes a PPM of the LCD area only (no case), flat black/white — its bytes are what every assertion reads, so they don't move — while **`DumpCanvas`** writes the whole window including the case and keys, in the canvas palette, and asserts nothing (it exists so the shell's own look can be reviewed without a display attached). Per decisions §360.
- **`nmea/bench_jog.nmea`** — a synthetic ~2-minute rectangular jog loop (GGA+RMC pairs with valid checksums, 1 Hz fix rate like a real MAX-M10S). The wrapper loops it into the emulated `uart0` forever; the GPS task parses it into fixes that drive both the on-screen face and the phone-link frames, so the whole data path is exercised against a deterministic feed. This is the **default** fixture.
- **`nmea/mountain_loop.nmea`** — a synthetic ~13-minute mountain loop (~800 GGA+RMC pairs, same checksummed 1 Hz format) that climbs the East + North legs and descends the West + South legs of a rectangle, encoding **~200 m of cumulative vert gain and ~200 m of loss** over sustained 18–26 % grades before returning to the valley start. Where `bench_jog` is dead flat, this feed exercises the elevation / vert accumulator (`VERT +gain -loss` on the run dashboard; the idle face keeps its clock row once a fix arrives, per decisions §289) and drives the **grade-adjusted-pace path** hard — on the steep climb legs the Pace page's `GAP` row reads visibly faster than raw pace, and on the descents visibly slower. Satellite count also varies (11 in the valley, dropping to 7–8 near the summit with a correspondingly higher HDOP, re-emitted in periodic `$GPGSV` sets) so the fix-quality path sees movement too. Select it with `--fixture mountain_loop` (or `NMEA_FIXTURE=mountain_loop`). Note the canned `sim-course` breadcrumb is derived from the `bench_jog` rectangle, so the Nav page's off-course geometry only lines up under the default fixture.
- **`nmea/gps_dropout.nmea`** — a ~2-minute jog with a 40 s signal void in the middle (void RMC + fix-quality-0 GGA, with GSA fix-type 3→1→3 transitions and a mid-void GSV so the honest signal meter is exercisable) and a plausible reacquire 122 m downrange. It caught the un-ported `run_recorder` #330 gap re-anchor by hand in the 2026-07-19 pass and now backs `ci_smoke.py`'s `dropout` scenario. Select it with `--fixture gps_dropout`.
- **`nmea/heat_flat.nmea`** and **`nmea/switchback_descent.nmea`** — two more ~10-minute terrain fixtures, selectable the same way: `heat_flat` holds a dead-flat 305 m for its whole length (the no-vert control against which the climbing fixtures are read), `switchback_descent` drops 2400 m → 2099 m through switchbacks (the descent counterpart to `mountain_loop`'s climb, and the case where a bearing swings hardest between fixes). Neither backs a `ci_smoke` scenario today.

The phone link mirrors the step-6 BLE design without the radio: the firmware's `phone` task writes one `watch_core::link` NDJSON status frame per second to UARTE1, Renode serves it as a TCP socket (`tcp://localhost:7788`; the Android emulator reaches it at `10.0.2.2:7788`), and the mobile app's dev-only **Settings → Developer → Sim watch link** screen (loopback-backend gate) renders the live values. `ncat localhost 7788` shows the raw frames.

Sim artifacts (Renode log, raw defmt capture) are kept in a `/tmp/watch-sim.XXXXXX` dir printed on exit. Each run picks a random monitor telnet port (recorded in the run dir's `monitor.port`, printed in the "Renode up" line) — `bin/watch-monitor.sh` attaches an interactive Renode monitor to the newest running sim to press buttons, poke registers, pause the machine, or dump display frames mid-run; `ncat localhost <port>` is the manual equivalent.

The pointer `watch-monitor.sh` follows is **per checkout**: `/tmp/watch-sim.latest-<checkout>-<hash>`, derived from the working tree's root (`watch_sim_latest_link` in `bin/lib/common.sh`, overridable with `WATCH_SIM_LATEST`). It used to be one shared `/tmp/watch-sim.latest`, which meant two concurrent sims — two git worktrees, two people, two agents — overwrote each other's pointer, and `watch-monitor.sh` would attach to the *wrong* Renode. A sim started from another worktree is deliberately unreachable by a bare `bin/watch-monitor.sh`; pass its port explicitly if you really want it.

Gotchas, learned the slow way:

- **`sim/defmt_rtt.py` must stay ASCII-only and Python-2 compatible.** Renode embeds IronPython 2: one em dash in a comment aborts the include (`Non-ASCII character '\xe2'`), and the failure is only visible on the monitor console, not in the Renode log. The wrapper guards this (pty-as-sentinel + a grep for "defmt-rtt drain active"), but if you edit the file, keep it plain ASCII.
- **The Renode monitor treats a closed stdin as `quit`.** So `echo 'sysbus.spi3.display DumpFrame "/tmp/f.ppm"' | ncat localhost <port>` runs the command *and then shuts the emulator down* — ncat closes stdin the moment the echo is consumed, and the run dies mid-scenario. Ctrl-D in an interactive `bin/watch-monitor.sh` does the same (Ctrl-C detaches cleanly; Ctrl-D does not). To script a single command, hold stdin open long enough for the reply: `{ echo '<cmd>'; sleep 2; } | ncat localhost <port>`.
- **Monitor errors never reach the Renode log file, so `watch.resc` writes stage markers instead.** The include logs `watch.resc stage: <name>` after each of its risky steps (platform + ELF, phone-link socket, GPS pty, machine start), and a boot that never produces the pty reports the last one it reached — the step AFTER that marker is the one that died. That names the step; it still does not print the error, so to read the error itself re-run the include interactively: `renode --console -e "include @apps/custom_watch/sim/watch.resc"`.
- **The UICR warning at boot is expected.** embassy-nrf checks the UICR region to configure the reset pin; Renode doesn't model UICR, the read returns zeros, and the firmware logs a WARN about not being able to reprogram it. Harmless in the sim; it does not appear on real hardware.
- **Sim uptime used to wrap to zero at virtual t = 512 s; `sim/watch.resc` fixes it, so don't boot the firmware on the stock platform.** RTC1 is a 24-bit counter at 32768 Hz (2^24 / 32768 = 512 s), and embassy-nrf extends it to a 64-bit monotonic `Instant` by counting half-periods off COMPARE[3] and the OVRFLW event. Stock Renode drops both: `nrf52840.repl` declares rtc1 with `numberOfEvents: 3` so the CC[3] write vanishes, and the model's OVRFLW is a log-only tagged flag that never fires. With neither firing, `Instant::now()` — and with it the defmt timestamps, GPS-fix freshness, and the recorder's clock — jumped back to ~0 after 512 virtual seconds, which reads like a reboot in the log (timestamps restart, but no boot banner, tasks keep running, state preserved) and quietly broke every uptime-keyed path. `sim/watch.resc` re-registers rtc1 as `sim/NRF52840_RTC_Overflow.cs` with `numberOfEvents: 4` — the upstream v1.16.1 model plus a real OVRFLW event — so a sim launched through `bin/watch-sim.sh` runs past 8.5 minutes with an honest clock (verified monotonic past 512 s and 1024 s in the 2026-07-19 pass, `sim/verification-2026-07-19/`). The trap that remains: `include @…/nrf52840.repl` by hand, or any scenario that skips `watch.resc`, gets the stock model and the wrap back.
- **`ppi: Failed to register PPI from 0x…` in `renode.log` means a peripheral the stock platform declares cannot be a PPI event source, and the chain silently never fires.** Renode's `NRF52840_PPI` resolves an event endpoint by asking the bus which peripheral owns the address written to EVENTP[n] and casting it to `INRFEventProvider`; a peripheral that does not implement it is refused with that one error line and nothing else complains ever again. Renode 1.16.1's `NRF52840_UART` is such a peripheral, which silently disabled both UARTE-sourced chains the firmware builds: UARTE1's `split_with_idle` byte counter (which is why the software gap timeout was carrying the settings pipe alone) and UARTE0's `BufferedUarte` RX ring, whose write index *is* a TIMER byte count — with the count frozen at 0, not one NMEA byte is ever delivered and the symptom is "no fix", indistinguishable from a broken fixture. `sim/watch.resc` re-registers both instances as `sim/NRF52840_UARTE_Events.cs` (decisions.md § 698). The trap that remains is the same as rtc1's: any scenario that skips `watch.resc` gets the stock model back. **When you next touch a PPI chain, grep the run's `renode.log` for `Failed to register` before believing a green scenario.**
- **A boot that dies before the first log line with `PC = 0x1a000` is the RTC start race, not your code.** `sim/NRF52840_RTC_Overflow.cs` syncs the CPU's executed-but-unreported time into the clock source before TASKS_START / STOP / CLEAR / TRIGOVRFLW touch the timers. Without that, Renode credits the freshly-started RTC with the whole part of the CPU's quantum that ran *before* the guest started it (measured: 65.33 us, two 32768 Hz ticks), and embassy-nrf's `RtcDriver::init` — `tasks_clear; tasks_start; while counter != 0 {}` — then waits for the 24-bit counter to wrap, 512 s, i.e. forever as far as any scenario budget is concerned. The tell is a `WEDGED GUEST` report whose firmware clock never left `0.000000`, whose last decoded line is embassy-nrf's UICR reset-pin warning, and whose PC symbolises to the embassy main task (`embassy_nrf::init` is inlined, so the symbol names the caller — disassemble the PC to see the COUNTER read). It is deterministic per *binary*, not per host: a build that reaches RTC init a few hundred instructions earlier or later flips it, which is how it passed locally for a week while failing every CI run (issue #788, decisions.md § 666).

## Building + flashing the BLE (SoftDevice) firmware

README step 6 (the real phone radio) lives behind the **`ble` Cargo feature** and is **not** part of the default or sim build — the Renode sim can't run it (the Nordic S140 SoftDevice is proprietary firmware Renode doesn't model). CI *does* build it — the `build-firmware` job has built and clippy-gated the `ble` feature set per PR since 2026-07-25 (see [CI parity](#ci-parity)) — so it is **build-verified**, not merely compilable-in-principle; nothing on this path has run on hardware yet.

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
- **Advertising + notify.** Scan for "Threkir", connect, subscribe to the `d1f6a7e1-…` characteristic, and confirm one NDJSON status frame per second — the same bytes the UART/sim transport emits. The phone-side BLE transport **is** built — `ReactiveBleWatchTransport` in `apps/mobile_android/lib/sim_watch_sync.dart`, over `flutter_reactive_ble` (chosen over `flutter_blue_plus`, decisions §212), unit-tested behind an injectable seam with no radio. What is unconfirmed is that it talks to a real S140, so the sim's TCP Sim Watch screen remains the read surface until a board exists.

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
cargo build  --release --target thumbv7em-none-eabihf -p app --features sim-autostart,sim-alerts,sim-buttons,sim-course,sim-workout,dev-blink
cargo clippy --release --target thumbv7em-none-eabihf -p app --features sim-autostart,sim-alerts,sim-buttons,sim-course,sim-workout,dev-blink -- -D warnings

cargo fmt --check
```

The `ble` and sim feature sets are gated because the default-only job let them rot: `ble` had already accumulated a dead-code warning (`FRAME_GAP` in the phone task, whose whole module is unreachable once the radio owns the link) that no default build could see, so the "compile-and-link-verified" claim behind the BLE run-sync vertical had nothing defending it. `ble` needs its own `--no-default-features` invocation — the S140 SoftDevice provides `critical-section`, so it is mutually exclusive with the default `single-core-cs`. The sim set is the one `bin/watch-sim.sh` builds, so a sim-only regression fails a PR instead of the next sim session.

All of those run on a stock Ubuntu CI runner with no hardware, with Cargo registry + `target/` cached across PRs via `actions/cache` keyed on the `Cargo.toml` + `rust-toolchain.toml` hashes (uncached cold builds are ~3-5 min; cached re-runs are seconds). On-target tests stay manual / local until tier 2+ where we'd connect a HIL (hardware-in-the-loop) rig to a self-hosted runner.

### The GATT table across languages

A second, toolchain-free job — **`watch-ble-uuids`** ("Watch ↔ phone GATT UUID drift"), also in the `CI gate` required-check list — runs `node scripts/check_watch_ble_uuids.mjs` plus that script's own `node --test` suite. It parses the `#[characteristic(uuid = …)]` rows out of `app/src/tasks/ble.rs` and the `Uuid.parse` constants out of `apps/mobile_android/lib/reactive_ble_watch_transport.dart` and fails on disagreement, per [decisions.md § 416](../../docs/architecture/decisions.md). Only the Android copy is read; the iOS twin is byte-identical by the `twin-parity` job ([§ 39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)). This is the one firmware path CI can defend *no other way*: the radio needs the S140, which Renode does not model, so a shifted characteristic ([§ 410](../../docs/architecture/decisions.md) — watch→phone run sync could not have worked at all) is invisible to every build and every sim until a board exists.

### The Renode sim in CI

`build-firmware` defends the **build-verified** rung of the four-rung verification contract in [decisions.md § 314](../../docs/architecture/decisions.md); two further jobs defend **sim-verified**. **`sim-firmware`** ("Simulate custom_watch firmware (Renode)") runs the `smoke` scenario and is **in the `CI gate` required-check list**, because that sequence has a manual verification pass behind it (`sim/verification-2026-07-19/`) and a long green history on hosted runners. **`sim-scenarios`** runs `pages` + `alerts` + `terrain` + `dropout` + `screens` + `idle` + `workout`. It was held out of the gate while its assertions were new — they first executed 2026-07-26, and blocking every PR in the repo on two-run-old assertions is the risk worth avoiding — and was folded into `ci-gate`'s `needs:` on 2026-07-27 once the soak had done its job (it caught the alerts scenario racing the panel repaint on both halves of its banner/quiet pair). Both jobs gate today. It installs the pinned Renode portable build + `defmt-print`, builds the sim feature set, boots it under the emulator via the same `bin/watch-sim.sh` the manual sessions use, and asserts on decoded defmt output:

```
# sim-firmware on ubuntu-latest, timeout-minutes: 25
# sim-scenarios on ubuntu-latest, timeout-minutes: 50
curl … renode-1.16.1.linux-portable-dotnet.tar.gz   # sha256-pinned
cargo install defmt-print --locked --version '^1.1' # cached between runs
DEFMT_LOG=debug cargo build --release --bin app \
  --features sim-autostart,sim-alerts,sim-buttons,sim-course,sim-workout,dev-blink

# one step per scenario, each in its own out-dir
python3 …/ci_smoke.py --scenario smoke   --out-dir "$RUNNER_TEMP/watch-sim-ci/smoke"   --budget 300
python3 …/ci_smoke.py --scenario pages   --out-dir "$RUNNER_TEMP/watch-sim-ci/pages"   --budget 300
python3 …/ci_smoke.py --scenario alerts  --out-dir "$RUNNER_TEMP/watch-sim-ci/alerts"  --budget 300
python3 …/ci_smoke.py --scenario terrain --out-dir "$RUNNER_TEMP/watch-sim-ci/terrain" --budget 300
python3 …/ci_smoke.py --scenario dropout --out-dir "$RUNNER_TEMP/watch-sim-ci/dropout" --budget 420
python3 …/ci_smoke.py --scenario screens --out-dir "$RUNNER_TEMP/watch-sim-ci/screens" --budget 300
python3 …/ci_smoke.py --scenario idle    --out-dir "$RUNNER_TEMP/watch-sim-ci/idle"    --budget 300
python3 …/ci_smoke.py --scenario workout --out-dir "$RUNNER_TEMP/watch-sim-ci/workout" --budget 300
```

One step per scenario rather than one `--scenario all` so a red step *names* the surface that broke without anyone opening a log — which matters more here than anywhere else in CI, because Renode is not installable on every contributor machine and CI is usually the only executor. Keeping `smoke` its own job is the load-bearing part of that split: a red `smoke` beside a green `pages` points at the pipeline, and the reverse points at the new scenario code. The cost is one emulator boot per step, which is what the budgets are sized against: `sim-scenarios`' seven sum to 37 min inside its 50 min cap, leaving ~10 min for the Renode fetch, the toolchain and a cold cargo build. `dropout` carries the larger budget because it has to run the fixture's clean leg, its whole 40 s void, and into the reacquire — ~200 s of wall clock — before it can assert anything. The budget sits *below* the job timeout deliberately — overrunning it exits through the harness's own diagnostic dump, where the job timeout kills the runner bare. **A scenario added to the harness needs a step added to the workflow**; the `all` default is not what CI runs.

Each step writes into its own subdirectory of `$RUNNER_TEMP/watch-sim-ci`, so the single `if: failure()` upload still carries every scenario's evidence and no two scenarios overwrite each other's `sim-output.log` / `frame.ppm` / `renode.log`.

`sim/ci_smoke.py` is the harness — runnable locally too (it needs `renode` + `defmt-print` on PATH, so a Linux dev box, not a Mac). It drives `watch-sim.sh` and fails with a named expectation when an assertion's log line or artifact doesn't arrive.

The `smoke` scenario is the end-to-end sequence, and the one with a manual verification pass behind it ([`sim/verification-2026-07-19/`](sim/verification-2026-07-19/README.md)):

| Assertion | Log / artifact it waits on |
|---|---|
| flash run store arms at boot | `run_flash: run store armed at 0x…` |
| the canned NMEA parses into a fix with ≥ 4 satellites | `gps: fix lat=… sats=N` |
| the optical-HR driver reads a plausible pulse off the AFE model | `hr: MAX86177 streaming` then `hr: bpm N`, 55 ≤ N ≤ 95 against a model synthesizing ~72 |
| that first fix starts a recording | `record: sim-autostart on first fix` |
| distance accumulates past 20 m | `record: recording dist=<m>` (DEBUG — hence `DEFMT_LOG=debug`) |
| the live fix reaches the **phone link** | a TCP connect to the `--phone-port` socket → v1 NDJSON frames that open on the present (within 20 s of the run clock, so the backlog was flushed), whose `uptime_s` strictly increases, and whose newest `fix` is within 0.001° of the log rail's newest |
| the run face renders on the panel | monitor `DumpFrame` → a PPM with ≥ 200 dark **and** ≥ 200 light pixels (all-light = nothing drawn, all-dark = a broken decode) |
| two BTN2 presses stop the run and commit it | `button: BTN2 armed` then `run_flash: stored run N (M B) in slot S`, M > 0 |
| nothing panicked | no `panicked` line in the decoded stream |

The HR and phone-link rows are folded into `smoke` rather than given scenarios of their own — neither needs anything that boot isn't already doing, and a scenario costs a whole emulator. Both cover a rail that previously had no assertion at all: the MAX86177 model had never had a BPM read off it by any scenario, and nothing had ever opened the phone-link socket, so the panel could be perfect while the link emitted nothing and only a human running the mobile dev screen would find out.

**The socket opens on the present, and that is a setting.** Renode's server-socket provider queues everything UARTE1 wrote while no client was attached, so with its default `flushOnConnect = False` an `ncat localhost 7788` against a ten-minute-old sim opened on the frame from `uptime_s: 1` and replayed ten minutes of history before catching up — as did the mobile Sim watch link screen, whose entire job is to show what the watch is doing now. `watch.resc` passes the fourth argument (`emulation CreateServerSocketTerminal $phone_port "phone" false true`) so the queue is dropped when a client arrives. The `smoke` scenario asserts it: the first frame off a fresh connection has to carry an `uptime_s` within 20 s of the run's own clock at the moment the socket was opened, which a replay of the boot cannot.

Every wait is on a specific log line with a per-assertion deadline rather than a fixed sleep, and the fixture + sensor models are virtual-time driven with no randomness (see [`sim/verification-2026-07-19/README.md`](sim/verification-2026-07-19/README.md)), so the run replays identically. The one exception is the ~1.5 s gap between the two BTN2 presses, which has to land inside the firmware's 4 s stop-confirm window and so can't wait on the "armed" line; a missed injected press is retried up to three times. On failure the job uploads the decoded stream, `renode.log`, the raw defmt capture, the monitor transcript, and the panel dump as the `custom-watch-sim-logs` artifact.

### Scenarios — running one at a time

`--scenario` selects which sequence runs. Default `all`; the process exits non-zero if any selected scenario fails.

```
python3 apps/custom_watch/sim/ci_smoke.py                        # all of them
python3 apps/custom_watch/sim/ci_smoke.py --scenario smoke       # just the proven path
python3 apps/custom_watch/sim/ci_smoke.py --scenario pages
python3 apps/custom_watch/sim/ci_smoke.py --scenario alerts
python3 apps/custom_watch/sim/ci_smoke.py --scenario terrain
python3 apps/custom_watch/sim/ci_smoke.py --scenario dropout
python3 apps/custom_watch/sim/ci_smoke.py --scenario screens
python3 apps/custom_watch/sim/ci_smoke.py --scenario idle
python3 apps/custom_watch/sim/ci_smoke.py --scenario workout
python3 apps/custom_watch/sim/ci_smoke.py --scenario storm

# a named fixture from sim/nmea/, a moved out-dir, a tighter wall-clock cap
python3 apps/custom_watch/sim/ci_smoke.py --scenario pages \
  --fixture mountain_loop --out-dir /tmp/watch-pages --budget 300

python3 apps/custom_watch/sim/ci_smoke.py --scenario alerts --phone-port 9900
```

| Scenario | What it proves | What it still doesn't |
|---|---|---|
| `smoke` | The recording pipeline end to end: NMEA → parser → fix accumulator → recorder → distance, one run face on glass, and the two-press stop committing a CRC'd blob to a flash slot. Since § 362 it also asserts the optical-HR rail (a BPM off the MAX86177 model) and the phone link (v1 NDJSON frames off the TCP socket, schema checked key by key). | Nothing about the *other* built-in pages — the ring is 41 built-ins plus up to four composed — and nothing about an alert firing. |
| `pages` | That the run-view page cycle actually renders — `$btn4` walks the filtered mask rightward (§ 350), `$btn3` is asserted to be the exact inverse, and each page produces a non-blank frame instead of a blank or a panic. It is a **render** assertion, so it catches a page whose face code faults, divides by zero on empty data, or draws nothing; it does not check that a number is *right*. | Correctness of any displayed value (that's the host tests on `watch_core`), legibility, glyph shape at a given font tier, or one-handed press ergonomics. |
| `alerts` | That the alert path fires from real recorded state and reaches the panel — the `watch_core::alerts` engine's fuel / zone / pace reminders off the recorder's own event cadence, and the `nav` task's off-course latch and re-arm — as an inverse-video banner, without disturbing the recording underneath it (the L4 contract). | Whether a tired runner *notices* it. There is no vibration motor at tier 1, so an alert is display-only by construction and "unmissable" is a bench/wrist claim, never a sim one. |
| `terrain` | That the two pages a flat fixture can't arm — `Waypoint` and `Climb` — come **into** the cycle once they are armed (a BTN5 hold marks a point, the BMP581 model's triangle profile climbs past the 20 m a climb opens at) and render. `pages` only ever proved they stay out of an unarmed cycle, which a data-presence bit wired to the wrong field passes silently. Plus the § 359 climb rail's two independent halves, which a page dump cannot speak to at all: the **detector** opening a climb (its own output, not the baro gain that feeds it), and the **crest ahead** read off the pushed course profile — asserted as a falling series rather than a value, because a position frozen by a lost signal keeps reporting the crest from where the runner *was*, and one sample cannot tell that from a live read. | That the WPT page shows the right bearing, or that any of these numbers is *rendered* correctly — the climb assertions read the recorder's own defmt lines, not the panel. Layout stays a host-test claim on `core/src/climb.rs` and `core/src/record.rs`. |
| `screens` | That a runner's own composed data screens (§ 364) reach the panel: `--screens` seeds three (Duo / Trio / Single) through `state::SCREENS` — the same channel a phone `SCR1` push feeds — and the walk asserts they are the first three pages a forward tap reaches after the Dashboard, that each draws a non-blank frame distinct from the others, and that the uncomposed fourth is **absent** from the cycle. That last one is the assertion with teeth: an unfed slot filtered in would render an empty screen the runner has to page past. | That a tired runner can read a `Duo` or `Trio` at 45 cm, or that the right metric landed in the right slot. The arcmin figures are derived; slot correctness is a host-test claim on `watch_core` and legibility is a step-4 bench claim no simulator settles. |
| `idle` | That the **idle** surfaces work — the only scenario that boots `--no-autostart`, so the only one that reaches them at all. The settings menu (§ 351) as a whole: BTN5 opens it and it reaches the panel, BTN3 walks all eight rows in their documented order and wraps, BTN2 walks back the other way, an edit on the GNSS row moves the ladder **and stays ordered** (parked at its left end, then walked back up — projected hours may not fall as you edit right), and BTN4 closes it. Then the three faces BTN4 walks (§ 291 + § 358) — Home, Diagnostics, and the ICE card a responder reads off a collapsed runner's wrist — each rendering a **distinct** frame, plus the menu's own MEDICAL ID row as the card's second route in. Then § 378's FACTORY ERASE: one BTN1 press has to *arm* (and change the panel) rather than wipe, stepping off the row and back has to leave the next press arming again rather than confirming, and only the second adjacent press wipes — after which the GNSS mode falls back from the Expedition rung the scenario itself walked to. | That an edit **survives a reboot** — `CFG1` persistence is a flash claim and this never power-cycles the emulator; the menu's writes are best-effort / L4 by design. Nor legibility of eight rows on a 1-bit panel, which is bench-only. **Nor that the erase reaches flash**: Renode answers `NVMC:READY` from its SVD and swallows the `ERASEPAGE` write, so the firmware reports success over an emulator that changed no byte — the slots really reading back `0xFF` is a step-7 bench item. |
| `dropout` | That the recorder survives a GPS void honestly and **comes back from it**: the pre-void leg banks distance, the void freezes it with every snapshot inside reading `paused`, and the reacquire — 122 m downrange past `MAX_JUMP_M`, over a gap past `GPS_REANCHOR_AFTER_S` — moves it again. That last bit is `run_recorder`'s #330 re-anchor, the bug this fixture found by hand on 2026-07-19; it froze distance for the rest of a run and was guarded only by host tests over `Recorder` until this scenario put a guard on the whole NMEA→parser→cadence→recorder path. | Anything about a *throttled* GNSS mode: the re-anchor is the 1 Hz path only (a throttled mode's `MAX_SPEED_MPS * dt` ceiling self-heals by design), and the sim runs the default cadence. |
| `storm` | That the § 376 storm rail runs end to end: the BMP581 model's **sea-level reference** is ramped down while its altitude stays put — a weather change, not a movement one — and the tracker withholds a tendency until a third of its window is banked (`Building`), reads a still atmosphere as `Steady` inside a 0.5 hPa residual, reaches `Storm` past the armed threshold once the front has run a full window, and raises **exactly one** banner for it (the arm's once-per-front hysteresis, countable only because `--no-alerts` leaves the slot to it). Then the Storm page enters the cycle and renders. Boots `--storm`, which compresses the trend window from three hours to 60 s and arms the banner. Verified to **fail** as well as pass before landing: feeding the tracker the baro-derived altitude instead of the GPS one — the circularity the module is built around avoiding — leaves the still atmosphere reading a suspiciously exact `+0.00 hPa` at the ISA reference and the front never arrives at all. | The thing the module exists for: telling a **climb** from a front. The firmware's altitude reference comes from the NMEA fixture, which the harness cannot ramp independently of the barometer, so an in-sim "climb" is a baro ramp against a flat GPS altitude — which *is* weather as far as any correct implementation can tell. That separation is host-tested on `core/src/storm.rs` and cannot be asserted here. |
| `workout` | That the § 354 / § 356 structured-workout rail runs end to end: the pushed step list arms the recorder over the channel a `WKT1` push lands on, the Workout page enters the cycle and renders, the runner auto-advances through the plan **in order over both end axes** (the demo plan mixes 50-60 m distance steps with a 30 s duration one, so a runner that settles only one axis stalls partway), **exactly one** end-of-step warning fires — the recovery, the only step clearing `ENDING_MIN_STEP_S`; nothing else can hold the alert slot because it boots `--no-alerts` — a BTN5 lap press skips the active step and then completes the workout, and the finished five-step trail flushes into the run blob with no step or summary dropped. The skip is timed on the **firmware's** virtual clock: an edge under a second into a step that needs ~33 s to end by itself is the press, not the schedule ([§ 371](../../docs/architecture/decisions.md)). | That the page reads `WORKOUT DONE` — nothing here reads a glyph — or anything about the real `WKT1` transport, which needs a SoftDevice. It also cannot assert the negative (the page staying OUT of a cycle with no workout): every run-starting boot in the harness arms the demo workout. |

`--budget` is a hard wall-clock cap for the run, not a per-assertion deadline (those are per-assertion and tighter). It exists so a wedged emulator fails with the harness's own diagnostics — last 40 lines of decoded output plus the tail of `renode.log` — rather than hanging until something outside kills it. Locally you can leave it at the default; in CI it is set per step, and always below the job's own `timeout-minutes`.

### Looking at the UI — `bin/watch-shots.sh`

`ci_smoke.py` dumps panels to assert they are *not blank*; nothing made them viewable. `bin/watch-shots.sh` does — it boots the sim twice, walks every screen it can reach, and writes one PNG per screen plus a self-contained HTML contact sheet you open in a browser. Use it whenever you touch `face.rs`, `widgets.rs`, or anything that decides where a value lands: a bad layout becomes something you can *see* instead of something a human has to notice while paging through thirty-odd screens in `--gui`. Rationale + what it caught on its first run in [decisions.md § 360](../../docs/architecture/decisions.md).

```
bin/watch-shots.sh                        # both sessions -> /tmp/watch-shots/index.html
bin/watch-shots.sh --session run          # only the run-view page cycle
bin/watch-shots.sh --session idle         # only the idle faces + the settings menu
bin/watch-shots.sh --out-dir /path/shots  # somewhere durable
```

### The live window without Renode's UI — `bin/watch-view.sh`

`--gui` needs a Renode build that can start its own window layer, and the
macOS arm64 .NET build cannot (renode/renode#886 — "Couldn't start UI",
console fallback, and a backgrounded console reads its closed stdin as
`quit`). On such a build `--gui` falls back to this route by itself —
headless relaunch plus the viewer. To drive it by hand instead:

```
bin/watch-sim.sh                # terminal 1 (or pnpm watch:sim)
bin/watch-view.sh               # terminal 2 (or pnpm watch:view)
```

It polls the display model's `DumpCanvas` over the telnet monitor (~5 fps)
and resolves clicks through the model's own `HitButtonAt`, then fires the
watch.resc **virtual-time** button macros — a raw press/release pair over
the socket lands milliseconds apart in wall time, which the firmware's
~10 ms poll can miss and its tap-vs-hold classifier would misread. Left-click
taps; right-click / ctrl-click holds (BTN3/BTN4: page grid, BTN5: mark
waypoint); keys 1–5 tap, shift+key holds. Closing the window detaches like
`watch-monitor.sh`'s Ctrl-C — the sim keeps running. Needs a python with
tkinter (`brew install python-tk@3.13`); the wrapper probes for one.

### Looking at the UI without Renode — `bin/watch-preview.sh`

The host rung of the same story. `render/src/preview.rs` composes each page the
way the ui task does; with `WATCH_PREVIEW_DIR` set, every preview test also
dumps its panel as a 1:1 PPM. `bin/watch-preview.sh` wraps that — run the
previews, convert to crisp PNGs, montage a contact sheet — so a layout change
is viewable on any machine with cargo + ImageMagick, no renode, no defmt-print,
no board. The split: this shows what the *compositions* render (a host-test
claim); `watch-shots.sh` shows what the *firmware* drew (a sim claim).

```
bin/watch-preview.sh                      # -> /tmp/watch-preview/contact-sheet.png
bin/watch-preview.sh --zoom 4             # bigger PNGs (default 3x)
bin/watch-preview.sh --out-dir /path      # somewhere durable
```

Two boots, because the run view and the idle faces are disjoint — the page cycle only exists mid-run, and the idle faces are only reachable before one starts. The `run` session uses `mountain_loop` with `scenario_terrain`'s two arming steps (the BMP581 triangle profile and a BTN5-hold waypoint mark), so `CLMB` and `WPT` are in the cycle instead of legitimately filtered out of it; the `idle` session boots `--no-autostart`. Both boot **`--no-alerts`** — see below. Expect ~25 screens and several minutes. Needs ImageMagick 7 (`magick`) on top of the sim's own prerequisites.

Every capture is named by the ui task's own line — `ui: page <Name>`, or `ui: idle <View>` for a face — and each press cross-checks that against the button task's intent exactly as `scenario_pages` does, so a file called `page-Pacer.png` is the panel the composer *said* it composed. Two kinds of bad frame are rejected and re-shot, both measured on the captured pixels rather than inferred from the log: one under an alert banner (a solid inverse-video band over the hero rows — the log would only say what the *record* task believes, and this walk's subject is what reached the panel), and one byte-identical to the previous screen (the composer logs its line *before* it draws, so a dump sent the instant that line decodes can read the previous frame — this is how the harness first "proved" the two idle faces render identically). A screen that stays bad after four tries is still captured and says so in its caption.

**Why `--no-alerts`.** The re-shoot loop can only wait a banner out if there are gaps to wait in, and when this was written there were none: the sim's shortened cadences (fuel at 30 s / 45 s, plus the distance, time and pace arms) overlapped into a continuous banner past ~100 s, which is exactly when a 25-screen walk is still running. [§ 465](../../docs/architecture/decisions.md) since put a floor under the gap, so the loop would now have windows to wait in — the flag stays because waiting one out still costs a re-shoot per screen, and a screenshot walk wants the hero band, not a demonstration that the banner clears. On the first sheet that cost **six of the twenty-one run screens** — `page-Dashboard` and `page-Climb` among them, the latter's entire hero replaced by `! DRINK`. Those cadences exist for the `ci_smoke` `alerts` scenario and are noise to everything else, so they now sit behind their own `sim-alerts` Cargo feature that `--no-alerts` drops. Dropping `sim-autostart` instead would also have silenced them, and would have taken with it the demo settings that arm most of the pages worth photographing. Measured on the next sheet: **22 re-shoots and six unusable screens became 2 and none.** The two that remain are the Dashboard waiting out a `WorkoutStep` banner from the demo workout, which stays armed because the Workout page is one of the pages worth photographing — one of those is the shape this is meant to leave behind, a banner the loop can actually wait out.

**A screenshot is *sim-verified* evidence and no more.** Nothing here reads a glyph: a capture says the named screen composed and inked pixels. Layout and value correctness stay host-test claims (`render/src/preview.rs`, `core/`) — see [quality_standards.md](../../docs/custom_watch/quality_standards.md). And the sheet is not the whole UI: thirteen pages have no `SET1` wire field to arm them, so ~25 screens is the ceiling of what the sim can show, not of what the watch renders.

Use `--out-dir` when running more than one scenario by hand: each run clears `sim-output.log`, `frame.ppm` and the `watch-sim.latest` pointer in its out-dir first, so two scenarios sharing one out-dir destroy each other's evidence.

### What the sim cannot prove, in the four-rung vocabulary

The rungs are defined in [`docs/custom_watch/quality_standards.md`](../../docs/custom_watch/quality_standards.md). A green run of any scenario earns **sim-verified** for the observable it named, and that rung's ceiling is: *says nothing about real silicon, analog behaviour, the radio, or power*. Concretely, and none of this changes as scenarios are added:

- **BLE can never be sim-verified.** Renode does not model the S140 SoftDevice ([decisions.md § 210](../../docs/architecture/decisions.md)), so the whole radio path — RAM origin, interrupt priorities, connection interval, pairing/bonding, and every characteristic (`frame`, `run_manifest`, `run_chunk`, the write-only pushes `settings` / `course` / `workout` / `screens` / `roadbook`, and the read-only `push_status`) — jumps host/build-verified straight to bench-verified. There is no sim scenario that could cover it.
- **The sim models no power at all.** Renode does not simulate current, so a green run is **not a battery claim**. Every power and runtime figure in this workspace — the ~110 / ~180 / ~220 h GNSS-mode projections included — is a derivation awaiting a PPK2.
- **The sensor models are pinned to the drivers, not to silicon.** The MAX86177 and BMP581 models answer the register sequences the drivers issue, with a deterministic waveform and a scripted altitude. That verifies the *path*; a model built from the driver's beliefs cannot detect a wrong belief. No register semantics, no bus timing, no analog noise or settling.
- **No SAADC**, so the battery-gauge sampling path is unreachable; only "the task parks cleanly and the faces still render" is checkable.
- **No RF, no antenna, no thermal, no mechanical, no legibility.** A `pages` pass says a page drew pixels — not that a numeral is readable in direct sun at arm's length, which is a step-4 bench item.

A green `sim-firmware` means the firmware is self-consistent end to end under the emulator. The bench-verify list in [`sim/verification-2026-07-19/README.md`](sim/verification-2026-07-19/README.md) § Model limitations and the tier-1 checklist in `quality_standards.md` are untouched by it. Never write "verified" without the rung and the observable.

## Common errors

**"No debug probes found"** — the board isn't plugged in, the USB cable is power-only (try a different cable), udev rules aren't installed (Linux), or the J-Link firmware on the DK has wedged. For the last one, power-cycle the board while holding the reset button — that triggers the [J-Link On-Board recovery procedure](https://www.segger.com/products/debug-probes/j-link/).

**"target 'thumbv7em-none-eabihf' not found"** — `rustup target add thumbv7em-none-eabihf` not run yet. `bin/watch-doctor.sh` catches this.

**"Failed to attach to RTT"** — happens occasionally when reflashing while logs are streaming. Solution: `probe-rs reset --chip nRF52840_xxAA` and retry.

**Logs garbled or out of order** — RTT buffer overflowed because the firmware is logging faster than your USB can drain. Either reduce log frequency in firmware (`defmt::trace!` for high-rate events instead of `defmt::info!`) or drop the active log level via the `DEFMT_LOG` env var.

**`cargo run` hangs after "Flashing"** — usually a power issue with the DK. Unplug, wait 5 seconds, replug, retry. If persistent, check that the DK's `SW6` power switch is set to `VDD` and not `Source`.

**"Mass storage interface error"** — the J-Link mass-storage interface is enabled and conflicting with probe-rs. Disable it via the [J-Link Commander](https://www.segger.com/downloads/jlink/) command `MSDDisable`, then power-cycle the board. Persists across reboots once disabled.

**`cargo` complains about thumbv7em features it doesn't recognise** — your Rust toolchain is too old. `rustup update stable` and try again.

**`watch-sim.sh`: "defmt-print not on PATH"** — `cargo install defmt-print --locked`. It's a host-side cargo tool, so it rides `cargo install-update` afterwards.

**`watch-sim.sh`: "Renode never created the GPS pty" or "defmt-rtt drain did not arm"** — a monitor-level error aborted `sim/watch.resc`, and those errors don't reach the Renode log. **Read the stage the message quotes first**: it is the last `watch.resc stage:` marker the include reached, so the failing command is the one after it. Then re-run the include under `renode --console` to see the error itself (see § Simulating without a board). The commonest cause is a non-ASCII character introduced into `sim/defmt_rtt.py`. The wait is bounded at 180 s (`WATCH_SIM_BOOT_TIMEOUT_S` overrides), which is a failure bound rather than a schedule — a cold Renode compiles seven C# peripheral models before it reaches the pty, and the previous 30 s bound was short enough to fail a healthy boot on a busy machine.

**`watch-sim.sh`: "phone-link port 7788 is already in use" / "claimed by another watch sim"** — the wrapper takes an advisory `flock` on a per-port lock file (`$TMPDIR/watch-sim.phone-<port>.lock`, and one per monitor-port draw) and holds it on a descriptor Renode inherits, so a second sim WAITS for the first to release rather than racing it into an `AddressAlreadyInUse` abort. "Claimed by another watch sim" means that wait ran out (45 s, `WATCH_SIM_PORT_WAIT_S`) — find the other sim, or pass `--phone-port <n>`. "Already in use" after the claim means the holder is not a watch sim at all: usually a Renode from some other context, `pgrep -f '^dotnet /opt/renode'` and kill what you find. (Note when hunting: `pkill -f Renode.dll` matches *your own shell's* command line — anchor the pattern as above.) On macOS there is no `flock(1)`, so the wrapper says so and falls back to the check alone.

**Successful flash but no LED blink, no defmt logs, or immediate chip reset.** Probable cause: the chip variant string in `apps/custom_watch/.cargo/config.toml` doesn't match the actual silicon on the DK. The scaffold uses `nRF52840_xxAA` (the standard variant in PCA10056); some boards or chip revisions ship as `nRF52840_xxAA-B` or other variants whose flash base addresses + ROM layouts differ slightly. probe-rs picks its flash algorithm from the chip string — a mismatch can "flash successfully" but the binary then references hardware that doesn't exist in that variant, causing immediate reset or silent no-op. **Diagnostic:** `probe-rs list` to see what probe-rs detects, `probe-rs chip list nRF52` to see known variants. **Fix:** update the `--chip` argument in the `.cargo/config.toml` runner line to match. `bin/watch-doctor.sh` prints the configured chip string on every run so you can spot a mismatch before it bites.
