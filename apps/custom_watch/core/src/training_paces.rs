//! Training pace zones — the five Daniels intensity-zone paces (easy /
//! marathon / tempo / interval / repetition, seconds per km) derived from a
//! goal-race pace, plus the resolver that picks that goal pace from whichever
//! fitness anchor the runner gave us (a recent 5K via Riegel → an explicit
//! goal time → a conservative fallback).
//!
//! Parity port of the pace-zone surface of web `training/training.ts`
//! (`pacesFromGoalPace` / `resolveTrainingPaces` / `resolveTrainingPacesWithMeta`
//! / `isMastersAge`), twin of `apps/mobile_android/lib/training.dart`. Keep the
//! multipliers, the 3% female calibration, the masters boundary, and the
//! anchor-priority branching in lockstep. The VDOT table, phase schedule, and
//! plan generator are NOT ported — those are out of scope here.
//!
//! Riegel is not re-ported: `resolve_training_paces_with_meta` reuses
//! [`crate::race_predictor::riegel_predict`] with the standard 1.06 exponent.
//! Pure logic, no peripherals, no allocator.

use crate::race_predictor::riegel_predict;

/// Riegel's 1981 exponent, matching the web `riegelPredict` default. Reused to
/// project a recent-5K anchor onto the goal distance before deriving paces.
const RIEGEL_EXPONENT: f64 = 1.06;

/// Female runners' actual VDOT plotted on Daniels' male-default curve
/// under-predicts their training paces by ~3%; applied as a uniform pace-time
/// multiplier (slightly slower seconds/km in every band). Male / NonBinary /
/// None stay on the unmodified curve — no validated calibration exists for
/// them, and a wrong adjustment is worse than none.
pub const FEMALE_PACE_CALIBRATION: f64 = 1.03;

/// Masters (50+) boundary. The web engine uses this only to widen hard-day
/// recovery spacing in the plan generator (not ported); the boundary predicate
/// itself is ported so a watch-side surface can flag a masters athlete.
pub const MASTERS_AGE: f64 = 50.0;

/// Conservative goal pace (sec/km, ~10:00/km) used when the runner gave us
/// neither a recent race nor a goal time. Slow enough that the derived easy
/// pace won't injure a returning runner; the resolver flags when it is in play.
pub const FALLBACK_GOAL_PACE_SEC_PER_KM: f64 = 600.0;

/// Optional gender hint for pace derivation. Mirrors the `gender` column on
/// `user_profiles`. Only [`TrainingGender::Female`] shifts the curve.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum TrainingGender {
    Male,
    Female,
    NonBinary,
    None,
}

/// The five Daniels intensity-zone paces, seconds per km. Ordered slow → fast
/// (easy is the biggest number, repetition the smallest).
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TrainingPaces {
    pub easy: f64,
    pub marathon: f64,
    pub tempo: f64,
    pub interval: f64,
    pub repetition: f64,
}

/// The resolved paces plus whether they came from a real fitness anchor or the
/// conservative fallback. `is_fallback` is true only when no usable anchor was
/// supplied, so the caller can disclose the paces are estimated.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ResolvedTrainingPaces {
    pub paces: TrainingPaces,
    pub is_fallback: bool,
}

/// The fitness anchor a caller supplies. `goal_time_s` / `recent_5k_s` are
/// optional; a `None`, zero, or NaN value is treated as "no usable anchor"
/// (mirroring the web JS truthiness the twin-parity test pins), so it falls
/// through to the next priority rather than running Riegel on a bad number.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PaceAnchor {
    pub goal_distance_m: f64,
    pub goal_time_s: Option<f64>,
    pub recent_5k_s: Option<f64>,
    pub gender: TrainingGender,
}

fn gender_pace_multiplier(gender: TrainingGender) -> f64 {
    match gender {
        TrainingGender::Female => FEMALE_PACE_CALIBRATION,
        _ => 1.0,
    }
}

/// True at or above [`MASTERS_AGE`]. A missing age is not masters.
pub fn is_masters_age(age: Option<f64>) -> bool {
    matches!(age, Some(a) if a >= MASTERS_AGE)
}

/// Derive the five Daniels intensity-zone paces as multipliers of goal-race
/// pace. `goal_pace_sec_per_km` is the runner's target pace for the goal race;
/// [`TrainingGender::Female`] applies the 3% calibration uniformly.
pub fn paces_from_goal_pace(goal_pace_sec_per_km: f64, gender: TrainingGender) -> TrainingPaces {
    let g = gender_pace_multiplier(gender);
    TrainingPaces {
        easy: libm::round(goal_pace_sec_per_km * 1.22 * g),
        marathon: libm::round(goal_pace_sec_per_km * 1.06 * g),
        tempo: libm::round(goal_pace_sec_per_km * 0.97 * g),
        interval: libm::round(goal_pace_sec_per_km * 0.9 * g),
        repetition: libm::round(goal_pace_sec_per_km * 0.85 * g),
    }
}

/// JS-truthy for an optional seconds value: present, non-zero, finite. A `0`
/// (or `NaN`) is "no usable time", not a real anchor.
fn usable_anchor(value: Option<f64>) -> Option<f64> {
    match value {
        Some(v) if v != 0.0 && !v.is_nan() => Some(v),
        _ => None,
    }
}

/// Resolve the runner's training paces plus whether they came from a real
/// fitness anchor or the conservative fallback. Priority: an explicit recent 5K
/// time (Riegel-projected onto the goal distance) → a goal time on the target
/// distance (used directly) → the conservative [`FALLBACK_GOAL_PACE_SEC_PER_KM`]
/// so the paces still generate for someone without any race history.
pub fn resolve_training_paces_with_meta(input: PaceAnchor) -> ResolvedTrainingPaces {
    let (goal_pace_sec_per_km, is_fallback) = if let Some(recent) = usable_anchor(input.recent_5k_s)
    {
        let predicted = riegel_predict(5000.0, recent, input.goal_distance_m, RIEGEL_EXPONENT);
        (predicted / (input.goal_distance_m / 1000.0), false)
    } else if let Some(goal) = usable_anchor(input.goal_time_s) {
        (goal / (input.goal_distance_m / 1000.0), false)
    } else {
        (FALLBACK_GOAL_PACE_SEC_PER_KM, true)
    };
    ResolvedTrainingPaces {
        paces: paces_from_goal_pace(goal_pace_sec_per_km, input.gender),
        is_fallback,
    }
}

/// Thin wrapper over [`resolve_training_paces_with_meta`] for callers that
/// don't need the fallback flag.
pub fn resolve_training_paces(input: PaceAnchor) -> TrainingPaces {
    resolve_training_paces_with_meta(input).paces
}

#[cfg(test)]
mod tests {
    use super::*;

    // Mirror of the pace-zone cases in
    // `apps/web/src/lib/training/training.test.ts` — same goal-pace inputs,
    // same bands, so the port can't drift. Plan-generation / phase / VDOT
    // cases are out of scope and not mirrored.

    fn anchor(
        goal_distance_m: f64,
        goal_time_s: Option<f64>,
        recent_5k_s: Option<f64>,
        gender: TrainingGender,
    ) -> PaceAnchor {
        PaceAnchor {
            goal_distance_m,
            goal_time_s,
            recent_5k_s,
            gender,
        }
    }

    #[test]
    fn paces_zones_ordered_slow_to_fast() {
        let p = paces_from_goal_pace(240.0, TrainingGender::None);
        assert!(p.easy > p.marathon);
        assert!(p.marathon > p.tempo);
        assert!(p.tempo > p.interval);
        assert!(p.interval > p.repetition);
    }

    #[test]
    fn paces_easy_band_for_four_min_goal() {
        let p = paces_from_goal_pace(240.0, TrainingGender::None);
        assert!(
            p.easy >= 270.0 && p.easy <= 315.0,
            "easy out of band: {}",
            p.easy
        );
    }

    #[test]
    fn none_and_male_share_the_base_curve() {
        let none = paces_from_goal_pace(240.0, TrainingGender::None);
        let male = paces_from_goal_pace(240.0, TrainingGender::Male);
        assert_eq!(none, male);
    }

    #[test]
    fn female_calibration_shifts_every_band_slower() {
        let male = paces_from_goal_pace(240.0, TrainingGender::Male);
        let female = paces_from_goal_pace(240.0, TrainingGender::Female);
        assert!(female.easy > male.easy);
        assert!(female.marathon > male.marathon);
        assert!(female.tempo > male.tempo);
        assert!(female.interval > male.interval);
        assert!(female.repetition > male.repetition);
        let ratio = female.easy / male.easy;
        assert!(
            ratio > 1.02 && ratio < 1.05,
            "female/male easy ratio out of band: {ratio}"
        );
    }

    #[test]
    fn nonbinary_falls_back_to_base_curve() {
        let male = paces_from_goal_pace(240.0, TrainingGender::Male);
        let nb = paces_from_goal_pace(240.0, TrainingGender::NonBinary);
        assert_eq!(nb, male);
    }

    #[test]
    fn recent_5k_beats_goal_time_as_anchor() {
        let with_recent = resolve_training_paces(anchor(
            5000.0,
            Some(19.0 * 60.0 + 59.0),
            Some(25.0 * 60.0),
            TrainingGender::None,
        ));
        let with_goal_only = resolve_training_paces(anchor(
            5000.0,
            Some(19.0 * 60.0 + 59.0),
            None,
            TrainingGender::None,
        ));
        assert!(
            with_recent.easy > with_goal_only.easy,
            "recent-5k anchor should yield slower (safer) easy pace"
        );
    }

    #[test]
    fn fallback_produces_valid_pace_set() {
        let p = resolve_training_paces(anchor(10_000.0, None, None, TrainingGender::None));
        assert!(p.easy > 0.0 && p.interval > 0.0);
    }

    #[test]
    fn zero_anchor_is_treated_as_no_anchor() {
        let zero_recent = resolve_training_paces_with_meta(anchor(
            10_000.0,
            None,
            Some(0.0),
            TrainingGender::None,
        ));
        assert!(zero_recent.is_fallback);
        assert!(zero_recent.paces.easy > 0.0 && zero_recent.paces.interval > 0.0);

        let zero_goal = resolve_training_paces_with_meta(anchor(
            10_000.0,
            Some(0.0),
            None,
            TrainingGender::None,
        ));
        assert!(zero_goal.is_fallback);
        assert!(zero_goal.paces.easy > 0.0);

        let fallback =
            resolve_training_paces_with_meta(anchor(10_000.0, None, None, TrainingGender::None));
        assert_eq!(zero_recent.paces.easy, fallback.paces.easy);
    }

    #[test]
    fn marathon_only_goal_time_valid() {
        let p = resolve_training_paces(anchor(
            42195.0,
            Some(4.0 * 3600.0),
            None,
            TrainingGender::None,
        ));
        assert!(
            p.easy > 350.0 && p.easy < 500.0,
            "easy out of range: {}",
            p.easy
        );
        assert!(p.tempo < p.marathon, "tempo must be faster than marathon");
    }

    #[test]
    fn masters_age_boundary_is_fifty_inclusive() {
        assert!(!is_masters_age(Some(49.0)));
        assert!(is_masters_age(Some(50.0)));
        assert!(is_masters_age(Some(72.0)));
        assert!(!is_masters_age(None));
    }
}
