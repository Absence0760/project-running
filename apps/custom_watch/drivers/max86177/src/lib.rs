//! Driver for Maxim MAX86177 optical heart-rate AFE.
//!
//! Tier 1 only exposes raw photodiode reads — `cargo test` covers any pure-
//! logic processing (filtering, naive peak-detect). The licensed Maxim HR
//! algorithm is C and gets pulled in via `bindgen` post-tier-1; see
//! `docs/architecture/decisions.md` § 80 ("Trade-offs we accept") for the FFI budget.
//!
//! Tier 1 stub. Real implementation lands in step 5 of
//! `apps/custom_watch/README.md`.

#![no_std]

// TODO step 5: define `Max86177<I2C>` driver with `init`, `read_sample` over
// I²C. Naive peak-detect goes in a sibling pure-logic module (host-testable)
// that consumes raw samples and emits BPM.
