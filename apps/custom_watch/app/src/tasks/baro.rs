//! Barometer task — drives the Bosch BMP581 (per decisions.md § 90) over I²C,
//! emits pressure + altitude samples into the recording state machine.
//!
//! Tier 1 stub. Not in the README's step list explicitly; bring up after
//! HR (step 5) and before integration (step 7).

use defmt::*;

#[embassy_executor::task]
pub async fn run() {
    warn!("baro::run is a stub — bring up after step 5");
}
