//! GPS task — reads NMEA from the u-blox MAX-M10S over UARTE0, parses
//! sentences, and publishes merged fixes to `state::FIX`.
//!
//! Thin glue by design: byte assembly + parsing live in `ublox_nmea`,
//! RMC/GGA merging in `watch_core::fix` — both host-tested. This task only
//! moves bytes from the peripheral into those modules.
//!
//! Reads are one byte per EasyDMA transfer. At NMEA rates (couple hundred
//! bytes/s) that's negligible bus traffic, and it sidesteps needing the
//! TIMER+PPI idle-line trick for variable-length reads; revisit with
//! `read_until_idle` if tier-2 profiling ever shows this task mattering.

use defmt::{debug, info, warn};
use embassy_nrf::uarte::UarteRx;
use embassy_time::{Duration, Instant, Timer};
use ublox_nmea::Parser;
use watch_core::fix::FixAccumulator;

use crate::state;

#[embassy_executor::task]
pub async fn run(mut rx: UarteRx<'static>) {
    let mut parser = Parser::new();
    let mut acc = FixAccumulator::new();
    let sender = state::FIX.sender();
    let mut byte = [0u8; 1];
    info!("gps: listening on UARTE0");
    loop {
        match rx.read(&mut byte).await {
            Ok(()) => {
                let Some(sentence) = parser.feed(byte[0]) else {
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
            Err(e) => {
                warn!("gps: uart read error {:?}, backing off", e);
                Timer::after(Duration::from_millis(100)).await;
            }
        }
    }
}
