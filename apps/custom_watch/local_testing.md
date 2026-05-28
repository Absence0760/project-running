# Local testing — custom_watch firmware

How to build, flash, test, and debug the watch firmware on a connected Nordic nRF52840 DK. Optimised for "plug in the board, type one command, see GPS fixes streaming in the terminal within 60 seconds."

## TL;DR — the three commands you'll actually run

Once parts have arrived and you've done the first-time setup below:

```
bin/watch-doctor.sh    # verify toolchain + board detection; run once per machine
bin/watch-flash.sh     # build + flash + stream defmt logs (the inner loop)
bin/watch-test.sh      # host-side unit tests, no board required
```

All three are thin wrappers around `cargo` and `probe-rs`. If you prefer the unwrapped form, `cd apps/custom_watch && cargo run --release` is what `bin/watch-flash.sh` actually does — same outcome, more typing.

## What "testing" means on embedded vs web/mobile

The web stack tests one way: Vitest unit tests and Playwright e2e tests, both running in headless processes on your dev machine. The mobile stack tests two ways: Dart unit tests (host process) plus Flutter `integration_test` (real-or-emulated device).

Embedded firmware has a sharper split:

- **Host tests** run on your development machine via `cargo test`. They cover any logic that doesn't touch a peripheral — NMEA parsers, recording state machines, signal-processing helpers, anything in the `drivers/` crates that's pure data manipulation. These give you instant feedback (sub-second), run in CI without any hardware, and are the same workflow you already know from web/backend.
- **On-target tests** run on the actual nRF52840 DK. Anything that reads a sensor, drives the display, talks to the radio, or relies on hardware timers belongs here. They're slower (you have to flash the board before running) and require a board plugged in. They're the embedded equivalent of mobile e2e tests.

The line between the two is enforced architecturally: pure-logic crates in `apps/custom_watch/drivers/` build for the host (`x86_64-unknown-linux-gnu`) and `cargo test` normally. The `app/` and `boards/` crates build for `thumbv7em-none-eabihf` and need a board. Aim to keep 60–70% of firmware code host-testable — it's the single most effective lever for keeping the inner loop fast.

## Prerequisites (install once per dev machine)

[`bin/watch-doctor.sh`](../../bin/watch-doctor.sh) verifies each of these. Install + run the doctor, fix what it flags, re-run until green.

1. **Rust toolchain** — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` (or `dnf install rustup && rustup-init` on Fedora).
2. **The Cortex-M4F build target** — `rustup target add thumbv7em-none-eabihf`. This is what the nRF52840 actually runs.
3. **probe-rs** — `cargo install probe-rs-tools --locked`. Open-source replacement for Segger's J-Link tools. Includes `probe-rs run` (flash + run + stream logs) and `probe-rs attach` (stream logs from an already-running board). (The older `cargo install probe-rs --features cli` form still works, but `probe-rs-tools` is the current canonical name.)
4. **udev rules for USB access on Linux** — copy [the official probe-rs rules](https://probe.rs/docs/getting-started/probe-setup/#udev-rules) into `/etc/udev/rules.d/` and `sudo udevadm control --reload`. Without these, non-root users can't talk to the debug probe and `probe-rs list` will report nothing even when the board is plugged in.
5. **`cargo-watch` (optional but nice)** — `cargo install cargo-watch`. Lets you auto-reflash on file save with `cargo watch -x 'run --release'`.

## First-time setup, after the workspace is scaffolded

If `apps/custom_watch/Cargo.toml` doesn't exist yet, see step 2 of [`README.md`](README.md) in this directory — the testing workflow below only becomes useful once that scaffold lands.

After scaffolding:

1. Plug the nRF52840 DK into a USB port using a **data cable** (not power-only). The onboard Segger J-Link enumerates as `/dev/ttyACM*` on Linux, `/dev/cu.usbmodem*` on macOS.
2. Run `bin/watch-doctor.sh` from the repo root. All five checks should pass and your board should appear in the "Connected debug probes" section.
3. Run `bin/watch-flash.sh`. You should see the user LED on the DK toggling within ~5 seconds, plus `defmt` log lines streaming in your terminal. Ctrl-C to exit; the board keeps running whatever was last flashed.

If step 3 hangs at "Flashing", unplug the board, wait 5 seconds, plug it back in, and retry. If `probe-rs list` shows nothing even after re-plugging, the udev rules from prerequisite #4 probably aren't installed.

## Day-to-day commands

All commands assume you're in `apps/custom_watch/` unless prefixed with `bin/`. The `bin/` wrappers all `cd` into the workspace internally and forward extra args through to the underlying tool.

| What | From the workspace | From the repo root | Hardware? |
|---|---|---|---|
| Verify toolchain + board detection | — | `bin/watch-doctor.sh` | Board if checking detection |
| Compile-check the whole workspace | `cargo build` | `bin/watch-build.sh` | No |
| Build a release binary | `cargo build --release` | `bin/watch-build.sh` | No |
| Run host-side unit tests | `cargo test` | `bin/watch-test.sh` | No |
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

You **cannot**:

- Run `cargo run` (it requires a board to flash to)
- Test the display, GPS, optical-HR, BLE, or any peripheral driver
- Measure actual power consumption

For hardware-less integration testing of peripheral-touching code, the long-term answer is [Renode](https://renode.io/) — an open-source MCU emulator that supports the nRF52 family. Setup is non-trivial (~half a day) and out of scope for tier 1; it becomes worth doing if/when we add a CI job that runs on-target integration tests.

## CI parity

The CI workflow at `.github/workflows/ci.yml` will get a `build-firmware` job (planned, lands with the Cargo workspace scaffold per [decisions.md § 80](../../docs/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)) that runs:

```
rustup target add thumbv7em-none-eabihf
cargo build --release --target thumbv7em-none-eabihf
cargo test                                              # host-side
cargo clippy --all-targets -- -D warnings
cargo fmt --check
```

All of those run on a stock Ubuntu CI runner with no hardware. On-target tests stay manual / local until tier 2+ where we'd connect a HIL (hardware-in-the-loop) rig to a self-hosted runner.

## Common errors

**"No debug probes found"** — the board isn't plugged in, the USB cable is power-only (try a different cable), udev rules aren't installed (Linux), or the J-Link firmware on the DK has wedged. For the last one, power-cycle the board while holding the reset button — that triggers the [J-Link On-Board recovery procedure](https://www.segger.com/products/debug-probes/j-link/).

**"target 'thumbv7em-none-eabihf' not found"** — `rustup target add thumbv7em-none-eabihf` not run yet. `bin/watch-doctor.sh` catches this.

**"Failed to attach to RTT"** — happens occasionally when reflashing while logs are streaming. Solution: `probe-rs reset --chip nRF52840_xxAA` and retry.

**Logs garbled or out of order** — RTT buffer overflowed because the firmware is logging faster than your USB can drain. Either reduce log frequency in firmware (`defmt::trace!` for high-rate events instead of `defmt::info!`) or drop the active log level via the `DEFMT_LOG` env var.

**`cargo run` hangs after "Flashing"** — usually a power issue with the DK. Unplug, wait 5 seconds, replug, retry. If persistent, check that the DK's `SW6` power switch is set to `VDD` and not `Source`.

**"Mass storage interface error"** — the J-Link mass-storage interface is enabled and conflicting with probe-rs. Disable it via the [J-Link Commander](https://www.segger.com/downloads/jlink/) command `MSDDisable`, then power-cycle the board. Persists across reboots once disabled.

**`cargo` complains about thumbv7em features it doesn't recognise** — your Rust toolchain is too old. `rustup update stable` and try again.
