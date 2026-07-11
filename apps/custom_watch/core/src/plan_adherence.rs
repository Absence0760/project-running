//! Plan-adherence feedback — does the runner's actual training match the
//! plan? Two pure signals:
//!
//!  1. [`weekly_drift`] — flags when actual weekly volume runs more than
//!     ±[`PLAN_DRIFT_THRESHOLD`] off the plan. BOTH directions matter:
//!     under-running loses the adaptation; over-running the easy weeks digs
//!     a fatigue hole.
//!  2. [`missed_workout_advice`] — a make-up / skip recommendation for a
//!     missed long run, driven by training phase + proximity to a recovery
//!     week. Only the long run earns a make-up decision.
//!
//! A parity port of web `training/plan_adherence.ts` (twin of
//! `plan_adherence.dart`). The advice/drift outputs are reason-code enums,
//! never English prose — the presentation layer owns wording.

/// Beyond ±this fraction off the planned weekly volume, surface a drift
/// flag. 20% is roughly one easy run's worth on a typical week.
pub const PLAN_DRIFT_THRESHOLD: f64 = 0.2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum DriftDirection {
    Under,
    Over,
    OnTrack,
}

/// Weekly mileage drift verdict. `drift_fraction` is `(actual − planned) /
/// planned` (positive = over-running); 0 when there's no planned volume.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct WeeklyDrift {
    pub planned_metres: f64,
    pub actual_metres: f64,
    pub drift_fraction: f64,
    pub direction: DriftDirection,
    /// True when `|drift_fraction|` exceeds the threshold AND there's a real
    /// plan to drift from (planned volume > 0).
    pub flagged: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum MakeUpRecommendation {
    MakeUp,
    Skip,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum MissedWorkoutReason {
    /// Base/build long run — worth making up.
    KeySession,
    /// Late in the plan; adding load now hurts more than it helps.
    Taper,
    /// A step-back week is imminent; let the body take the down week.
    RecoverySoon,
    /// Quality session, not worth a dedicated make-up.
    NotLongRun,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct MissedWorkoutAdvice {
    pub recommendation: MakeUpRecommendation,
    pub reason: MissedWorkoutReason,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct MissedWorkoutInput<'a> {
    /// Workout kind from the plan (`long`, `tempo`, …).
    pub kind: &'a str,
    pub is_taper: bool,
    /// Whether the very next week is a recovery / step-back week. `None` when
    /// unknown (treated as "not imminent").
    pub recovery_week_imminent: Option<bool>,
}

/// Compare a week's actual mileage to its planned volume. Returns a neutral,
/// unflagged result when the week has no planned volume (a pure rest week, or
/// a week before the plan models distance) so the caller never shows a drift
/// flag against a zero baseline.
pub fn weekly_drift(planned_metres: f64, actual_metres: f64, threshold: f64) -> WeeklyDrift {
    // Negated `>` (not `<= 0.0`) is deliberate: NaN must take the neutral
    // branch, and `NaN <= 0.0` is false where `!(NaN > 0.0)` is true.
    #[allow(clippy::neg_cmp_op_on_partial_ord)]
    if !(planned_metres > 0.0) {
        return WeeklyDrift {
            planned_metres: max_zero(planned_metres),
            actual_metres: max_zero(actual_metres),
            drift_fraction: 0.0,
            direction: DriftDirection::OnTrack,
            flagged: false,
        };
    }
    let actual = max_zero(actual_metres);
    let drift_fraction = (actual - planned_metres) / planned_metres;
    let direction = if drift_fraction > threshold {
        DriftDirection::Over
    } else if drift_fraction < -threshold {
        DriftDirection::Under
    } else {
        DriftDirection::OnTrack
    };
    WeeklyDrift {
        planned_metres,
        actual_metres: actual,
        drift_fraction,
        direction,
        flagged: direction != DriftDirection::OnTrack,
    }
}

/// Recommend whether to make up or skip a missed workout. Only the long run
/// earns a make-up decision; everything else is cheaper to drop than to cram.
/// For a long run: skip in the taper (freshness > one more long run) or when a
/// recovery week is about to absorb the deficit anyway; otherwise make it up.
pub fn missed_workout_advice(input: &MissedWorkoutInput) -> MissedWorkoutAdvice {
    if input.kind != "long" {
        return MissedWorkoutAdvice {
            recommendation: MakeUpRecommendation::Skip,
            reason: MissedWorkoutReason::NotLongRun,
        };
    }
    if input.is_taper {
        return MissedWorkoutAdvice {
            recommendation: MakeUpRecommendation::Skip,
            reason: MissedWorkoutReason::Taper,
        };
    }
    if input.recovery_week_imminent == Some(true) {
        return MissedWorkoutAdvice {
            recommendation: MakeUpRecommendation::Skip,
            reason: MissedWorkoutReason::RecoverySoon,
        };
    }
    MissedWorkoutAdvice {
        recommendation: MakeUpRecommendation::MakeUp,
        reason: MissedWorkoutReason::KeySession,
    }
}

/// Faithful `Math.max(0, x)`: clamps to 0 but propagates NaN (Rust's
/// `f64::max` would swallow it), so a bad row can't read as a real value.
fn max_zero(x: f64) -> f64 {
    if x > 0.0 {
        x
    } else if x.is_nan() {
        f64::NAN
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn weekly_drift_on_track_when_actual_matches_planned() {
        let d = weekly_drift(40_000.0, 41_000.0, PLAN_DRIFT_THRESHOLD);
        assert_eq!(d.direction, DriftDirection::OnTrack);
        assert!(!d.flagged);
    }

    #[test]
    fn weekly_drift_flags_under_running_past_the_threshold() {
        let d = weekly_drift(40_000.0, 28_000.0, PLAN_DRIFT_THRESHOLD);
        assert_eq!(d.direction, DriftDirection::Under);
        assert!(d.flagged);
        assert!(d.drift_fraction < -PLAN_DRIFT_THRESHOLD);
    }

    #[test]
    fn weekly_drift_flags_over_running_past_the_threshold() {
        let d = weekly_drift(40_000.0, 52_000.0, PLAN_DRIFT_THRESHOLD);
        assert_eq!(d.direction, DriftDirection::Over);
        assert!(d.flagged);
        assert!(d.drift_fraction > PLAN_DRIFT_THRESHOLD);
    }

    #[test]
    fn weekly_drift_just_inside_the_threshold_is_not_flagged() {
        let d = weekly_drift(40_000.0, 47_000.0, PLAN_DRIFT_THRESHOLD);
        assert_eq!(d.direction, DriftDirection::OnTrack);
        assert!(!d.flagged);
    }

    #[test]
    fn weekly_drift_no_planned_volume_yields_neutral_unflagged() {
        let d = weekly_drift(0.0, 30_000.0, PLAN_DRIFT_THRESHOLD);
        assert_eq!(d.direction, DriftDirection::OnTrack);
        assert!(!d.flagged);
        assert_eq!(d.drift_fraction, 0.0);
    }

    #[test]
    fn weekly_drift_clamps_negative_actual_to_zero() {
        let d = weekly_drift(40_000.0, -5.0, PLAN_DRIFT_THRESHOLD);
        assert_eq!(d.actual_metres, 0.0);
        assert_eq!(d.direction, DriftDirection::Under);
    }

    #[test]
    fn missed_workout_advice_base_build_long_run_is_worth_making_up() {
        let a = missed_workout_advice(&MissedWorkoutInput {
            kind: "long",
            is_taper: false,
            recovery_week_imminent: Some(false),
        });
        assert_eq!(a.recommendation, MakeUpRecommendation::MakeUp);
        assert_eq!(a.reason, MissedWorkoutReason::KeySession);
    }

    #[test]
    fn missed_workout_advice_skip_a_long_run_missed_in_the_taper() {
        let a = missed_workout_advice(&MissedWorkoutInput {
            kind: "long",
            is_taper: true,
            recovery_week_imminent: Some(false),
        });
        assert_eq!(a.recommendation, MakeUpRecommendation::Skip);
        assert_eq!(a.reason, MissedWorkoutReason::Taper);
    }

    #[test]
    fn missed_workout_advice_skip_when_a_recovery_week_is_imminent() {
        let a = missed_workout_advice(&MissedWorkoutInput {
            kind: "long",
            is_taper: false,
            recovery_week_imminent: Some(true),
        });
        assert_eq!(a.recommendation, MakeUpRecommendation::Skip);
        assert_eq!(a.reason, MissedWorkoutReason::RecoverySoon);
    }

    #[test]
    fn missed_workout_advice_taper_takes_precedence_over_recovery_soon() {
        let a = missed_workout_advice(&MissedWorkoutInput {
            kind: "long",
            is_taper: true,
            recovery_week_imminent: Some(true),
        });
        assert_eq!(a.reason, MissedWorkoutReason::Taper);
    }

    #[test]
    fn missed_workout_advice_a_missed_quality_session_is_just_skipped() {
        for kind in ["tempo", "interval", "easy", "marathon_pace"] {
            let a = missed_workout_advice(&MissedWorkoutInput {
                kind,
                is_taper: false,
                recovery_week_imminent: Some(false),
            });
            assert_eq!(a.recommendation, MakeUpRecommendation::Skip);
            assert_eq!(a.reason, MissedWorkoutReason::NotLongRun);
        }
    }
}
