//! Phone-link task — streams `watch_core::link` status frames over UARTE1,
//! which the simulator bridges to a TCP socket the mobile app's dev screen
//! connects to.
//!
//! This is the default / sim transport. On real hardware the `ble` feature
//! (README step 6) carries the SAME frames over a GATT notify characteristic
//! instead (`tasks::ble`), and `main` spawns that task in place of this one —
//! the frame layout is identical, only the pipe differs. The pipe is
//! two-directional: [`settings_rx`] decodes `SET1` settings frames written
//! into the socket — the sim twin of the BLE settings characteristic — so a
//! settings push is provable end-to-end with no hardware attached.

use defmt::*;
use embassy_nrf::uarte::{UarteRx, UarteTx};
use embassy_time::{with_timeout, Duration, Instant, Ticker};
use watch_core::link;
use watch_core::settings::{WatchSettings, MAX_SETTINGS_LEN};

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

/// An idle gap on the pipe marks a frame boundary: the TCP bridge delivers a
/// pushed frame's bytes back-to-back, so anything slower is a new push.
const FRAME_GAP: Duration = Duration::from_millis(100);

/// Decode settings frames off the phone link's receive side and publish them
/// to `state::SETTINGS` — the same seam the BLE settings characteristic feeds,
/// so a sim push exercises the real `apply_settings` path. Framing rides the
/// idle gap rather than duplicating the wire layout here: bytes accumulate
/// until the pipe pauses, then the whole buffer must decode (the codec's
/// fail-closed rules — bad magic, unknown bits, trailing bytes — all reject)
/// or the push is dropped with a log line.
#[embassy_executor::task]
pub async fn settings_rx(mut rx: UarteRx<'static>) {
    let sender = state::SETTINGS.sender();
    let mut buf = [0u8; MAX_SETTINGS_LEN];
    let mut len = 0usize;
    let mut overflow = false;
    info!("phone: settings frames accepted on UARTE1 rx");
    loop {
        let mut byte = [0u8; 1];
        if len == 0 {
            if rx.read(&mut byte).await.is_err() {
                continue;
            }
            buf[0] = byte[0];
            len = 1;
            continue;
        }
        match with_timeout(FRAME_GAP, rx.read(&mut byte)).await {
            Ok(Ok(())) => {
                if len == buf.len() {
                    overflow = true;
                } else {
                    buf[len] = byte[0];
                    len += 1;
                }
            }
            Ok(Err(e)) => {
                warn!("phone: uart read error {:?}", e);
                len = 0;
                overflow = false;
            }
            Err(_) => {
                if overflow {
                    warn!("phone: oversize settings push discarded");
                } else {
                    match WatchSettings::decode(&buf[..len]) {
                        Some(s) => {
                            info!("phone: settings frame applied ({=usize} bytes)", len);
                            sender.send(Some(s));
                        }
                        None => {
                            warn!("phone: settings frame rejected ({=usize} bytes)", len);
                        }
                    }
                }
                len = 0;
                overflow = false;
            }
        }
    }
}
