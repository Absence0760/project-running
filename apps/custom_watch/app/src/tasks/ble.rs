//! BLE task — runs the GATT server, syncs completed runs to a paired phone.
//!
//! Tier 1 stub. Real implementation lands in step 6 of the README. Uses
//! `nrf-softdevice` (Nordic's BLE + ANT+ SoftDevice) which is not yet in
//! `app/Cargo.toml`'s deps — adding it requires bumping `memory.x` to leave
//! room for the SoftDevice (typically 0x27000 bytes at the bottom of flash).

use defmt::*;

#[embassy_executor::task]
pub async fn run() {
    warn!("ble::run is a stub — step 6 of apps/custom_watch/README.md");
}
