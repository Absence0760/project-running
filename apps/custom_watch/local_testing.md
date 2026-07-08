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
- **Simulator runs** sit between the two: `bin/watch-sim.sh` boots the real firmware ELF on an emulated nRF52840 DK (Renode). Not a test tier with assertions (yet) — an interactive bring-up and debugging surface for the peripheral-touching paths host tests can't reach, minus what Renode can't model (BLE radio, sensor analog, power). See [Simulating without a board](#simulating-without-a-board-renode).

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
- Test BLE (nrf-softdevice needs the real radio — Renode doesn't model it faithfully; the phone link's sim transport below is the stand-in)
- Test real sensor analog behaviour (the HR/baro breakouts have no Renode device models yet — the display does)
- Measure actual power consumption

## Simulating without a board (Renode)

`bin/watch-sim.sh` boots the firmware on [Renode](https://renode.io/)'s emulated nRF52840 DK — no board, no probe-rs. It builds the **exact** `thumbv7em-none-eabihf` release ELF that `watch-flash.sh` flashes (nothing is compiled differently for the simulator), starts headless Renode with [`apps/custom_watch/sim/watch.resc`](sim/watch.resc), and streams decoded defmt logs to your terminal until Ctrl-C — same UX as `watch-flash.sh`. Rationale + design in [decisions.md § 208](../../docs/architecture/decisions.md#208-firmware-simulation-runs-the-unmodified-elf-on-renode-with-a-custom-defmt-rtt-drain).

```
bin/watch-sim.sh                      # build + boot the default binary, headless
bin/watch-sim.sh --gui                # also open the live watch-screen window
bin/watch-sim.sh --bin sensor_smoke   # boot a specific binary
bin/watch-sim.sh --nmea my_route.nmea # substitute the GPS fixture
bin/watch-sim.sh --phone-port 9900    # move the phone-link TCP port (default 7788)
```

What runs for real in the sim, end to end: the Embassy executor and RTC1 time driver; GPIO (LED1 toggles logged at INFO as `gpio0.led0: LED1 on/off`); the GPS pipeline (canned NMEA → UARTE0 → `ublox_nmea` parser → `watch_core` fix accumulator); the Sharp MIP display (SPIM3 → the C# panel model — `--gui` shows the live screen, or dump a frame from the monitor: `sysbus.spi3.display DumpFrame "/tmp/frame.ppm"`); and the phone link (status frames on UARTE1 → TCP, the mobile app's dev Sim Watch screen connects here). What doesn't: BLE, power, and the HR/baro sensor analog side.

Moving parts, all inside [`sim/`](sim/):

- **`watch.resc`** — the Renode script: loads the stock `nrf52840dk_nrf52840` platform, declares SPIM3 with EasyDMA + the display model, loads the ELF, arms the defmt drain, logs LED1 state changes, bridges the phone-link UART to TCP, exposes the GPS UART as a pty.
- **`defmt_rtt.py`** — gets defmt logs out. Renode's bundled `segger-rtt.py` hooks the SEGGER *C library's* function symbols, which the pure-Rust `defmt-rtt` crate doesn't have; this script instead polls the `_SEGGER_RTT` control block in emulated RAM, appends new bytes to a capture file, and advances the read offset. The wrapper tails that file through `defmt-print -e <elf>` for live decoded output.
- **`SharpMipDisplay.cs`** — a runtime-compiled Renode peripheral modelling the Sharp Memory LCD: decodes the exact line-update protocol `drivers/sharp_mip` encodes (CS-GPIO framing, 1-based line addresses, white-is-1 polarity) into a video framebuffer. `showAnalyzer sysbus.spi3.display` is the window `--gui` opens; `DumpFrame` writes a PPM for headless checks.
- **`nmea/bench_jog.nmea`** — a synthetic ~2-minute rectangular jog loop (GGA+RMC pairs with valid checksums, 1 Hz fix rate like a real MAX-M10S). The wrapper loops it into the emulated `uart0` forever; the GPS task parses it into fixes that drive both the on-screen face and the phone-link frames, so the whole data path is exercised against a deterministic feed.

The phone link mirrors the step-6 BLE design without the radio: the firmware's `phone` task writes one `watch_core::link` NDJSON status frame per second to UARTE1, Renode serves it as a TCP socket (`tcp://localhost:7788`; the Android emulator reaches it at `10.0.2.2:7788`), and the mobile app's dev-only **Settings → Developer → Sim watch link** screen (loopback-backend gate) renders the live values. `ncat localhost 7788` shows the raw frames.

Sim artifacts (Renode log, raw defmt capture) are kept in a `/tmp/watch-sim.XXXXXX` dir printed on exit. Each run picks a random monitor telnet port (printed in the "Renode up" line) — `ncat localhost <port>` gets you an interactive Renode monitor to poke registers, pause the machine, or dump display frames mid-run.

Gotchas, learned the slow way:

- **`sim/defmt_rtt.py` must stay ASCII-only and Python-2 compatible.** Renode embeds IronPython 2: one em dash in a comment aborts the include (`Non-ASCII character '\xe2'`), and the failure is only visible on the monitor console, not in the Renode log. The wrapper guards this (pty-as-sentinel + a grep for "defmt-rtt drain active"), but if you edit the file, keep it plain ASCII.
- **Monitor errors never reach the Renode log file.** If `watch-sim.sh` dies with "Renode never created the GPS pty", re-run the include interactively to see the real error: `renode --console -e "include @apps/custom_watch/sim/watch.resc"`.
- **The UICR warning at boot is expected.** embassy-nrf checks the UICR region to configure the reset pin; Renode doesn't model UICR, the read returns zeros, and the firmware logs a WARN about not being able to reprogram it. Harmless in the sim; it does not appear on real hardware.

## CI parity

The CI workflow at `.github/workflows/ci.yml` has a `build-firmware` job (per [decisions.md § 80](../../docs/architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)) that runs on every PR:

```
rustup show                                            # installs toolchain per rust-toolchain.toml
cargo build --release --target thumbv7em-none-eabihf
cargo test --target <HOST_TRIPLE> --workspace --exclude app --exclude nrf52840_dk
cargo clippy --workspace --release --target thumbv7em-none-eabihf -- -D warnings
cargo fmt --check
```

All of those run on a stock Ubuntu CI runner with no hardware, with Cargo registry + `target/` cached across PRs via `actions/cache` keyed on the `Cargo.toml` + `rust-toolchain.toml` hashes (uncached cold builds are ~3-5 min; cached re-runs are seconds). On-target tests stay manual / local until tier 2+ where we'd connect a HIL (hardware-in-the-loop) rig to a self-hosted runner.

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
