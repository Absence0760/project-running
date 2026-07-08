//! Cross-task shared state.
//!
//! The single seam between producers and consumers: the GPS task publishes
//! merged fixes here; the UI and phone-link tasks each hold a receiver.
//! Bump the receiver count when a new consumer subscribes — `Watch` hands
//! out at most `N` receivers and returns `None` past that.

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::watch::Watch;
use watch_core::fix::Fix;

pub static FIX: Watch<CriticalSectionRawMutex, Fix, 2> = Watch::new();
