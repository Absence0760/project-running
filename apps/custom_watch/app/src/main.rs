//! custom_watch tier-1 firmware — entry point.
//!
//! Boots the Embassy async runtime, splits the board into per-subsystem
//! ports (`nrf52840_dk::Board`), and spawns one task per subsystem. Tasks
//! are thin peripheral glue; the logic they drive lives in the host-tested
//! `watch_core` + driver crates.
//!
//! See `apps/custom_watch/README.md` for the per-step bring-up plan.

#![no_std]
#![no_main]

use defmt::*;
use embassy_executor::Spawner;
use embassy_nrf::{bind_interrupts, peripherals, uarte};
use nrf52840_dk::Board;
use {defmt_rtt as _, panic_probe as _};

mod state;
mod tasks;

bind_interrupts!(struct Irqs {
    UARTE0 => uarte::InterruptHandler<peripherals::UARTE0>;
});

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let p = embassy_nrf::init(Default::default());
    let board = Board::split(p);
    info!("custom_watch firmware booting (tier 1)");

    let mut gps_config = uarte::Config::default();
    gps_config.baudrate = uarte::Baudrate::BAUD9600;
    let gps_uart = uarte::Uarte::new(
        board.gps.uarte,
        board.gps.rx,
        board.gps.tx,
        Irqs,
        gps_config,
    );
    let (_gps_tx, gps_rx) = gps_uart.split();

    spawner.spawn(unwrap!(tasks::ui::blink_task(board.leds.led1)));
    spawner.spawn(unwrap!(tasks::gps::run(gps_rx)));

    spawner.spawn(unwrap!(tasks::hr::run()));
    spawner.spawn(unwrap!(tasks::baro::run()));
    spawner.spawn(unwrap!(tasks::ble::run()));
    spawner.spawn(unwrap!(tasks::record::run()));
}
