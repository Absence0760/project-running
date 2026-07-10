//! Hardware-free application core for the watch firmware.
//!
//! Everything in this crate is pure logic over plain data: no peripherals,
//! no Embassy, no allocator. The `app/` crate's async tasks are thin glue
//! that move bytes between peripherals and these modules, which keeps the
//! 60-70% host-testable split that `local_testing.md` calls for and means
//! the same core ports unchanged to tier-2 silicon (decisions.md § 90).
//!
//! - [`fix`] — the GPS fix domain model + the RMC/GGA accumulator
//! - [`elevation`] — barometric altitude + the cumulative-vert accumulator
//! - [`grade_adjusted_pace`] — the Minetti GAP model (fourth parity port) +
//!   the streaming grade estimator the recorder feeds
//! - [`face`] — watch-face layout: state in, text rows out
//! - [`page`] — which run-view screen shows + the page-button cycle order
//! - [`link`] — phone-link status frames (sim transport today, BLE GATT
//!   characteristic payload at step 6)
//! - [`record`] — recording state machine: commands + fixes in, run totals out
//! - [`button`] — the pure button-press → record-command mapping
//! - [`run_store`] — on-device run wire format + BLE sync framing
//! - [`flash_store`] — tier-1 internal-flash slot layout for finished runs

#![cfg_attr(not(test), no_std)]

pub mod button;
pub mod elevation;
pub mod face;
pub mod fix;
pub mod flash_store;
pub mod grade_adjusted_pace;
pub mod link;
pub mod page;
pub mod record;
pub mod run_store;
