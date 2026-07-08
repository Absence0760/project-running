//! Phone-link task — streams `watch_core::link` status frames to the phone.
//!
//! Transport today: UARTE1, which the simulator bridges to a TCP socket the
//! mobile app's dev screen connects to. At step 6 (BLE GATT bring-up on
//! real hardware) the same frames become the notify characteristic payload
//! — this task swaps its writer, the frame layout doesn't change.

use defmt::*;
use embassy_nrf::uarte::UarteTx;
use embassy_time::{Duration, Instant, Ticker};
use watch_core::link;

use crate::state;

#[embassy_executor::task]
pub async fn run(mut tx: UarteTx<'static>) {
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut latest = None;
    let mut ticker = Ticker::every(Duration::from_secs(1));
    info!("phone: status frames on UARTE1");
    loop {
        ticker.next().await;
        if let Some(fix) = fix_rx.try_changed() {
            latest = Some(fix);
        }
        let frame = link::status_frame(latest.as_ref(), Instant::now().as_secs() as u32);
        if let Err(e) = tx.write(frame.as_bytes()).await {
            warn!("phone: uart write error {:?}", e);
        }
    }
}
