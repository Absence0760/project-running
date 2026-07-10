//! Per-subsystem async tasks.
//!
//! Each module corresponds to one slice of the watch's behaviour. They run
//! concurrently under the Embassy executor. At tier 1 most are stubs; the
//! intent is that each can be developed + tested in isolation before being
//! integrated by `record.rs`.

pub mod baro;
pub mod ble;
pub mod button;
pub mod gps;
pub mod hr;
pub mod nav;
pub mod phone;
pub mod record;
pub mod ui;
