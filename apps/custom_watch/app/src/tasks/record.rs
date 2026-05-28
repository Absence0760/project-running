//! Recording state machine — port of the Dart `run_recorder` to async Rust.
//!
//! Consumes Fix / HeartRate / Altitude / Button events from the other tasks,
//! tracks the (idle → recording → paused → finished) state, persists the
//! GPS track to LittleFS, hands completed runs to the BLE sync task.
//!
//! Tier 1 stub. Real implementation lands in step 7 of the README. The
//! state-machine logic should live in a sibling host-testable crate
//! (`drivers/record/` or similar) so it can be exercised by `cargo test`
//! without a board — that's the firmware-architecture rule from
//! `docs/custom_watch/performance_path.md` ("60-70% host-testable").

use defmt::*;

#[embassy_executor::task]
pub async fn run() {
    warn!("record::run is a stub — step 7 of apps/custom_watch/README.md");
}
