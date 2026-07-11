//! Hydration target — a daily water goal the water tracker counts toward.
//!
//! A parity port of web `nutrition/hydration.ts` (twin of `hydration.dart`).
//! Heuristic constants (~35 ml/kg/
//! day, +8 ml/min of exercise) are a conservative nudge. The one non-obvious
//! choice: unlike the macro rings, this always returns a target (flat 2 L when
//! bodyweight is unknown), because a water tracker should work for everyone.
//! Water is a floor to reach, so the budget reports only remaining-to-goal +
//! a `reached` flag, never an over-budget warning. Pure logic, no peripherals,
//! no allocator.

/// Baseline daily water, ml per kg of bodyweight.
pub const BASELINE_ML_PER_KG: f64 = 35.0;
/// Flat baseline when bodyweight is unknown (~2 L).
pub const DEFAULT_BASELINE_ML: f64 = 2000.0;
/// Extra water per minute of logged exercise (~480 ml/hr sweat replacement).
pub const EXERCISE_ML_PER_MIN: f64 = 8.0;
/// Targets round to this for a tidy number.
pub const TARGET_ROUND_ML: f64 = 50.0;

/// Daily water goal in ml from bodyweight + today's exercise minutes. Always
/// returns a positive target (the flat baseline covers missing bodyweight).
pub fn hydration_target_ml(weight_kg: Option<f64>, exercise_minutes: Option<f64>) -> f64 {
    let baseline = match weight_kg {
        Some(w) if w > 0.0 => w * BASELINE_ML_PER_KG,
        _ => DEFAULT_BASELINE_ML,
    };
    let exercise = match exercise_minutes {
        Some(m) if m > 0.0 => m * EXERCISE_ML_PER_MIN,
        _ => 0.0,
    };
    libm::round((baseline + exercise) / TARGET_ROUND_ML) * TARGET_ROUND_ML
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HydrationBudget {
    pub target_ml: f64,
    pub consumed_ml: f64,
    /// Water still to drink, never negative (0 once the goal is met).
    pub remaining_ml: f64,
    /// True once consumed reaches or clears the target — a win, not a warning.
    pub reached: bool,
    /// Progress toward the goal, clamped to [0, 1] for the fill bar.
    pub fraction: f64,
}

/// Budget for the day's water given consumed + target ml.
pub fn hydration_budget(consumed_ml: f64, target_ml: f64) -> HydrationBudget {
    let consumed = libm::round(consumed_ml).max(0.0);
    let target = libm::round(target_ml).max(0.0);
    let remaining_ml = (target - consumed).max(0.0);
    let reached = target > 0.0 && consumed >= target;
    let fraction = if target > 0.0 {
        (consumed / target).clamp(0.0, 1.0)
    } else {
        0.0
    };
    HydrationBudget {
        target_ml: target,
        consumed_ml: consumed,
        remaining_ml,
        reached,
        fraction,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bodyweight_baseline_at_35_ml_per_kg_rounded_to_50() {
        assert_eq!(
            hydration_target_ml(Some(70.0), Some(0.0)),
            70.0 * BASELINE_ML_PER_KG
        );
        assert_eq!(hydration_target_ml(Some(68.0), Some(0.0)), 2400.0);
    }

    #[test]
    fn missing_non_physical_bodyweight_falls_back_to_flat_baseline() {
        assert_eq!(hydration_target_ml(None, Some(0.0)), DEFAULT_BASELINE_ML);
        assert_eq!(
            hydration_target_ml(Some(0.0), Some(0.0)),
            DEFAULT_BASELINE_ML
        );
        assert_eq!(
            hydration_target_ml(Some(-5.0), Some(0.0)),
            DEFAULT_BASELINE_ML
        );
    }

    #[test]
    fn exercise_minutes_raise_the_goal() {
        assert!(
            hydration_target_ml(Some(70.0), Some(60.0))
                > hydration_target_ml(Some(70.0), Some(0.0))
        );
        assert_eq!(hydration_target_ml(Some(70.0), Some(60.0)), 2950.0);
        assert_eq!(hydration_target_ml(None, Some(30.0)), 2250.0);
    }

    #[test]
    fn missing_zero_exercise_adds_nothing() {
        assert_eq!(hydration_target_ml(Some(70.0), None), 2450.0);
        assert_eq!(hydration_target_ml(Some(70.0), Some(0.0)), 2450.0);
        assert_eq!(hydration_target_ml(Some(70.0), Some(-10.0)), 2450.0);
    }

    #[test]
    fn under_goal_reports_remaining_not_reached() {
        let b = hydration_budget(1000.0, 2450.0);
        assert_eq!(b.remaining_ml, 1450.0);
        assert!(!b.reached);
        assert!((b.fraction - 1000.0 / 2450.0).abs() < 1e-9);
    }

    #[test]
    fn reaching_the_goal_flags_reached_remaining_floors_at_zero() {
        let b = hydration_budget(2450.0, 2450.0);
        assert_eq!(b.remaining_ml, 0.0);
        assert!(b.reached);
        assert_eq!(b.fraction, 1.0);
    }

    #[test]
    fn over_the_goal_stays_reached_fraction_clamps_to_one() {
        let b = hydration_budget(3000.0, 2450.0);
        assert_eq!(b.remaining_ml, 0.0);
        assert!(b.reached);
        assert_eq!(b.fraction, 1.0);
    }

    #[test]
    fn a_zero_target_never_reads_as_reached_or_divides() {
        let b = hydration_budget(0.0, 0.0);
        assert!(!b.reached);
        assert_eq!(b.fraction, 0.0);
        assert_eq!(b.remaining_ml, 0.0);
    }

    #[test]
    fn rounds_and_floors_negative_consumed() {
        let b = hydration_budget(-50.0, 2000.0);
        assert_eq!(b.consumed_ml, 0.0);
        assert_eq!(b.remaining_ml, 2000.0);
    }
}
