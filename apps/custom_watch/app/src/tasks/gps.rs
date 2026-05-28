//! GPS task — reads NMEA from u-blox MAX-M10S over UART, parses fixes, emits
//! `Fix` events into the recording state machine.
//!
//! Tier 1 stub. Real implementation lands in step 3 of the README:
//! - bring up UART RX from the GPS breakout
//! - feed bytes into `ublox_nmea::Parser`
//! - emit parsed fixes into a channel consumed by `record.rs`

use defmt::*;

#[embassy_executor::task]
pub async fn run() {
    warn!("gps::run is a stub — step 3 of apps/custom_watch/README.md");
}
