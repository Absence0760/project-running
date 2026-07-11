//! Host-testable widget drawing for the watch face.
//!
//! The `app` ui task decides *when* to draw and owns the panel peripheral; the
//! pure geometry of *where* each gauge, bar, signal meter, and page indicator
//! lands on the 168x144 grid lives here, over a plain [`sharp_mip::Framebuffer`]
//! and [`watch_core`] state. That keeps the visual layer under `cargo test`
//! (see [`widgets`] tests + the [`preview`] ASCII dumper) instead of only
//! reachable on a board.
//!
//! Everything is `no_std` so the same code links into the firmware; the tests
//! opt back into `std` the usual way.

#![cfg_attr(not(test), no_std)]

pub mod widgets;

#[cfg(test)]
mod preview;
