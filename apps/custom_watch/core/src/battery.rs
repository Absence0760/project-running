//! 1S LiPo supply voltage → remaining-charge percent.
//!
//! The app's `battery` task samples the supply rail through the SAADC's
//! internal VDD channel and feeds the millivolts here; the idle faces render
//! the result as a gauge icon (and the diagnostics face as a `BAT n%` row).
//! Pure and host-tested — the task owns the sampling cadence and the
//! plausibility park, this module owns the mapping.
//!
//! The map is piecewise-linear over published 1S LiPo resting-discharge
//! anchors rather than a straight 3.3–4.2 V line: a LiPo's discharge curve is
//! flat through the 3.7–3.9 V plateau and cliffs at both ends, so a linear
//! map would misread a mid-run cell by ~15–20 points. Even so the percent is
//! a bench estimate, not a fuel gauge — the anchors are rest voltages and a
//! cell under load sags below them.

/// `(millivolts, percent)` anchor points, strictly ascending on both axes,
/// from published 1S LiPo resting state-of-charge tables. First entry is the
/// empty cutoff (3.3 V — below it a LiPo damages itself), last is a full
/// 4.2 V charge; [`percent_from_mv`] clamps outside the span.
const CURVE_MV_PCT: [(u16, u8); 8] = [
    (3300, 0),
    (3450, 5),
    (3680, 10),
    (3740, 20),
    (3820, 50),
    (3920, 70),
    (4060, 90),
    (4200, 100),
];

/// Readings outside this band are not a 1S LiPo and must not render as one:
/// the nRF52840 DK powered from USB regulates VDD to ~3.0 V (a regulator
/// rail, not a cell — mapping it would show a confident 0%), and a rail well
/// above 4.2 V + charge slack is a broken measurement. The margins past the
/// curve ends absorb ADC error and a charger-fresh cell.
pub const PLAUSIBLE_MIN_MV: u16 = 3200;
pub const PLAUSIBLE_MAX_MV: u16 = 4350;

/// Whether `mv` can honestly be read as a 1S LiPo supply.
pub fn plausible_mv(mv: u16) -> bool {
    (PLAUSIBLE_MIN_MV..=PLAUSIBLE_MAX_MV).contains(&mv)
}

/// At or below this percent the gauge icon renders its low state. 20 % is the
/// knee of [`CURVE_MV_PCT`]: below the 3.74 V anchor the discharge plateau is
/// over and the remaining runtime cliffs, so this is where a glance must turn
/// into a warning.
pub const LOW_PCT: u8 = 20;

/// Whether the gauge should render its low state for `percent`.
pub fn is_low(percent: u8) -> bool {
    percent <= LOW_PCT
}

/// Fill for the battery icon's body, in `0.0..=1.0` — the `gauge` convention:
/// the decision here, the pixel scaling in the render layer.
pub fn fill_fraction(percent: u8) -> f32 {
    f32::from(percent.min(100)) / 100.0
}

/// Map a supply reading onto 0..=100 percent via [`CURVE_MV_PCT`], clamping
/// below the empty cutoff and above the full charge. Linear between adjacent
/// anchors, rounded to the nearest percent.
pub fn percent_from_mv(mv: u16) -> u8 {
    let (floor_mv, floor_pct) = CURVE_MV_PCT[0];
    if mv <= floor_mv {
        return floor_pct;
    }
    let (ceil_mv, ceil_pct) = CURVE_MV_PCT[CURVE_MV_PCT.len() - 1];
    if mv >= ceil_mv {
        return ceil_pct;
    }
    let mut i = 1;
    while CURVE_MV_PCT[i].0 < mv {
        i += 1;
    }
    let (lo_mv, lo_pct) = CURVE_MV_PCT[i - 1];
    let (hi_mv, hi_pct) = CURVE_MV_PCT[i];
    let num = u32::from(mv - lo_mv) * u32::from(hi_pct - lo_pct);
    let den = u32::from(hi_mv - lo_mv);
    lo_pct + ((num + den / 2) / den) as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn curve_is_strictly_ascending_on_both_axes() {
        for pair in CURVE_MV_PCT.windows(2) {
            assert!(pair[0].0 < pair[1].0, "mv anchors must ascend");
            assert!(pair[0].1 < pair[1].1, "percent anchors must ascend");
        }
    }

    #[test]
    fn anchor_points_map_exactly() {
        for (mv, pct) in CURVE_MV_PCT {
            assert_eq!(percent_from_mv(mv), pct, "{mv} mV");
        }
    }

    #[test]
    fn clamps_below_empty_and_above_full() {
        assert_eq!(percent_from_mv(0), 0);
        assert_eq!(percent_from_mv(3000), 0);
        assert_eq!(percent_from_mv(3299), 0);
        assert_eq!(percent_from_mv(4201), 100);
        assert_eq!(percent_from_mv(5000), 100);
        assert_eq!(percent_from_mv(u16::MAX), 100);
    }

    #[test]
    fn interpolates_between_anchors() {
        // Midway through the 3740..3820 (20%..50%) segment.
        assert_eq!(percent_from_mv(3780), 35);
        // Rounding: 3760 is a quarter in -> 20 + 7.5 rounds to 28.
        assert_eq!(percent_from_mv(3760), 28);
    }

    #[test]
    fn monotonic_over_the_whole_plausible_range() {
        let mut prev = percent_from_mv(PLAUSIBLE_MIN_MV);
        for mv in PLAUSIBLE_MIN_MV..=PLAUSIBLE_MAX_MV {
            let pct = percent_from_mv(mv);
            assert!(pct >= prev, "{mv} mV mapped to {pct}% after {prev}%");
            assert!(pct <= 100);
            prev = pct;
        }
    }

    #[test]
    fn plausibility_rejects_bench_rails_and_nonsense() {
        // The DK's USB-regulated VDD (~3.0 V) is a rail, not a cell.
        assert!(!plausible_mv(3000));
        assert!(!plausible_mv(0));
        assert!(!plausible_mv(1800));
        assert!(!plausible_mv(5000));
        assert!(!plausible_mv(PLAUSIBLE_MIN_MV - 1));
        assert!(!plausible_mv(PLAUSIBLE_MAX_MV + 1));
    }

    #[test]
    fn low_state_starts_at_the_curve_knee() {
        assert!(is_low(0));
        assert!(is_low(LOW_PCT));
        assert!(!is_low(LOW_PCT + 1));
        assert!(!is_low(100));
        // LOW_PCT is the plateau-knee anchor, not an arbitrary number: the
        // 3.74 V anchor maps exactly onto it.
        assert_eq!(percent_from_mv(3740), LOW_PCT);
    }

    #[test]
    fn fill_fraction_scales_and_clamps() {
        assert_eq!(fill_fraction(0), 0.0);
        assert_eq!(fill_fraction(50), 0.5);
        assert_eq!(fill_fraction(100), 1.0);
        assert_eq!(fill_fraction(255), 1.0);
        let mut prev = 0.0;
        for pct in 0..=100u8 {
            let f = fill_fraction(pct);
            assert!((0.0..=1.0).contains(&f));
            assert!(f >= prev);
            prev = f;
        }
    }

    #[test]
    fn plausibility_accepts_the_lipo_span() {
        assert!(plausible_mv(PLAUSIBLE_MIN_MV));
        assert!(plausible_mv(3300));
        assert!(plausible_mv(3700));
        assert!(plausible_mv(4200));
        assert!(plausible_mv(PLAUSIBLE_MAX_MV));
    }
}
