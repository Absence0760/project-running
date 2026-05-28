//! HR task — drives the Maxim MAX86177 optical-HR AFE over I²C, runs the
//! peak-detect pipeline, emits `HeartRate` events.
//!
//! Tier 1 stub. Real implementation lands in step 5 of the README. The
//! licensed Maxim HR algorithm is pulled in via `bindgen` post-tier-1;
//! tier-1 uses a naive peak-detect that's host-testable in
//! `drivers/max86177/`.

use defmt::*;

#[embassy_executor::task]
pub async fn run() {
    warn!("hr::run is a stub — step 5 of apps/custom_watch/README.md");
}
