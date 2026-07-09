//! GPS task — reads NMEA from the u-blox MAX-M10S over UARTE0, parses
//! sentences, and publishes merged fixes to `state::FIX`.
//!
//! Thin glue by design: byte assembly + parsing live in `ublox_nmea`,
//! RMC/GGA merging in `watch_core::fix` — both host-tested. This task only
//! moves bytes from the peripheral into those modules.
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

use defmt::{debug, info, warn};
use embassy_nrf::uarte::UarteRx;
use embassy_time::{Duration, Instant, Timer};
use ublox_nmea::Parser;
use watch_core::fix::FixAccumulator;

use crate::state;

/// Burst-read size. Small enough to bound the tail latency (a partly-filled
/// buffer waits for the next bytes to top it off) while cutting UART wakes ~30x
/// versus one byte per read at 9600 baud. The parser is byte-stateful, so a
/// sentence split across two reads is fine.
const RX_BURST: usize = 32;

#[embassy_executor::task]
pub async fn run(mut rx: UarteRx<'static>) {
    let mut parser = Parser::new();
    let mut acc = FixAccumulator::new();
    let sender = state::FIX.sender();
    let mut buf = [0u8; RX_BURST];
    info!("gps: listening on UARTE0");
    loop {
        match rx.read(&mut buf).await {
            Ok(()) => {
                for &b in &buf {
                    let Some(sentence) = parser.feed(b) else {
                        continue;
                    };
                    let uptime_s = Instant::now().as_secs() as u32;
                    if let Some(fix) = acc.apply(&sentence, uptime_s) {
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
