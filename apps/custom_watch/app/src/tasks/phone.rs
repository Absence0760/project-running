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
//!
//! **Transmit is change-gated, with a slow liveness beacon underneath it.** The
//! task used to write a full frame on every one of its 1 Hz ticks whether or not
//! anything in the frame had moved — 3,600 UART transfers an hour, and on an
//! Expedition-mode run (one fix a minute) 59 of every 60 carrying the fix the
//! client already had. See [`HEARTBEAT_S`] for why the beacon underneath the gate
//! is load-bearing rather than a leftover tick, and [`SAMPLE`] for why the tick
//! model survives the gate at all.

#![cfg(not(feature = "ble"))]

use defmt::*;
use embassy_nrf::uarte::{UarteRx, UarteTx};
use embassy_time::{with_timeout, Duration, Instant, Ticker};
use watch_core::link;
use watch_core::settings_frame::{SettingsFramer, SettingsPush, FRAME_GAP_MS};

use crate::state;

/// Longest an attached client may see nothing at all.
///
/// A client cannot tell a link with nothing to report from a link that died, so
/// one frame goes out this often regardless of whether the data moved — it is
/// the only thing an idle link says about itself. `sim/ci_smoke.py` reads a
/// batch of frames off the bridged socket and asserts they are schema-valid and
/// that their `uptime_s` advances; with the gate above it, this beacon is what
/// keeps that true of a watch whose sensors have gone quiet. Not a redundant
/// tick: deleting it makes a silent link and a dead link identical.
const HEARTBEAT_S: u32 = 30;

/// Sampling clock for the gate.
///
/// The gate is polled on a tick rather than awaited on the two watches directly
/// because the frame's clock is `Instant::as_secs()`: an event-driven wait would
/// let a fix and an elevation reading arriving in the same second emit two
/// frames stamped with the same `uptime_s`, and a client (and
/// `sim/ci_smoke.py`) reads that sequence as strictly increasing. Ticking at the
/// clock's own resolution makes one-frame-per-second structural.
const SAMPLE: Duration = Duration::from_secs(1);

#[embassy_executor::task]
pub async fn run(mut tx: UarteTx<'static>) {
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut elev_rx = unwrap!(state::ELEVATION.receiver());
    let mut latest = None;
    let mut elev = None;
    // Latches until a frame actually carries the change, so a send deferred for
    // any reason is deferred and not dropped.
    let mut dirty = false;
    let mut sent_at_s: Option<u32> = None;
    let mut ticker = Ticker::every(SAMPLE);
    info!(
        "phone: status frames on UARTE1 (change-gated, {}s beacon)",
        HEARTBEAT_S
    );
    loop {
        ticker.next().await;
        if let Some(fix) = fix_rx.try_changed() {
            latest = Some(fix);
            dirty = true;
        }
        if let Some(reading) = elev_rx.try_changed() {
            elev = Some(reading);
            dirty = true;
        }
        let uptime_s = Instant::now().as_secs() as u32;
        let beacon_due = sent_at_s.is_none_or(|s| uptime_s.saturating_sub(s) >= HEARTBEAT_S);
        if !dirty && !beacon_due {
            continue;
        }
        // A late tick can land in the second the last frame was stamped with;
        // `dirty` is still set, so the update goes out on the next one rather
        // than as a second frame wearing the same `uptime_s`.
        if sent_at_s == Some(uptime_s) {
            continue;
        }
        let frame = link::status_frame(latest.as_ref(), elev.as_ref(), uptime_s);
        if let Err(e) = tx.write(frame.as_bytes()).await {
            warn!("phone: uart write error {:?}", e);
            continue;
        }
        dirty = false;
        sent_at_s = Some(uptime_s);
    }
}

const FRAME_GAP: Duration = Duration::from_millis(FRAME_GAP_MS);

/// Decode settings frames off the phone link's receive side and queue them on
/// `state::SETTINGS` — the same seam the BLE settings characteristic feeds,
/// so a sim push exercises the real `apply_settings` path. Every framing
/// decision lives in [`watch_core::settings_frame`]; this drives it, waiting
/// for the next byte with no gap timer armed while no frame is open.
///
/// **The one-byte reads are deliberate, and a burst buffer here would lose
/// frames.** `gps.rs` reads its UART a burst at a time (its `RX_BURST`, 32)
/// and its module doc holds that up as the wake-count lever, so this loop reads
/// as the leftover of the same anti-pattern. It is not, because of how the two
/// framings differ:
///
/// - `UarteRx::read` resolves only when the buffer is **full**. A settings frame
///   carries no length prefix (`watch_core::settings_frame`) and is almost never
///   a multiple of a burst size, so the read at a frame's end cannot complete —
///   the gap timer has to cancel it.
/// - A cancelled `read` reports **no count**. It stops the DMA and returns
///   nothing; the bytes are in the buffer but how many is only in the
///   peripheral's `RXD.AMOUNT`, which the safe API does not surface. So every
///   push whose tail is a partial burst would be silently truncated, then
///   rejected by the codec's CRC — fail-closed, but the settings pipe dead.
/// - `gps.rs` can burst *because* NMEA tolerates exactly that loss: its stream
///   always tops the buffer up, and the parser resynchronises on the next `$`.
///   A dropped sentence costs one fix. A dropped frame tail costs the push.
///
/// The API that returns a count on a short read is `read_until_idle`, and it
/// lives only on the `split_with_idle` receiver — which needs a spare TIMER + 2
/// PPI channels supplied where the UARTE is built, in `main`. That is the
/// durable fix and the only safe way to burst this pipe; until it lands, one
/// byte per read is the correct driver. Settings pushes are rare, so what the
/// byte loop costs is a few hundred wakes per push and nothing at rest — the
/// `is_empty()` branch arms no timer while no frame is open.
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
