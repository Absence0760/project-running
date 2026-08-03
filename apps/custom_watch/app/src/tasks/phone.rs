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
use embassy_nrf::uarte::{UarteRxWithIdle, UarteTx};
use embassy_time::{with_timeout, Duration, Instant, Ticker};
use watch_core::ble_sync::PushKind;
use watch_core::link;
use watch_core::settings::MAX_SETTINGS_LEN;
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
/// for the next chunk with no gap timer armed while no frame is open.
///
/// **Two idle detectors, and they are not the same thing.** The receiver is the
/// `Uarte::split_with_idle` half (`main` supplies its TIMER + PPI pair), so a
/// read ends at the *hardware* idle window and reports how many bytes landed.
/// That count is the whole reason a burst buffer is usable here: plain
/// `UarteRx::read` resolves only on a **full** buffer and returns no count, and
/// a settings frame carries no length prefix and is almost never a round number
/// of bytes — so it could only be ended by cancelling the read, which discards
/// the count along with the tail of nearly every push. `gps.rs` can burst
/// without a count because NMEA tops the buffer up and resynchronises on the
/// next `$`; a settings frame cannot. See decisions.md § 407.
///
/// The frame *boundary* is still the [`FRAME_GAP`] software timeout, and that is
/// not scaffolding left from the old design. `with_idle` fixes its window at two
/// byte-times — ~174 µs at this link's 115200 baud — and offers no way to widen
/// it, so a hardware-idle read means "the sender paused" — ~575x short of the
/// 100 ms that `watch_core::settings_frame` defines a push boundary as. Closing
/// the frame on every short read would split one push
/// into rejected fragments the first time a sender stalls mid-frame, which is
/// exactly why `SettingsFramer::push` takes a slice rather than a byte.
///
/// What the hardware detector changes is the cost of that timeout firing. It
/// used to cancel a read on every single frame; now it can only fire after
/// 100 ms of silence, by which point the hardware has already handed over every
/// byte that arrived, ~174 µs after the last one. The only bytes a cancel can
/// still lose are ones landing inside that final window — and since the timeout
/// is armed only while a frame is open, that needs a second push starting within
/// ~174 µs of the previous one's boundary. It stays fail-closed either way: the
/// codec's CRC refuses the short frame rather than applying a partial one.
#[embassy_executor::task]
pub async fn settings_rx(mut rx: UarteRxWithIdle<'static>) {
    let mut framer = SettingsFramer::new();
    let mut buf = [0u8; MAX_SETTINGS_LEN];
    info!("phone: settings frames accepted on UARTE1 rx");
    loop {
        if framer.is_empty() {
            match rx.read_until_idle(&mut buf).await {
                Ok(n) => framer.push(&buf[..n]),
                Err(e) => warn!("phone: uart read error {:?}", e),
            }
            continue;
        }
        match with_timeout(FRAME_GAP, rx.read_until_idle(&mut buf)).await {
            Ok(Ok(n)) => framer.push(&buf[..n]),
            Ok(Err(e)) => {
                warn!("phone: uart read error {:?}", e);
                framer.reset();
            }
            // Every non-empty outcome funnels through `state::note_push`, the
            // same seam the radio task's five characteristics use — the sim's
            // UART transport refuses a settings push exactly as the radio
            // does, and the wearer must be told either way. `Empty` is not an
            // outcome: no frame arrived, so nothing was refused.
            Err(_) => match framer.on_gap() {
                SettingsPush::Empty => {}
                SettingsPush::Oversize => {
                    warn!("phone: oversize settings push discarded");
                    state::note_push(PushKind::Settings, false);
                }
                SettingsPush::Rejected { len } => {
                    warn!("phone: settings frame rejected ({=usize} bytes)", len);
                    state::note_push(PushKind::Settings, false);
                }
                SettingsPush::Applied { settings, len } => {
                    info!("phone: settings frame applied ({=usize} bytes)", len);
                    match state::SETTINGS.try_send(settings) {
                        Ok(()) => {
                            state::note_push(PushKind::Settings, true);
                        }
                        Err(_) => {
                            warn!("phone: settings queue full, push refused");
                            state::note_push(PushKind::Settings, false);
                        }
                    }
                }
            },
        }
    }
}
