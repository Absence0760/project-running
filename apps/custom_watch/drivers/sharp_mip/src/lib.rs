//! Driver for Sharp Memory LCD displays (LS013B4DN04 family).
//!
//! Communicates over SPI. Supports per-line updates so partial-refresh power
//! draw stays near the display's ~10 µA static current — see
//! `docs/custom_watch/performance_path.md` "Display partial updates".
//!
//! Tier 1 stub. Real implementation lands in step 4 of
//! `apps/custom_watch/README.md`. References:
//! - Sharp application note: <https://www.sharpsma.com/documents/1468207/1485624/LS013B4DN04_application+info.pdf>
//! - Adafruit C++ reference: <https://github.com/adafruit/Adafruit_SHARP_Memory_Display>

#![no_std]

// TODO step 4: define `SharpMip<SPI, CS, DISP>` struct holding the SPI bus,
// chip-select pin, and display-enable pin; implement `init`, `clear`,
// `set_pixel`, `flush_lines`. Per-line updates are the perf win.
