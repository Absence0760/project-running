//! Host-side tests for the driver's pure register-logic helpers: the LED-current
//! auto-gain step and the internal die-temperature decode. Run via
//! `bin/watch-test.sh` from the repo root, or `cargo test --target <HOST_TRIPLE>
//! -p max86177` from anywhere. These touch no peripheral, only the integer math
//! that decides a register value.

use max86177::{agc_next_pa, decode_die_temp_milli_c, AgcConfig, LED_PA_MAX};

#[test]
fn dim_signal_steps_current_up() {
    let cfg = AgcConfig::default();
    let next = agc_next_pa(cfg.target_low - 50_000, 0x40, &cfg);
    assert_eq!(next, 0x40 + cfg.step, "a dim DC must raise the LED drive");
}

#[test]
fn saturating_signal_steps_current_down() {
    let cfg = AgcConfig::default();
    let next = agc_next_pa(cfg.target_high + 50_000, 0x40, &cfg);
    assert_eq!(
        next,
        0x40 - cfg.step,
        "a railing DC must lower the LED drive"
    );
}

#[test]
fn in_window_holds_the_current() {
    let cfg = AgcConfig::default();
    let mid = (cfg.target_low + cfg.target_high) / 2;
    assert_eq!(
        agc_next_pa(mid, 0x40, &cfg),
        0x40,
        "a DC inside the target band must not move the drive"
    );
    assert_eq!(
        agc_next_pa(cfg.target_low, 0x40, &cfg),
        0x40,
        "the low edge is inside the band"
    );
    assert_eq!(
        agc_next_pa(cfg.target_high, 0x40, &cfg),
        0x40,
        "the high edge is inside the band"
    );
}

#[test]
fn step_up_clamps_at_max() {
    let cfg = AgcConfig::default();
    let near_max = cfg.max_pa - cfg.step / 2;
    let next = agc_next_pa(0, near_max, &cfg);
    assert_eq!(next, cfg.max_pa, "stepping up must not exceed max_pa");
}

#[test]
fn step_down_clamps_at_min() {
    let cfg = AgcConfig::default();
    let near_min = cfg.min_pa + cfg.step / 2;
    let next = agc_next_pa(u32::MAX, near_min, &cfg);
    assert_eq!(next, cfg.min_pa, "stepping down must not fall below min_pa");
}

#[test]
fn saturating_add_cannot_wrap_past_the_register() {
    let cfg = AgcConfig {
        max_pa: LED_PA_MAX,
        ..AgcConfig::default()
    };
    let next = agc_next_pa(0, LED_PA_MAX - 1, &cfg);
    assert_eq!(
        next, LED_PA_MAX,
        "a near-full code must saturate, not wrap to 0"
    );
}

#[test]
fn converges_into_the_window_and_holds() {
    // A simple monotone optical model: DC scales with the drive code. Closing the
    // loop must walk the drive until the DC lands inside the band and then leave
    // it there forever — the anti-oscillation guarantee, not just a single step.
    let cfg = AgcConfig::default();
    let gain = 3_000u32;
    let mut pa = cfg.min_pa;

    for _ in 0..256 {
        let dc = u32::from(pa) * gain;
        pa = agc_next_pa(dc, pa, &cfg);
    }

    let settled = pa;
    let dc = u32::from(settled) * gain;
    assert!(
        dc >= cfg.target_low && dc <= cfg.target_high,
        "loop must settle inside the window, got dc {dc} at pa {settled}"
    );

    for _ in 0..32 {
        let dc = u32::from(pa) * gain;
        pa = agc_next_pa(dc, pa, &cfg);
        assert_eq!(pa, settled, "a settled loop must not oscillate");
    }
}

#[test]
fn decode_temp_whole_degrees() {
    assert_eq!(decode_die_temp_milli_c(25, 0), 25_000);
    assert_eq!(decode_die_temp_milli_c(37, 0), 37_000);
}

#[test]
fn decode_temp_fractional_bits() {
    assert_eq!(decode_die_temp_milli_c(25, 8), 25_500, "8/16 = 0.5 degC");
    assert_eq!(decode_die_temp_milli_c(37, 4), 37_250, "4/16 = 0.25 degC");
    assert_eq!(
        decode_die_temp_milli_c(36, 15),
        36_938,
        "15/16 = 0.9375 degC, rounded to milli"
    );
}

#[test]
fn decode_temp_ignores_upper_frac_bits() {
    // Only the low nibble of TEMP_FRAC is the fraction; reserved upper bits set
    // must not leak into the reading.
    assert_eq!(
        decode_die_temp_milli_c(20, 0xF8),
        decode_die_temp_milli_c(20, 0x08)
    );
}

#[test]
fn decode_temp_negative() {
    // Two's-complement whole part with a positive added fraction: -6 + 8/16.
    assert_eq!(decode_die_temp_milli_c(0xFA, 8), -5_500);
    assert_eq!(decode_die_temp_milli_c(0xFF, 0), -1_000);
}

#[test]
fn decode_temp_smallest_step() {
    assert_eq!(
        decode_die_temp_milli_c(0, 1),
        63,
        "1/16 = 0.0625 degC -> 63 milli"
    );
}
