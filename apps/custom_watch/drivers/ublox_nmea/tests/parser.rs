//! Host-side parser tests. Run via `bin/watch-test.sh` from the repo root,
//! or `cargo test --target <HOST_TRIPLE> -p ublox_nmea` from anywhere.

#[test]
fn placeholder_remove_when_parser_lands() {
    // TODO step 3: replace with real test cases against captured NMEA fixtures.
    // Suggested fixtures: cold start, hot start, lost-fix, multi-band burst,
    // GSV satellite-in-view sweep, malformed sentence (checksum mismatch).
}
