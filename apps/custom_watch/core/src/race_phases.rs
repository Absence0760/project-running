//! Race pacing-strategy phase plans — pure, locale/unit-agnostic. Slices a race
//! distance into intent phases (hold back / settle / race) whose pace factors
//! multiply the goal pace, with the derived final factor chosen so the
//! distance-weighted mean factor is exactly 1.0 — the plan still lands the goal
//! time.
//!
//! Presets: [`RacePhasePreset::Even`] (one flat phase),
//! [`RacePhasePreset::NegativeSplit`] (2 % held-back first half, derived-faster
//! second half), and [`RacePhasePreset::TenTenTen`] (the classic marathon
//! 10 mi / 10 mi / 10 K strategy generalised proportionally to any distance).
//! Intent is an identifier — labels resolve at the render layer and are not part
//! of the port.
//!
//! A parity port of web `runs/race_phases.ts` (twin of `race_phases.dart`):
//! same algorithm, same edge cases, test-for-test. The plan is at most
//! [`MAX_RACE_PHASES`] phases, so it lives in a `heapless::Vec` with no
//! allocator.

use heapless::Vec;

/// The most phases any preset produces (the three of `TenTenTen`).
pub const MAX_RACE_PHASES: usize = 3;

/// A marathon's first 10 miles as a fraction of the whole — the proportion the
/// 10-10-10 strategy generalises to any race distance.
const TEN_MILE_FRACTION: f64 = 16_093.44 / 42_195.0;

/// The held-back opening phase runs 2 % slower than goal pace.
const HOLD_BACK_FACTOR: f64 = 1.02;

/// The settle phase runs exactly at goal pace.
const SETTLE_FACTOR: f64 = 1.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RacePhasePreset {
    TenTenTen,
    NegativeSplit,
    Even,
}

impl RacePhasePreset {
    /// The cross-platform wire name, identical to the web union member.
    pub const fn wire(self) -> &'static str {
        match self {
            Self::TenTenTen => "ten_ten_ten",
            Self::NegativeSplit => "negative_split",
            Self::Even => "even",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RacePhaseIntent {
    HoldBack,
    Settle,
    Race,
    Even,
}

impl RacePhaseIntent {
    /// The cross-platform wire name, identical to the web union member. The
    /// runner-facing label is the render layer's job — the core carries no
    /// language.
    pub const fn wire(self) -> &'static str {
        match self {
            Self::HoldBack => "hold_back",
            Self::Settle => "settle",
            Self::Race => "race",
            Self::Even => "even",
        }
    }
}

/// One distance-bounded phase: `[start_m, end_m)` and the factor its target pace
/// multiplies the goal pace by.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RacePhase {
    pub start_m: f64,
    pub end_m: f64,
    pub intent: RacePhaseIntent,
    pub pace_factor: f64,
}

pub type PhasePlan = Vec<RacePhase, MAX_RACE_PHASES>;

/// Slice `distance_m` into the preset's intent phases. A non-positive or
/// non-finite distance yields an empty plan — there is no race to shape.
pub fn build_phase_plan(distance_m: f64, preset: RacePhasePreset) -> PhasePlan {
    let mut plan = PhasePlan::new();
    if !distance_m.is_finite() || distance_m <= 0.0 {
        return plan;
    }

    match preset {
        RacePhasePreset::Even => {
            let _ = plan.push(RacePhase {
                start_m: 0.0,
                end_m: distance_m,
                intent: RacePhaseIntent::Even,
                pace_factor: 1.0,
            });
        }
        RacePhasePreset::NegativeSplit => {
            let race_factor = (1.0 - 0.5 * HOLD_BACK_FACTOR) / 0.5;
            let half = distance_m / 2.0;
            let _ = plan.push(RacePhase {
                start_m: 0.0,
                end_m: half,
                intent: RacePhaseIntent::HoldBack,
                pace_factor: HOLD_BACK_FACTOR,
            });
            let _ = plan.push(RacePhase {
                start_m: half,
                end_m: distance_m,
                intent: RacePhaseIntent::Race,
                pace_factor: race_factor,
            });
        }
        RacePhasePreset::TenTenTen => {
            let f1 = TEN_MILE_FRACTION;
            let f2 = TEN_MILE_FRACTION;
            let f3 = 1.0 - f1 - f2;
            let race_factor = (1.0 - f1 * HOLD_BACK_FACTOR - f2 * SETTLE_FACTOR) / f3;
            let _ = plan.push(RacePhase {
                start_m: 0.0,
                end_m: distance_m * f1,
                intent: RacePhaseIntent::HoldBack,
                pace_factor: HOLD_BACK_FACTOR,
            });
            let _ = plan.push(RacePhase {
                start_m: distance_m * f1,
                end_m: distance_m * (f1 + f2),
                intent: RacePhaseIntent::Settle,
                pace_factor: SETTLE_FACTOR,
            });
            let _ = plan.push(RacePhase {
                start_m: distance_m * (f1 + f2),
                end_m: distance_m,
                intent: RacePhaseIntent::Race,
                pace_factor: race_factor,
            });
        }
    }
    plan
}

/// Index of the phase containing `distance_m` (start-inclusive, end-exclusive;
/// at or past the last end clamps to the last index, below 0 clamps to the
/// first). Empty plan → -1.
pub fn phase_at(phases: &[RacePhase], distance_m: f64) -> i8 {
    if phases.is_empty() {
        return -1;
    }
    if distance_m < 0.0 {
        return 0;
    }
    for (i, p) in phases.iter().enumerate() {
        if distance_m >= p.start_m && distance_m < p.end_m {
            return i as i8;
        }
    }
    (phases.len() - 1) as i8
}

/// The phase's target pace: the goal pace scaled by the phase factor. `None`
/// without a usable goal pace — a phase with no goal has no target, never a
/// zero standing in for one.
pub fn phase_target_pace_s_per_km(
    phase: &RacePhase,
    goal_pace_s_per_km: Option<f64>,
) -> Option<f64> {
    let goal = goal_pace_s_per_km?;
    if !goal.is_finite() || goal <= 0.0 {
        return None;
    }
    Some(goal * phase.pace_factor)
}

/// Even goal pace for a race: the goal time spread over its kilometres.
pub fn goal_pace_s_per_km(distance_m: f64, goal_time_s: f64) -> Option<f64> {
    if !distance_m.is_finite() || distance_m <= 0.0 {
        return None;
    }
    if !goal_time_s.is_finite() || goal_time_s <= 0.0 {
        return None;
    }
    Some(goal_time_s / (distance_m / 1000.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn weighted_mean_factor(phases: &[RacePhase]) -> f64 {
        let total = phases[phases.len() - 1].end_m;
        let sum: f64 = phases
            .iter()
            .map(|p| p.pace_factor * (p.end_m - p.start_m))
            .sum();
        sum / total
    }

    #[test]
    fn even_preset_is_one_full_distance_phase_at_factor_1() {
        let plan = build_phase_plan(10_000.0, RacePhasePreset::Even);
        assert_eq!(plan.len(), 1);
        assert_eq!(
            plan[0],
            RacePhase {
                start_m: 0.0,
                end_m: 10_000.0,
                intent: RacePhaseIntent::Even,
                pace_factor: 1.0,
            }
        );
    }

    #[test]
    fn ten_ten_ten_boundaries_land_on_the_generalised_ten_mile_fractions() {
        let plan = build_phase_plan(42_195.0, RacePhasePreset::TenTenTen);
        assert_eq!(plan.len(), 3);
        assert_eq!(plan[0].start_m, 0.0);
        assert!((plan[1].start_m - 16_093.44).abs() < 1e-9);
        assert!((plan[2].start_m - 32_186.88).abs() < 1e-9);
        assert_eq!(plan[2].end_m, 42_195.0);
        assert_eq!(plan[0].end_m, plan[1].start_m);
        assert_eq!(plan[1].end_m, plan[2].start_m);
    }

    #[test]
    fn ten_ten_ten_intents_and_factors_hold_back_settle_then_a_derived_finish() {
        let plan = build_phase_plan(42_195.0, RacePhasePreset::TenTenTen);
        let intents: heapless::Vec<RacePhaseIntent, MAX_RACE_PHASES> =
            plan.iter().map(|p| p.intent).collect();
        assert_eq!(
            intents.as_slice(),
            &[
                RacePhaseIntent::HoldBack,
                RacePhaseIntent::Settle,
                RacePhaseIntent::Race
            ]
        );
        assert_eq!(plan[0].pace_factor, 1.02);
        assert_eq!(plan[1].pace_factor, 1.0);
        let f = TEN_MILE_FRACTION;
        let derived = (1.0 - f * 1.02 - f * 1.0) / (1.0 - f - f);
        assert!((plan[2].pace_factor - derived).abs() < 1e-12);
        assert!(plan[2].pace_factor > 0.96 && plan[2].pace_factor < 0.97);
    }

    #[test]
    fn distance_weighted_mean_factor_is_1_for_ten_ten_ten_at_any_distance() {
        for distance_m in [42_195.0, 10_000.0, 160_934.0] {
            let plan = build_phase_plan(distance_m, RacePhasePreset::TenTenTen);
            assert!((weighted_mean_factor(&plan) - 1.0).abs() < 1e-9);
        }
    }

    #[test]
    fn negative_split_is_two_halves_held_back_then_a_derived_finish_mean_1() {
        let plan = build_phase_plan(21_097.5, RacePhasePreset::NegativeSplit);
        assert_eq!(plan.len(), 2);
        let intents: heapless::Vec<RacePhaseIntent, MAX_RACE_PHASES> =
            plan.iter().map(|p| p.intent).collect();
        assert_eq!(
            intents.as_slice(),
            &[RacePhaseIntent::HoldBack, RacePhaseIntent::Race]
        );
        assert_eq!(plan[0].end_m, 21_097.5 / 2.0);
        assert_eq!(plan[1].start_m, 21_097.5 / 2.0);
        assert_eq!(plan[0].pace_factor, 1.02);
        assert!((plan[1].pace_factor - (1.0 - 0.5 * 1.02) / 0.5).abs() < 1e-12);
        assert!((weighted_mean_factor(&plan) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn phase_at_puts_an_exact_boundary_in_the_next_phase() {
        let plan = build_phase_plan(42_195.0, RacePhasePreset::TenTenTen);
        assert_eq!(phase_at(&plan, 0.0), 0);
        assert_eq!(phase_at(&plan, plan[1].start_m - 0.001), 0);
        assert_eq!(phase_at(&plan, plan[1].start_m), 1);
        assert_eq!(phase_at(&plan, plan[2].start_m), 2);
    }

    #[test]
    fn phase_at_clamps_past_the_end_to_last_negative_to_first_empty_to_minus_1() {
        let plan = build_phase_plan(42_195.0, RacePhasePreset::TenTenTen);
        assert_eq!(phase_at(&plan, 42_195.0), 2);
        assert_eq!(phase_at(&plan, 100_000.0), 2);
        assert_eq!(phase_at(&plan, -5.0), 0);
        assert_eq!(phase_at(&[], 1_000.0), -1);
    }

    #[test]
    fn a_non_positive_or_non_finite_distance_yields_an_empty_plan() {
        for distance_m in [0.0, -42_195.0, f64::NAN, f64::INFINITY] {
            assert!(build_phase_plan(distance_m, RacePhasePreset::TenTenTen).is_empty());
            assert!(build_phase_plan(distance_m, RacePhasePreset::NegativeSplit).is_empty());
            assert!(build_phase_plan(distance_m, RacePhasePreset::Even).is_empty());
        }
    }

    #[test]
    fn goal_pace_divides_the_goal_time_over_the_km_and_rejects_bad_inputs() {
        assert_eq!(goal_pace_s_per_km(10_000.0, 3_000.0), Some(300.0));
        assert_eq!(goal_pace_s_per_km(0.0, 3_000.0), None);
        assert_eq!(goal_pace_s_per_km(-1.0, 3_000.0), None);
        assert_eq!(goal_pace_s_per_km(10_000.0, 0.0), None);
        assert_eq!(goal_pace_s_per_km(10_000.0, -60.0), None);
        assert_eq!(goal_pace_s_per_km(f64::NAN, 3_000.0), None);
        assert_eq!(goal_pace_s_per_km(10_000.0, f64::NAN), None);
    }

    #[test]
    fn phase_target_pace_scales_the_goal_pace_and_rejects_a_bad_pace() {
        let plan = build_phase_plan(42_195.0, RacePhasePreset::TenTenTen);
        assert!((phase_target_pace_s_per_km(&plan[0], Some(300.0)).unwrap() - 306.0).abs() < 1e-9);
        assert_eq!(
            phase_target_pace_s_per_km(&plan[1], Some(300.0)),
            Some(300.0)
        );
        assert_eq!(phase_target_pace_s_per_km(&plan[0], None), None);
        assert_eq!(phase_target_pace_s_per_km(&plan[0], Some(0.0)), None);
        assert_eq!(phase_target_pace_s_per_km(&plan[0], Some(-300.0)), None);
        assert_eq!(phase_target_pace_s_per_km(&plan[0], Some(f64::NAN)), None);
    }

    #[test]
    fn preset_and_intent_wire_names_are_stable() {
        assert_eq!(
            [
                RacePhasePreset::TenTenTen.wire(),
                RacePhasePreset::NegativeSplit.wire(),
                RacePhasePreset::Even.wire()
            ],
            ["ten_ten_ten", "negative_split", "even"]
        );
        assert_eq!(
            [
                RacePhaseIntent::HoldBack.wire(),
                RacePhaseIntent::Settle.wire(),
                RacePhaseIntent::Race.wire(),
                RacePhaseIntent::Even.wire()
            ],
            ["hold_back", "settle", "race", "even"]
        );
    }
}
