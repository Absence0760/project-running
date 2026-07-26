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
//!
//! The whole module is therefore compiled out of the `ble` build: `main` only
//! spawns these tasks under `not(feature = "ble")`, so under `ble` every item
//! here is unreachable and the dead-code lint fires on the first one it can
//! see.

#![cfg(not(feature = "ble"))]

use defmt::*;
use embassy_nrf::uarte::{UarteRx, UarteTx};
use embassy_time::{with_timeout, Duration, Instant, Ticker};
use watch_core::link;
use watch_core::settings_frame::{SettingsFramer, SettingsPush, FRAME_GAP_MS};

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

const FRAME_GAP: Duration = Duration::from_millis(FRAME_GAP_MS);

/// Decode settings frames off the phone link's receive side and queue them on
/// `state::SETTINGS` — the same seam the BLE settings characteristic feeds,
/// so a sim push exercises the real `apply_settings` path. Every framing
/// decision lives in [`watch_core::settings_frame`]; this drives it, waiting
/// for the next byte with no gap timer armed while no frame is open.
#[embassy_executor::task]
pub async fn settings_rx(mut rx: UarteRx<'static>) {
    let mut framer = SettingsFramer::new();
    info!("phone: settings frames accepted on UARTE1 rx");
    loop {
        let mut byte = [0u8; 1];
        if framer.is_empty() {
            if rx.read(&mut byte).await.is_ok() {
                framer.push(&byte);
            }
            continue;
        }
        match with_timeout(FRAME_GAP, rx.read(&mut byte)).await {
            Ok(Ok(())) => framer.push(&byte),
            Ok(Err(e)) => {
                warn!("phone: uart read error {:?}", e);
                framer.reset();
            }
            Err(_) => match framer.on_gap() {
                SettingsPush::Empty => {}
                SettingsPush::Oversize => warn!("phone: oversize settings push discarded"),
                SettingsPush::Rejected { len } => {
                    warn!("phone: settings frame rejected ({=usize} bytes)", len)
                }
                SettingsPush::Applied { settings, len } => {
                    info!("phone: settings frame applied ({=usize} bytes)", len);
                    if state::SETTINGS.try_send(settings).is_err() {
                        warn!("phone: settings queue full, push refused");
                    }
                }
            },
        }
    }
}
