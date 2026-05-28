//! custom_watch tier-1 firmware — entry point.
//!
//! Boots the Embassy async runtime, spawns the per-subsystem tasks, then idles
//! the CPU. At tier 1 only `ui::blink_task` is wired up to do anything visible
//! — the rest are stubs that log-and-return so the binary compiles + runs
//! end-to-end against the nRF52840 DK before the drivers are written.
//!
//! See `apps/custom_watch/README.md` for the per-step bring-up plan.

#![no_std]
#![no_main]

use defmt::*;
use embassy_executor::Spawner;
use {defmt_rtt as _, panic_probe as _};

mod tasks;

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let p = embassy_nrf::init(Default::default());
    info!("custom_watch firmware booting (tier 1, blink-LED stub)");

    spawner.must_spawn(tasks::ui::blink_task(p.P0_13.into()));

    spawner.must_spawn(tasks::gps::run());
    spawner.must_spawn(tasks::hr::run());
    spawner.must_spawn(tasks::baro::run());
    spawner.must_spawn(tasks::ble::run());
    spawner.must_spawn(tasks::record::run());
}
