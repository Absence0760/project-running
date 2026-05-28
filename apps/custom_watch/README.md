# custom_watch — tier-1 bench-prototype workspace

Rust + Embassy firmware for the ultra-marathon watch research effort. This is *only* the active workspace + per-step build status; the broader research (strategy, BOM, cost tiers, firmware architecture, performance path, parts list) lives under [`docs/custom_watch/`](../../docs/custom_watch/README.md). See also [`CLAUDE.md`](CLAUDE.md) in this directory for the scope rules.

## Status

**Workspace scaffolded 2026-05-28 — no parts yet, no on-board verification yet.** [decisions.md §71](../../docs/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) was amended 2026-05-28 to allow owner-personal tier-1 work in evenings/weekends. Tier 2+ (PCB CAD, case CAD, RF consultant spend, ODM conversations) remain gated on the three triggers in §71. The Cargo workspace at this directory is in place per [§ 80](../../docs/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance); first flash (toolchain + blink-LED end-to-end against a real nRF52840 DK) lands when the dev kit arrives — see [`parts.md`](../../docs/custom_watch/parts.md).

**Language + framework decided: Rust + Embassy on the Nordic nRF52840.** See [decisions.md §80](../../docs/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) for why (short version: memory safety + tooling + async ergonomics, *not* perf — Rust vs C is within ±5% on this class of MCU). See [`docs/custom_watch/performance_path.md`](../../docs/custom_watch/performance_path.md) for where the performance levers actually live, and [`docs/custom_watch/competitive_landscape.md`](../../docs/custom_watch/competitive_landscape.md) for the strategic framing of why tier 1 exists at all.

## Local testing

The watch's developer inner loop is `bin/watch-flash.sh` from the repo root (or `cargo run --release` from this directory): build the firmware, flash it to a connected Nordic nRF52840 DK, stream `defmt` logs back to your terminal until Ctrl-C. Host-side unit tests run via `bin/watch-test.sh` or `cargo test` and don't need a board. Run `bin/watch-doctor.sh` once per machine to verify toolchain + board detection. See [`local_testing.md`](local_testing.md) for the full setup walkthrough, the host-vs-on-target testing split, and the common-error reference.

## Next steps

1. **Order parts** — see [`docs/custom_watch/parts.md`](../../docs/custom_watch/parts.md). Total ~$300 for the MCU + sensor breakouts + battery + breadboard, plus ~$200–$900 in bench tools depending on which soldering iron / multimeter / logic analyzer tier you pick.
2. **Scaffold the Cargo workspace** — **DONE (2026-05-28).** `Cargo.toml`, `rust-toolchain.toml`, `.cargo/config.toml` with probe-rs runner, `app/` crate with Embassy executor + blink-LED stub task, stub modules for each subsystem, driver crates (`sharp_mip`, `ublox_nmea`, `max86177`) as `no_std` stubs, board crate (`nrf52840_dk`) with DK pin assignments, VS Code launch + tasks for in-IDE debug. `nrf-softdevice` is **not** in deps yet — it adds at step 6 with BLE and requires bumping `memory.x` to leave room for the SoftDevice. First flash pending parts arrival.
3. **GNSS bring-up** — u-blox MAX-M10S over UART, NMEA parser, log fixes at 1 Hz via `defmt` over RTT.
4. **Display bring-up** — Sharp Memory LCD over SPI, render current GPS fix. This is the first hand-rolled driver — about 100 lines of SPI bit-banging plus a small framebuffer abstraction.
5. **Optical HR bring-up** — MAX86177 over I²C, raw photodiode sample → naive peak-detect (the licensed HR algorithm comes later via `bindgen` against Maxim's C library, post-tier-1).
6. **BLE GATT bring-up** — phone pairs via `nrf-softdevice`, watch advertises a custom service, phone reads a dummy characteristic.
7. **Integration** — wire steps 3–6 into a single recording state machine that ports the existing Dart `run_recorder` algorithm to async Rust.

Each step is roughly 2–4 weeks of evenings depending on prior firmware experience.

## Layout

Actual workspace shape (Cargo workspace, all paths relative to `apps/custom_watch/`):

```
Cargo.toml              workspace root
rust-toolchain.toml     pins a recent stable Rust + thumbv7em-none-eabihf target
.cargo/config.toml      runner = probe-rs, default target, defmt log level
app/
  Cargo.toml
  src/
    main.rs             #[embassy_executor::main] entry, spawns tasks
    tasks/
      gps.rs            GNSS NMEA parser task
      hr.rs             MAX86177 polling + naive peak-detect task
      baro.rs           BMP390 sample task
      ui.rs             screen update + button-handler task
      ble.rs            GATT server + sync task
      record.rs         recording state machine (port of Dart run_recorder)
drivers/
  sharp_mip/            Sharp Memory LCD driver crate
  ublox_nmea/           u-blox NMEA parser crate (no_std)
  max86177/             MAX86177 register-level driver + bindgen wrapper for the HR algorithm
boards/
  nrf52840_dk/          board-support crate: pinmux, peripheral assignments
```

This is intentionally close to the per-task / per-driver split that the Zephyr-flavoured proposal in [`docs/custom_watch/firmware.md`](../../docs/custom_watch/firmware.md) uses — so the firmware architecture stays portable across the language choice. If we ever revert to C/Zephyr per the §80 fallback, the task boundaries map directly onto Zephyr threads + work queues.
