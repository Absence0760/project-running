//! Adaptive re-plan (plan generator v2). Where [`replan_remaining`] reacts to a
//! single signal (a missed long run, last week over), this gates a re-plan on a
//! MULTI-WEEK adherence TREND: it only proposes changes when the last few
//! completed weeks show a sustained drift, suppressing the single-week noise the
//! manual re-plan would act on. This layer decides WHETHER and WHY; the shipped
//! engine decides WHAT — the past + taper stay frozen because
//! [`replan_remaining`] already freezes them.
//!
//! P2 gate (a faithful port; the web source lives on a CISO-gated branch): an
//! optional `fitness` input adds a DIRECTION GATE — an "you've under-run, do
//! more" trend is suppressed for a fatigued runner (`tsb < 0`), because piling
//! volume onto a fatigue hole is wrong. Only the sign of `tsb` is read.
//!
//! Parity port of web `training/plan_adaptive_replan.ts` `adaptiveReplanRemaining`
//! (twin of `apps/mobile_android/lib/plan_adaptive_replan.dart`) — keep the
//! rules, edge cases, and test count in lockstep. Reuses
//! [`crate::plan_adherence::weekly_drift`] + [`crate::plan_replan::replan_remaining`].
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

use crate::plan_adherence::{weekly_drift, DriftDirection, PLAN_DRIFT_THRESHOLD};
use crate::plan_replan::{
    replan_remaining, ReplanChange, ReplanInput, ReplanWeek, MAX_REPLAN_CHANGES, MAX_REPLAN_WEEKS,
};

/// How many trailing COMPLETED weeks define the trend.
pub const ADAPTIVE_TREND_WINDOW: usize = 3;

/// At least this many flagged weeks (in one direction) within the window make
/// a trend. Two-of-three is the "sustained, not noise" bar.
pub const ADAPTIVE_TREND_MIN: usize = 2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AdaptiveReason {
    TrendUnderfitness,
    TrendOvertraining,
    OnTrack,
}

/// How strongly the window agrees with the trend direction.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AdaptiveConfidence {
    High,
    Medium,
    Low,
}

/// The runner's current training-load state, sourced from the already-computed
/// [`crate::training_load`] series. Only the sign of `tsb` (form) is consulted.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct AdaptiveFitness {
    /// Training Stress Balance (form). Negative = fatigued.
    pub tsb: f64,
    /// Acute load (fatigue).
    pub atl: f64,
    /// Chronic load (fitness).
    pub ctl: f64,
}

pub struct AdaptiveReplanInput<'a> {
    pub weeks: &'a [ReplanWeek<'a>],
    /// ISO today. Passed through to [`replan_remaining`]; the trend is read
    /// off the caller-precomputed `is_complete` flags, not off this string.
    pub today: &'a str,
    /// Current fitness/fatigue (P2, gated). `None` for the P1 behaviour.
    pub fitness: Option<AdaptiveFitness>,
}

pub struct AdaptiveReplanResult<'a> {
    pub changes: Vec<ReplanChange<'a>, MAX_REPLAN_CHANGES>,
    pub reason: AdaptiveReason,
    pub confidence: AdaptiveConfidence,
    pub on_track: bool,
    pub trailing_directions: Vec<DriftDirection, ADAPTIVE_TREND_WINDOW>,
    /// True when a would-be add-volume suggestion was withheld because the
    /// fitness signal contradicts the adherence trend (fatigued runner).
    pub fitness_gated: bool,
}

/// Classify the trailing completed weeks' adherence trend and, when a sustained
/// drift is found, return the future-only changes [`replan_remaining`] would
/// make. Fails toward on-track whenever a trend can't be established. When
/// `fitness` is supplied, an under-fitness ramp is suppressed for a fatigued
/// runner.
pub fn adaptive_replan_remaining<'a>(input: &AdaptiveReplanInput<'a>) -> AdaptiveReplanResult<'a> {
    let mut sorted: Vec<ReplanWeek<'a>, MAX_REPLAN_WEEKS> = Vec::new();
    for w in input.weeks {
        if sorted.push(*w).is_err() {
            break;
        }
    }
    sorted.sort_unstable_by_key(|w| w.week_index);

    let mut completed: Vec<ReplanWeek<'a>, MAX_REPLAN_WEEKS> = Vec::new();
    for w in sorted.iter() {
        if w.is_complete && w.planned_metres > 0.0 {
            let _ = completed.push(*w);
        }
    }
    let start = completed.len().saturating_sub(ADAPTIVE_TREND_WINDOW);
    let window = &completed[start..];

    let mut trailing_directions: Vec<DriftDirection, ADAPTIVE_TREND_WINDOW> = Vec::new();
    let mut under = 0usize;
    let mut over = 0usize;
    for w in window {
        let d = weekly_drift(w.planned_metres, w.actual_metres, PLAN_DRIFT_THRESHOLD);
        let _ = trailing_directions.push(d.direction);
        if d.flagged && d.direction == DriftDirection::Under {
            under += 1;
        } else if d.flagged && d.direction == DriftDirection::Over {
            over += 1;
        }
    }

    let mut reason = AdaptiveReason::OnTrack;
    if under >= ADAPTIVE_TREND_MIN && under > over {
        reason = AdaptiveReason::TrendUnderfitness;
    } else if over >= ADAPTIVE_TREND_MIN && over > under {
        reason = AdaptiveReason::TrendOvertraining;
    }

    if reason == AdaptiveReason::TrendUnderfitness {
        if let Some(f) = input.fitness {
            if f.tsb < 0.0 {
                return AdaptiveReplanResult {
                    changes: Vec::new(),
                    reason: AdaptiveReason::OnTrack,
                    confidence: AdaptiveConfidence::Low,
                    on_track: true,
                    trailing_directions,
                    fitness_gated: true,
                };
            }
        }
    }

    if reason == AdaptiveReason::OnTrack {
        return AdaptiveReplanResult {
            changes: Vec::new(),
            reason,
            confidence: AdaptiveConfidence::Low,
            on_track: true,
            trailing_directions,
            fitness_gated: false,
        };
    }

    let agree = if reason == AdaptiveReason::TrendUnderfitness {
        under
    } else {
        over
    };
    let confidence = if agree >= window.len() {
        AdaptiveConfidence::High
    } else {
        AdaptiveConfidence::Medium
    };

    let result = replan_remaining(&ReplanInput {
        weeks: input.weeks,
        today: input.today,
    });
    let on_track = result.changes.is_empty();
    AdaptiveReplanResult {
        changes: result.changes,
        reason,
        confidence,
        on_track,
        trailing_directions,
        fitness_gated: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plan_replan::{ReplanReason, ReplanWorkout};

    /// Mirror of `apps/web/src/lib/training/plan_adaptive_replan.test.ts` — same
    /// scenarios, same expected values, so the ports can't drift.
    #[derive(Clone, Copy)]
    enum Drift {
        Under,
        Over,
        OnTrack,
    }

    fn wo<'a>(
        id: &'a str,
        scheduled_date: &'a str,
        kind: &'a str,
        target_distance_m: Option<f64>,
        is_past: bool,
    ) -> ReplanWorkout<'a> {
        ReplanWorkout {
            id,
            scheduled_date,
            kind,
            target_distance_m,
            completed: false,
            skipped: false,
            is_past,
        }
    }

    fn week<'a>(
        week_index: i32,
        drift: Drift,
        phase: &'a str,
        workouts: &'a [ReplanWorkout<'a>],
    ) -> ReplanWeek<'a> {
        let planned_metres = 40_000.0;
        let actual_metres = match drift {
            Drift::Under => 26_000.0,
            Drift::Over => 54_000.0,
            Drift::OnTrack => 39_000.0,
        };
        ReplanWeek {
            week_index,
            phase,
            planned_metres,
            actual_metres,
            is_complete: true,
            workouts,
        }
    }

    fn has_change(r: &AdaptiveReplanResult, id: &str, reason: ReplanReason) -> bool {
        r.changes
            .iter()
            .any(|c| c.workout_id == id && c.reason == reason)
    }

    #[test]
    fn on_track_when_fewer_than_two_weeks_drift() {
        let weeks = [
            week(0, Drift::OnTrack, "build", &[]),
            week(1, Drift::Over, "build", &[]),
            week(2, Drift::OnTrack, "build", &[]),
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: None,
        });
        assert_eq!(r.reason, AdaptiveReason::OnTrack);
        assert_eq!(r.confidence, AdaptiveConfidence::Low);
        assert!(r.on_track);
        assert!(r.changes.is_empty());
    }

    #[test]
    fn a_single_noisy_week_does_not_trigger_a_trend() {
        let weeks = [
            week(0, Drift::OnTrack, "build", &[]),
            week(1, Drift::OnTrack, "build", &[]),
            week(2, Drift::Under, "build", &[]),
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: None,
        });
        assert_eq!(r.reason, AdaptiveReason::OnTrack);
        assert!(r.changes.is_empty());
    }

    #[test]
    fn two_of_three_under_weeks_trend_underfitness_medium_confidence() {
        let w0 = [wo("missed", "2026-06-15", "long", Some(28_000.0), true)];
        let w3 = [wo("next", "2026-07-06", "long", Some(22_000.0), false)];
        let weeks = [
            week(0, Drift::Under, "build", &w0),
            week(1, Drift::OnTrack, "build", &[]),
            week(2, Drift::Under, "build", &[]),
            ReplanWeek {
                week_index: 3,
                phase: "build",
                planned_metres: 42_000.0,
                actual_metres: 0.0,
                is_complete: false,
                workouts: &w3,
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: None,
        });
        assert_eq!(r.reason, AdaptiveReason::TrendUnderfitness);
        assert_eq!(r.confidence, AdaptiveConfidence::Medium);
        assert!(!r.on_track);
        assert!(has_change(&r, "next", ReplanReason::MakeUpLong));
    }

    #[test]
    fn three_of_three_under_weeks_high_confidence() {
        let w0 = [wo("missed", "2026-06-15", "long", Some(28_000.0), true)];
        let w3 = [wo("next", "2026-07-06", "long", Some(22_000.0), false)];
        let weeks = [
            week(0, Drift::Under, "build", &w0),
            week(1, Drift::Under, "build", &[]),
            week(2, Drift::Under, "build", &[]),
            ReplanWeek {
                week_index: 3,
                phase: "build",
                planned_metres: 42_000.0,
                actual_metres: 0.0,
                is_complete: false,
                workouts: &w3,
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: None,
        });
        assert_eq!(r.reason, AdaptiveReason::TrendUnderfitness);
        assert_eq!(r.confidence, AdaptiveConfidence::High);
    }

    #[test]
    fn two_of_three_over_weeks_trend_overtraining_with_an_ease_off_change() {
        let w3 = [wo("easy", "2026-07-07", "easy", Some(8_000.0), false)];
        let weeks = [
            week(0, Drift::Over, "build", &[]),
            week(1, Drift::OnTrack, "build", &[]),
            week(2, Drift::Over, "build", &[]),
            ReplanWeek {
                week_index: 3,
                phase: "build",
                planned_metres: 42_000.0,
                actual_metres: 0.0,
                is_complete: false,
                workouts: &w3,
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: None,
        });
        assert_eq!(r.reason, AdaptiveReason::TrendOvertraining);
        assert!(has_change(&r, "easy", ReplanReason::EaseOverRunning));
    }

    #[test]
    fn a_flagged_under_trend_with_no_safe_change_stays_change_free() {
        let w3 = [wo("f", "2026-07-06", "easy", Some(8_000.0), false)];
        let weeks = [
            week(0, Drift::Under, "build", &[]),
            week(1, Drift::Under, "build", &[]),
            week(2, Drift::Under, "build", &[]),
            ReplanWeek {
                week_index: 3,
                phase: "build",
                planned_metres: 42_000.0,
                actual_metres: 0.0,
                is_complete: false,
                workouts: &w3,
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: None,
        });
        assert_eq!(r.reason, AdaptiveReason::TrendUnderfitness);
        assert!(r.changes.is_empty());
        assert!(r.on_track);
    }

    #[test]
    fn in_progress_and_zero_planned_weeks_are_excluded_from_the_window() {
        let weeks = [
            ReplanWeek {
                week_index: 0,
                phase: "base",
                planned_metres: 0.0,
                actual_metres: 30_000.0,
                is_complete: true,
                workouts: &[],
            },
            week(1, Drift::Under, "build", &[]),
            ReplanWeek {
                week_index: 2,
                phase: "build",
                planned_metres: 40_000.0,
                actual_metres: 12_000.0,
                is_complete: false,
                workouts: &[],
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: None,
        });
        assert_eq!(r.reason, AdaptiveReason::OnTrack);
        assert_eq!(r.trailing_directions.len(), 1);
    }

    #[test]
    fn an_under_fitness_trend_is_suppressed_for_a_fatigued_runner() {
        let w0 = [wo("missed", "2026-06-15", "long", Some(28_000.0), true)];
        let w3 = [wo("next", "2026-07-06", "long", Some(22_000.0), false)];
        let weeks = [
            week(0, Drift::Under, "build", &w0),
            week(1, Drift::Under, "build", &[]),
            week(2, Drift::Under, "build", &[]),
            ReplanWeek {
                week_index: 3,
                phase: "build",
                planned_metres: 42_000.0,
                actual_metres: 0.0,
                is_complete: false,
                workouts: &w3,
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: Some(AdaptiveFitness {
                tsb: -18.0,
                atl: 90.0,
                ctl: 72.0,
            }),
        });
        assert_eq!(r.reason, AdaptiveReason::OnTrack);
        assert!(r.fitness_gated);
        assert!(r.changes.is_empty());
    }

    #[test]
    fn an_under_fitness_trend_proceeds_for_a_fresh_runner() {
        let w0 = [wo("missed", "2026-06-15", "long", Some(28_000.0), true)];
        let w3 = [wo("next", "2026-07-06", "long", Some(22_000.0), false)];
        let weeks = [
            week(0, Drift::Under, "build", &w0),
            week(1, Drift::Under, "build", &[]),
            week(2, Drift::Under, "build", &[]),
            ReplanWeek {
                week_index: 3,
                phase: "build",
                planned_metres: 42_000.0,
                actual_metres: 0.0,
                is_complete: false,
                workouts: &w3,
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: Some(AdaptiveFitness {
                tsb: 6.0,
                atl: 60.0,
                ctl: 66.0,
            }),
        });
        assert_eq!(r.reason, AdaptiveReason::TrendUnderfitness);
        assert!(!r.fitness_gated);
        assert!(r.changes.iter().any(|c| c.workout_id == "next"));
    }

    #[test]
    fn an_over_training_trend_is_not_fitness_gated_even_when_fatigued() {
        let w3 = [wo("easy", "2026-07-07", "easy", Some(8_000.0), false)];
        let weeks = [
            week(0, Drift::Over, "build", &[]),
            week(1, Drift::OnTrack, "build", &[]),
            week(2, Drift::Over, "build", &[]),
            ReplanWeek {
                week_index: 3,
                phase: "build",
                planned_metres: 42_000.0,
                actual_metres: 0.0,
                is_complete: false,
                workouts: &w3,
            },
        ];
        let r = adaptive_replan_remaining(&AdaptiveReplanInput {
            weeks: &weeks,
            today: "2026-07-01",
            fitness: Some(AdaptiveFitness {
                tsb: -22.0,
                atl: 100.0,
                ctl: 78.0,
            }),
        });
        assert_eq!(r.reason, AdaptiveReason::TrendOvertraining);
        assert!(!r.fitness_gated);
    }
}
