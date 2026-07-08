//! Phone-link task — streams `watch_core::link` status frames over UARTE1,
//! which the simulator bridges to a TCP socket the mobile app's dev screen
//! connects to.
//!
//! This is the default / sim transport. On real hardware the `ble` feature
//! (README step 6) carries the SAME frames over a GATT notify characteristic
//! instead (`tasks::ble`), and `main` spawns that task in place of this one —
//! the frame layout is identical, only the pipe differs.

use defmt::*;
use embassy_nrf::uarte::UarteTx;
use embassy_time::{Duration, Instant, Ticker};
use watch_core::link;

use crate::state;

#[embassy_executor::task]
pub async fn run(mut tx: UarteTx<'static>) {
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut elev_rx = unwrap!(state::ELEVATION.receiver());
    let mut latest = None;
    let mut elev = None;
    let mut ticker = Ticker::every(Duration::from_secs(1));
    info!("phone: status frames on UARTE1");
    loop {
        ticker.next().await;
        if let Some(fix) = fix_rx.try_changed() {
            latest = Some(fix);
        }
        if let Some(reading) = elev_rx.try_changed() {
            elev = Some(reading);
        }
        let frame = link::status_frame(
            latest.as_ref(),
            elev.as_ref(),
            Instant::now().as_secs() as u32,
        );
        if let Err(e) = tx.write(frame.as_bytes()).await {
            warn!("phone: uart write error {:?}", e);
        }
    }
}
