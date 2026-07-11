//! Gear wear status — classify a piece of gear by how close its accumulated
//! distance is to its replacement target, so the face can warn before a shoe
//! is run into the ground.
//!
//! A parity port of web `gear/gear_wear.ts` (twin of `gear_wear.dart`).
//! Thresholds are deliberately simple: a shoe in the last ~15% of its planned
//! life is [`Due`](GearWearStatus::Due) (replace soon), and at/over its target
//! is [`Worn`](GearWearStatus::Worn). Untracked gear (no target set) gets no
//! warning — the progress bar already shows raw distance.
//!
//! Negative / non-finite inputs are treated as 0 so a bad row can't surface a
//! scary false "worn" badge. Pure logic, no peripherals, no allocator.

/// Fraction of the replacement target at which gear is flagged "due".
pub const GEAR_WEAR_DUE_FRACTION: f64 = 0.85;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GearWearStatus {
    Untracked,
    Ok,
    Due,
    Worn,
}

/// Wear verdict + `total / target` fraction (uncapped, so a 120%-worn shoe
/// reads 1.2); `fraction` is `None` when no target is set. The caller caps the
/// progress *bar* at 100% itself.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GearWear {
    pub status: GearWearStatus,
    pub fraction: Option<f64>,
}

/// Classify gear wear from its rolled-up distance vs its replacement target.
/// A missing / non-finite / non-positive target is untracked; a missing /
/// non-finite / non-positive total clamps to 0.
pub fn gear_wear(total_distance_m: Option<f64>, target_distance_m: Option<f64>) -> GearWear {
    let target = match target_distance_m {
        Some(t) if t.is_finite() && t > 0.0 => t,
        _ => {
            return GearWear {
                status: GearWearStatus::Untracked,
                fraction: None,
            };
        }
    };
    let total = match total_distance_m {
        Some(v) if v.is_finite() && v > 0.0 => v,
        _ => 0.0,
    };
    let fraction = total / target;
    let status = if fraction >= 1.0 {
        GearWearStatus::Worn
    } else if fraction >= GEAR_WEAR_DUE_FRACTION {
        GearWearStatus::Due
    } else {
        GearWearStatus::Ok
    };
    GearWear {
        status,
        fraction: Some(fraction),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_target_is_untracked_with_null_fraction() {
        let w = gear_wear(Some(500_000.0), None);
        assert_eq!(w.status, GearWearStatus::Untracked);
        assert_eq!(w.fraction, None);
        let z = gear_wear(Some(500_000.0), Some(0.0));
        assert_eq!(z.status, GearWearStatus::Untracked);
        assert_eq!(z.fraction, None);
    }

    #[test]
    fn well_within_target_is_ok() {
        let w = gear_wear(Some(300_000.0), Some(800_000.0));
        assert_eq!(w.status, GearWearStatus::Ok);
        assert!((w.fraction.unwrap() - 0.375).abs() < 1e-9);
    }

    #[test]
    fn at_the_due_threshold_is_due() {
        let w = gear_wear(Some(GEAR_WEAR_DUE_FRACTION * 800_000.0), Some(800_000.0));
        assert_eq!(w.status, GearWearStatus::Due);
    }

    #[test]
    fn just_below_the_due_threshold_is_ok() {
        let w = gear_wear(
            Some((GEAR_WEAR_DUE_FRACTION - 0.01) * 800_000.0),
            Some(800_000.0),
        );
        assert_eq!(w.status, GearWearStatus::Ok);
    }

    #[test]
    fn at_target_is_worn() {
        assert_eq!(
            gear_wear(Some(800_000.0), Some(800_000.0)).status,
            GearWearStatus::Worn
        );
    }

    #[test]
    fn over_target_is_worn_with_uncapped_fraction() {
        let w = gear_wear(Some(960_000.0), Some(800_000.0));
        assert_eq!(w.status, GearWearStatus::Worn);
        assert!((w.fraction.unwrap() - 1.2).abs() < 1e-9);
    }

    #[test]
    fn zero_negative_non_finite_total_clamps_to_zero() {
        assert_eq!(
            gear_wear(Some(0.0), Some(800_000.0)).status,
            GearWearStatus::Ok
        );
        assert_eq!(
            gear_wear(Some(-100.0), Some(800_000.0)).status,
            GearWearStatus::Ok
        );
        assert_eq!(
            gear_wear(Some(f64::NAN), Some(800_000.0)).status,
            GearWearStatus::Ok
        );
    }

    #[test]
    fn non_finite_negative_target_is_untracked() {
        assert_eq!(
            gear_wear(Some(500_000.0), Some(f64::NAN)).status,
            GearWearStatus::Untracked
        );
        assert_eq!(
            gear_wear(Some(500_000.0), Some(-10.0)).status,
            GearWearStatus::Untracked
        );
    }
}
