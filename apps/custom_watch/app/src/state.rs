//! Cross-task shared state.
//!
//! The seams between producers and consumers. Each `Watch` hands out at most
//! `N` receivers and returns `None` past that, so `N` tracks the live
//! subscriber count — bump it when a new consumer subscribes.

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::watch::Watch;
use max86177::peak_detect::Reading as HrReading;
use watch_core::fix::Fix;
use watch_core::record::Snapshot;

/// Merged GPS fixes: `gps` publishes; `ui`, `phone`, and `record` subscribe.
pub static FIX: Watch<CriticalSectionRawMutex, Fix, 3> = Watch::new();

/// Latest heart-rate estimate: `hr` publishes, the `ui` face subscribes.
pub static HR: Watch<CriticalSectionRawMutex, HrReading, 1> = Watch::new();

/// Live recording totals: `record` publishes once a second, the `ui` face
/// subscribes.
pub static RECORD: Watch<CriticalSectionRawMutex, Snapshot, 1> = Watch::new();
