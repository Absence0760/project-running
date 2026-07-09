//! GPS task — reads NMEA from the u-blox MAX-M10S over UARTE0, parses
//! sentences, and publishes merged fixes to `state::FIX`.
//!
//! Thin glue by design: byte assembly + parsing live in `ublox_nmea`,
//! RMC/GGA merging in `watch_core::fix` — both host-tested. This task only
//! moves bytes from the peripheral into those modules.
//!
//! Publication is **de-rated while no run is active**: idle fixes are forwarded
//! at most once per [`IDLE_FIX_MIN_INTERVAL_S`] rather than every ~1 s, so a
//! standing wrist stops waking the UI / record / phone consumers each second for
//! a position nobody is recording. A run (`state::RECORD` Recording/Paused) lifts
//! the throttle and gets every fix. This is the software half of GPS
//! duty-cycling; powering the GNSS module down between fixes is the separate,
//! hardware-gated tier-2 win.
//!
//! Reads are burst-DMA: the UARTE fills an [`RX_BURST`]-byte buffer over
//! EasyDMA and wakes the CPU once per buffer, not once per byte. A
//! byte-at-a-time loop woke the executor hundreds of times a second at 9600
//! baud; the burst read is the same data for a fraction of the active-CPU
//! time — the DMA-not-polling lever in `docs/custom_watch/performance_path.md`,
//! which ports straight to tier-2. (The further refinement is idle-line
//! detection via `split_with_idle` so a buffer never waits on the next burst to
//! fill; it needs a free TIMER + 2 PPI channels and can't be Renode-verified,
//! so it's a tier-2 profiling item, not a bench-prototype one.)

use defmt::{debug, info, unwrap, warn};
use embassy_nrf::uarte::UarteRx;
use embassy_time::{Duration, Instant, Timer};
use ublox_nmea::Parser;
use watch_core::face::STALE_AFTER_S;
use watch_core::fix::FixAccumulator;
use watch_core::record::RecordState;

use crate::state;

/// Burst-read size. Small enough to bound the tail latency (a partly-filled
/// buffer waits for the next bytes to top it off) while cutting UART wakes ~30x
/// versus one byte per read at 9600 baud. The parser is byte-stateful, so a
/// sentence split across two reads is fine.
const RX_BURST: usize = 32;

/// While no run is active, forward at most one fix per this interval instead of
/// every ~1 s fix. A moving (or slowly drifting) idle position otherwise wakes
/// the UI, record, and phone consumers every second for a view nobody is acting
/// on — the "de-rate the display when not recording" half of GPS duty-cycling.
/// Held one second under the face's `STALE_AFTER_S` freshness budget so the idle
/// status face still shows a locked fix as fresh; a longer gap would flip it to
/// the "searching" state even though GNSS has a lock. Powering the GNSS module
/// itself down between fixes is the separate, hardware-gated tier-2 win (README
/// power discipline) — this cuts only the downstream wakes, not the UART stream.
const IDLE_FIX_MIN_INTERVAL_S: u32 = STALE_AFTER_S - 1;

/// Full-rate fixes are only needed while a run consumes them — Recording, and
/// Paused (an auto-pause resumes off the next moving fix, so it must see them).
fn run_active(state: RecordState) -> bool {
    matches!(state, RecordState::Recording | RecordState::Paused)
}

#[embassy_executor::task]
pub async fn run(mut rx: UarteRx<'static>) {
    let mut parser = Parser::new();
    let mut acc = FixAccumulator::new();
    let sender = state::FIX.sender();
    let mut rec_rx = unwrap!(state::RECORD.receiver());
    let mut buf = [0u8; RX_BURST];
    let mut active = false;
    let mut last_published_s: u32 = 0;
    info!("gps: listening on UARTE0");
    loop {
        // Pick up run start/stop without blocking on it; buffers arrive every
        // few tens of ms while the GNSS streams, so a state change is observed
        // well within a fix interval.
        if let Some(snap) = rec_rx.try_changed() {
            active = run_active(snap.state);
        }
        match rx.read(&mut buf).await {
            Ok(()) => {
                for &b in &buf {
                    let Some(sentence) = parser.feed(b) else {
                        continue;
                    };
                    let uptime_s = Instant::now().as_secs() as u32;
                    if let Some(fix) = acc.apply(&sentence, uptime_s) {
                        // De-rate while idle; a run always gets every fix.
                        if !active
                            && uptime_s.saturating_sub(last_published_s) < IDLE_FIX_MIN_INTERVAL_S
                        {
                            continue;
                        }
                        last_published_s = uptime_s;
                        debug!(
                            "gps: fix lat={} lon={} speed={} sats={}",
                            fix.lat_deg, fix.lon_deg, fix.speed_mps, fix.sats
                        );
                        sender.send(fix);
                    }
                }
            }
            Err(e) => {
                warn!("gps: uart read error {:?}, backing off", e);
                Timer::after(Duration::from_millis(100)).await;
            }
        }
    }
}
