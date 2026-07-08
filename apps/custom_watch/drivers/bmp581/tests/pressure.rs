//! Host-side conversion tests. Run via `bin/watch-test.sh` from the repo root,
//! or `cargo test --target <HOST_TRIPLE> -p bmp581` from anywhere.

use bmp581::raw_to_pa;

fn approx(a: f32, b: f32, tol: f32) -> bool {
    (a - b).abs() <= tol
}

#[test]
fn sea_level_pressure() {
    // 101325 Pa * 64 counts/Pa = 6_484_800 raw.
    assert!(approx(raw_to_pa(6_484_800), 101_325.0, 0.01));
}

#[test]
fn zero_reads_zero() {
    assert_eq!(raw_to_pa(0), 0.0);
}

#[test]
fn high_altitude_low_pressure() {
    // ~9 km up, roughly 30 kPa: 30000 Pa * 64 = 1_920_000 raw.
    assert!(approx(raw_to_pa(1_920_000), 30_000.0, 0.01));
}

#[test]
fn one_count_is_a_sixty_fourth_pa() {
    assert!(approx(raw_to_pa(6_484_801), 101_325.015_625, 0.001));
}

#[test]
fn full_scale_24bit() {
    assert!(approx(raw_to_pa(0x00FF_FFFF), 262_143.98, 0.05));
}
