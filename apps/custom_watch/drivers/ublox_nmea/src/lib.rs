//! Streaming NMEA-0183 parser for u-blox MAX-M10S output.
//!
//! `no_std`, no allocations — feeds bytes from a UART buffer and emits parsed
//! `Sentence` enums. Designed for host testability: the parser itself doesn't
//! touch peripherals, so `bin/watch-test.sh` (which excludes embedded-only
//! crates) covers it without a board.
//!
//! Tier 1 stub. Real implementation lands in step 3 of
//! `apps/custom_watch/README.md`. Sentences we care about for the watch:
//! - `$GPRMC` — fix + speed + course
//! - `$GPGGA` — fix quality + altitude
//! - `$GPGSV` — satellites in view (for signal-quality debug)

#![no_std]

// TODO step 3: define `Parser` with a byte-level feed API; emit `Sentence`
// variants for at least RMC / GGA / GSV. Add #[test] cases for each sentence
// type against captured NMEA fixtures in `tests/`.
