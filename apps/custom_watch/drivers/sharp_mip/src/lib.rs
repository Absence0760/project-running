//! Driver for Sharp Memory LCD displays (LS013B4DN04 family, 168x144).
//!
//! Layered so everything above the SPI bus is host-testable:
//!
//! - [`font`] — generated 8x16 ASCII bitmap table (see `scripts/gen_font.py`)
//! - [`framebuffer`] — pixel + text-cell drawing with per-line dirty tracking
//! - [`display`] — the wire protocol: encodes dirty lines into the panel's
//!   line-update packets over an `embedded-hal` SPI bus
//!
//! Per-line updates are the perf win: static draw stays near the panel's
//! ~10 uA while only changed lines cost SPI traffic — see
//! `docs/custom_watch/performance_path.md` "Display partial updates".
//!
//! References:
//! - Sharp application note: <https://www.sharpsma.com/documents/1468207/1485624/LS013B4DN04_application+info.pdf>
//! - Adafruit C++ reference: <https://github.com/adafruit/Adafruit_SHARP_Memory_Display>

#![no_std]

pub mod display;
pub mod font;
pub mod framebuffer;
pub mod icons;

pub use display::SharpMip;
pub use framebuffer::{Framebuffer, HEIGHT, LINE_BYTES, TEXT_COLS, TEXT_ROWS, WIDTH};
pub use icons::{Icon, ICON_BYTES_PER_ROW, ICON_SIZE};
