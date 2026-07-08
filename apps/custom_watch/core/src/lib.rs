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
//! - [`face`] — watch-face layout: state in, text rows out
//! - [`link`] — phone-link status frames (sim transport today, BLE GATT
//!   characteristic payload at step 6)
//! - [`record`] — recording state machine: commands + fixes in, run totals out

#![cfg_attr(not(test), no_std)]

pub mod elevation;
pub mod face;
pub mod fix;
pub mod link;
pub mod record;
