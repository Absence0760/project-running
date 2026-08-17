//! Host-side tests for the part-agnostic LED auto-gain loop. Run via
//! `bin/watch-test.sh` from the repo root, or
//! `cargo test --target <HOST_TRIPLE> -p watch_core` from anywhere.
//!
//! These moved here with the code (decisions.md § 623) — they were in the
//! `max86177` crate's `driver_logic.rs` while the AGC was, and they test
//! arithmetic over DC levels that touches no register and no bus.

use watch_core::ppg::{agc_next_pa, agc_next_pa_ambient, AgcConfig, PpgScale};

/// Largest LEDx_PA register code an 8-bit current DAC can carry. The AGC clamps
/// against `cfg.max_pa`, not against this; it is here so the wrap tests exercise
/// the top of the register rather than the top of the configured window.
const LED_PA_MAX: u8 = 0xFF;

#[test]
fn dim_signal_steps_current_up() {
    let cfg = AgcConfig::BITS_19;
    let next = agc_next_pa(cfg.target_low - 50_000, 0x40, &cfg);
    assert_eq!(next, 0x40 + cfg.step, "a dim DC must raise the LED drive");
}

#[test]
fn saturating_signal_steps_current_down() {
    let cfg = AgcConfig::BITS_19;
    let next = agc_next_pa(cfg.target_high + 50_000, 0x40, &cfg);
    assert_eq!(
        next,
        0x40 - cfg.step,
        "a railing DC must lower the LED drive"
    );
}

#[test]
fn in_window_holds_the_current() {
    let cfg = AgcConfig::BITS_19;
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
    let cfg = AgcConfig::BITS_19;
    let near_max = cfg.max_pa - cfg.step / 2;
    let next = agc_next_pa(0, near_max, &cfg);
    assert_eq!(next, cfg.max_pa, "stepping up must not exceed max_pa");
}

#[test]
fn step_down_clamps_at_min() {
    let cfg = AgcConfig::BITS_19;
    let near_min = cfg.min_pa + cfg.step / 2;
    let next = agc_next_pa(u32::MAX, near_min, &cfg);
    assert_eq!(next, cfg.min_pa, "stepping down must not fall below min_pa");
}

#[test]
fn saturating_add_cannot_wrap_past_the_register() {
    let cfg = AgcConfig {
        max_pa: LED_PA_MAX,
        ..AgcConfig::BITS_19
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
    let cfg = AgcConfig::BITS_19;
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
fn rail_guard_sheds_drive_even_when_corrected_is_dim() {
    // Blinding ambient: the raw DC is past the clip guard while the corrected
    // (LED-reflected) DC reads dim. A corrected-only loop would step UP into
    // the rail; the guard must win and step DOWN — driving the LED harder into
    // an ADC near its rail only deepens the clip.
    let cfg = AgcConfig::BITS_19;
    let next = agc_next_pa_ambient(cfg.raw_ceiling + 10_000, 1_000, 0x40, &cfg);
    assert_eq!(next, 0x40 - cfg.step);
}

#[test]
fn rail_guard_clamps_at_min_pa() {
    let cfg = AgcConfig::BITS_19;
    let next = agc_next_pa_ambient(cfg.raw_ceiling + 10_000, 1_000, cfg.min_pa, &cfg);
    assert_eq!(next, cfg.min_pa, "the guard clamps at min_pa, never wraps");
}

#[test]
fn ambient_swings_below_the_ceiling_never_move_the_drive() {
    // The anti-oscillation property: with the corrected DC parked inside the
    // target band, raw-DC excursions from ambient (clouds, shade, a headlamp)
    // anywhere up to the ceiling must not walk the LED current — ambient
    // cancels out of the corrected level the band judges.
    let cfg = AgcConfig::BITS_19;
    let corrected = (cfg.target_low + cfg.target_high) / 2;
    for raw in [corrected, 350_000, 460_000, cfg.raw_ceiling] {
        assert_eq!(
            agc_next_pa_ambient(raw, corrected, 0x40, &cfg),
            0x40,
            "raw {raw} at/below the ceiling must hold the drive"
        );
    }
}

#[test]
fn ambient_loop_converges_and_holds_under_steady_ambient() {
    // Closed-loop model with a large but sub-rail ambient bleed: raw = ambient
    // + gain*pa, corrected = gain*pa. Starting over-driven (raw past the
    // ceiling), the guard walks the drive down until conversion headroom is
    // back, the band then finishes the job, and the settled point holds — the
    // whole-loop anti-oscillation guarantee of `converges_into_the_window_and_
    // holds`, under ambient.
    let cfg = AgcConfig::BITS_19;
    let ambient = 150_000u32;
    let gain = 3_000u32;
    let mut pa = cfg.max_pa;

    for _ in 0..256 {
        let corrected = u32::from(pa) * gain;
        pa = agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg);
    }

    let settled = pa;
    let corrected = u32::from(settled) * gain;
    assert!(
        corrected >= cfg.target_low && corrected <= cfg.target_high,
        "loop must settle the corrected DC inside the window, got {corrected} at pa {settled}"
    );
    assert!(
        ambient + corrected <= cfg.raw_ceiling,
        "the settled raw level must respect the ceiling"
    );

    for _ in 0..32 {
        let corrected = u32::from(pa) * gain;
        pa = agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg);
        assert_eq!(pa, settled, "a settled ambient loop must not oscillate");
    }
}

#[test]
fn blinding_ambient_walks_to_the_floor_and_stays() {
    // Ambient alone far past the ceiling, whatever the LED does: the loop must
    // walk the drive to min_pa and hold — the honest floor while the peak
    // detector reports Saturated. It must never bounce back up against the dim
    // corrected read that scene produces.
    let cfg = AgcConfig::BITS_19;
    let ambient = 520_000u32;
    let gain = 500u32;
    let mut pa = 0x40;
    for _ in 0..64 {
        let corrected = u32::from(pa) * gain;
        pa = agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg);
    }
    assert_eq!(pa, cfg.min_pa);
    let corrected = u32::from(pa) * gain; // dim — unguarded, this would step up
    assert_eq!(
        agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg),
        cfg.min_pa
    );
}

/// The invariant `AgcConfig::for_scale` exists to preserve, checked at both
/// widths rather than argued from proportionality: the auto-gain loop must shed
/// LED drive *before* the detector gives up on the read. If `raw_ceiling` ever
/// crossed `raw_rail_dc`, the detector would declare `Saturated` on a scene the
/// loop still believed it could brighten its way out of.
#[test]
fn agc_sheds_drive_before_the_detector_declares_a_rail() {
    for (agc, scale, name) in [
        (AgcConfig::BITS_19, PpgScale::BITS_19, "19-bit"),
        (AgcConfig::BITS_18, PpgScale::BITS_18, "18-bit"),
    ] {
        assert!(
            (agc.raw_ceiling as i32) < scale.raw_rail_dc,
            "{name}: AGC ceiling {} must sit below the detector's rail {}",
            agc.raw_ceiling,
            scale.raw_rail_dc,
        );
        // And the brightness window has to sit under the ceiling, or the loop
        // would chase a target it is simultaneously guarding against.
        assert!(
            agc.target_high < agc.raw_ceiling,
            "{name}: window under ceiling"
        );
        assert!(
            agc.target_low < agc.target_high,
            "{name}: window is ordered"
        );
    }
}

/// A rescale moves the DC bounds and leaves the drive codes alone. An LED
/// current code addresses the part's current DAC, not its converter, so
/// scaling one with the other would silently re-tune the drive when only the
/// ADC width changed.
#[test]
fn rescaling_moves_dc_bounds_and_not_drive_codes() {
    let a = AgcConfig::BITS_19;
    let b = AgcConfig::BITS_18;

    assert!(b.target_low < a.target_low);
    assert!(b.target_high < a.target_high);
    assert!(b.raw_ceiling < a.raw_ceiling);

    assert_eq!(b.step, a.step);
    assert_eq!(b.min_pa, a.min_pa);
    assert_eq!(b.max_pa, a.max_pa);
}

/// Halving the converter width halves the counts a given optical scene
/// produces, so every DC bound must halve with it — to within the deliberate
/// downward rounding. Pinned as a ratio so the relationship survives a retune
/// of the 19-bit reference.
#[test]
fn eighteen_bit_bounds_are_half_the_nineteen_bit_ones() {
    let a = PpgScale::BITS_19;
    let b = PpgScale::BITS_18;

    // 0x3_FFFF / 0x7_FFFF is a hair under one half, and the rescale floors.
    for (wide, narrow, name) in [
        (a.contact_dc_min, b.contact_dc_min, "contact_dc_min"),
        (a.contact_dc_max, b.contact_dc_max, "contact_dc_max"),
        (a.raw_rail_dc, b.raw_rail_dc, "raw_rail_dc"),
        (a.min_envelope, b.min_envelope, "min_envelope"),
    ] {
        let half = wide / 2;
        assert!(
            narrow <= half && narrow >= half - 1,
            "{name}: {narrow} should be the floor of half {wide}",
        );
    }
}
