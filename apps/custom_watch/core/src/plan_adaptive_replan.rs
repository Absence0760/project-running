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
//! volume onto a fatigue hole is wrong. Only the sign of `tsb` is read there.
//!
//! **The same input also arms a DELOAD OVERRIDE**, gated on both
//! [`ADAPTIVE_DEEP_FATIGUE_TSB`] and [`ADAPTIVE_HIGH_ACWR`] (decisions §1029).
//! This arm was missing from the port until 2026-09-03 while the header above
//! claimed the P2 gate was faithful: the gate is one of web's three arms, and
//! the one it left out is the only branch where the runner is at genuine risk.
//! It is checked BEFORE the adherence arms and never adds volume, so it is a
//! strict tightening of them rather than a competing rule.
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
    ease_off_next_week, replan_remaining, ReplanChange, ReplanInput, ReplanWeek,
    MAX_REPLAN_CHANGES, MAX_REPLAN_WEEKS,
};

/// How many trailing COMPLETED weeks define the trend.
pub const ADAPTIVE_TREND_WINDOW: usize = 3;

/// At least this many flagged weeks (in one direction) within the window make
/// a trend. Two-of-three is the "sustained, not noise" bar.
pub const ADAPTIVE_TREND_MIN: usize = 2;

/// TSB at or below this counts as DEEPLY negative — form is in the hole, not
/// merely down after one hard week. The conventional reading of the CTL/ATL/TSB
/// model puts -10..-25 in the productive-training band and past -25 into
/// overreaching, so that is where "stop adding, start bleeding" sits.
pub const ADAPTIVE_DEEP_FATIGUE_TSB: f64 = -25.0;

/// Acute:chronic workload ratio at or above which acute load counts as HIGH
/// against the base the runner has actually absorbed. 1.3 is the conventional
/// injury-risk threshold. Required alongside the TSB floor so a runner whose
/// whole load is simply large (high ATL and high CTL together) isn't told to
/// deload — only one carrying acute load their chronic base doesn't support.
pub const ADAPTIVE_HIGH_ACWR: f64 = 1.3;

/// Discriminants are pinned to the `PlanAdaptiveView` wire codes (see
/// [`crate::record::PlanAdaptiveView::trend_code`]) so a cast and the codec
/// cannot disagree — the two trend directions are opposite advice. Declaration
/// order is unchanged; only the numbering is fixed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AdaptiveReason {
    TrendUnderfitness = 1,
    TrendOvertraining = 2,
    /// The fitness signal overrode the adherence direction to a deload.
    DeloadFatigue = 3,
    OnTrack = 0,
}

/// How strongly the window agrees with the trend direction. Discriminants are
/// pinned to the low → high wire ladder in
/// [`crate::record::PlanAdaptiveView::confidence_code`], which runs opposite to
/// this declaration order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AdaptiveConfidence {
    High = 2,
    Medium = 1,
    Low = 0,
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
    /// fitness signal contradicts the adherence trend (fatigued runner) and
    /// nothing is proposed in its place. A deload override reports its outcome
    /// through `reason` instead.
    pub fitness_gated: bool,
}

/// Deeply fatigued: form in the hole AND acute load high against a real chronic
/// base. A non-finite or absent chronic base fails closed — a runner with no
/// chronic base has nothing for acute load to be "high" against, and dividing
/// by it would manufacture a deload out of someone who has barely trained.
fn is_deeply_fatigued(f: &AdaptiveFitness) -> bool {
    if !f.tsb.is_finite() || !f.atl.is_finite() || !f.ctl.is_finite() {
        return false;
    }
    // Finiteness is settled above, so this is web's `!(ctl > 0)` without the
    // negated partial comparison clippy refuses: a NaN cannot reach here.
    if f.ctl <= 0.0 {
        return false;
    }
    f.tsb <= ADAPTIVE_DEEP_FATIGUE_TSB && f.atl >= f.ctl * ADAPTIVE_HIGH_ACWR
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

    // P2 arm 2 — the deep-fatigue DELOAD OVERRIDE. Checked before the
    // adherence arms because it is the only branch where the runner is at
    // genuine risk: whatever the plan says they ran, the load says bleed it
    // off. It never adds volume (the make-up pass is skipped entirely), so it
    // is a strict tightening of arm 1 rather than a competing rule.
    if input.fitness.is_some_and(|f| is_deeply_fatigued(&f)) {
        let after = sorted
            .iter()
            .rev()
            .find(|w| w.is_complete)
            .map_or(-1, |w| w.week_index);
        let changes = ease_off_next_week(&sorted, after, &[]);
        let on_track = changes.is_empty();
        return AdaptiveReplanResult {
            changes,
            reason: AdaptiveReason::DeloadFatigue,
            // The load signal crossed both thresholds — nothing about the week
            // window makes it more or less certain.
            confidence: AdaptiveConfidence::High,
            on_track,
            trailing_directions,
            fitness_gated: false,
        };
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
    #[derive(Clone, Copy, Debug)]
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

    /// Arm 2 — the deload override the port was missing. The adherence trend
    /// says the runner has UNDER-run (do more), and the load signal overrides
    /// it to a deload: form in the hole and acute load high against the base
    /// they have absorbed. The arm that used to be missing is the only one
    /// where the runner is at genuine risk.
    #[test]
    fn deep_fatigue_overrides_an_under_trend_to_a_deload() {
        let w3 = [
            wo("easy", "2026-07-07", "easy", Some(8_000.0), false),
            wo("long", "2026-07-11", "long", Some(24_000.0), false),
        ];
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
            fitness: Some(AdaptiveFitness {
                tsb: ADAPTIVE_DEEP_FATIGUE_TSB,
                atl: 100.0,
                ctl: 100.0 / ADAPTIVE_HIGH_ACWR,
            }),
        });
        assert_eq!(r.reason, AdaptiveReason::DeloadFatigue);
        assert_eq!(r.confidence, AdaptiveConfidence::High);
        assert!(
            !r.fitness_gated,
            "a deload reports through `reason`; `fitness_gated` is for a \
             suggestion withheld with nothing proposed in its place"
        );
        // It eases, and it never ADDS: the long run is left alone even though
        // an under-trend would otherwise want more of it.
        assert!(has_change(&r, "easy", ReplanReason::EaseOverRunning));
        assert!(r.changes.iter().all(|c| c.workout_id != "long"));
        assert!(r
            .changes
            .iter()
            .all(|c| c.reason == ReplanReason::EaseOverRunning));
        assert!(!r.on_track);
    }

    /// It overrides an OVER-trend too — the direction is irrelevant, which is
    /// why the arm is checked before both adherence arms rather than beside
    /// them.
    #[test]
    fn deep_fatigue_outranks_the_adherence_direction_either_way() {
        let w3 = [wo("easy", "2026-07-07", "easy", Some(8_000.0), false)];
        let fatigued = Some(AdaptiveFitness {
            tsb: -40.0,
            atl: 90.0,
            ctl: 50.0,
        });
        for drift in [Drift::Under, Drift::Over, Drift::OnTrack] {
            let weeks = [
                week(0, drift, "build", &[]),
                week(1, drift, "build", &[]),
                week(2, drift, "build", &[]),
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
                fitness: fatigued,
            });
            assert_eq!(r.reason, AdaptiveReason::DeloadFatigue, "{drift:?}");
        }
    }

    /// Both thresholds are required, and a runner with no chronic base fails
    /// closed. A big negative TSB alone is a hard week; acute load alone is a
    /// runner whose whole load is simply large. Neither is a deload.
    #[test]
    fn one_threshold_alone_is_not_deep_fatigue() {
        let w3 = [wo("easy", "2026-07-07", "easy", Some(8_000.0), false)];
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
        let not_fatigued = [
            // Form in the hole, but acute load is not high against the base.
            AdaptiveFitness {
                tsb: -40.0,
                atl: 50.0,
                ctl: 100.0,
            },
            // Acute load high, but form is only mildly down.
            AdaptiveFitness {
                tsb: -5.0,
                atl: 200.0,
                ctl: 100.0,
            },
            // Just inside both thresholds.
            AdaptiveFitness {
                tsb: ADAPTIVE_DEEP_FATIGUE_TSB + 0.1,
                atl: 100.0,
                ctl: 100.0 / ADAPTIVE_HIGH_ACWR,
            },
            // No chronic base: nothing for acute load to be "high" against.
            AdaptiveFitness {
                tsb: -40.0,
                atl: 90.0,
                ctl: 0.0,
            },
            // Non-finite reads fail closed rather than comparing their way in.
            AdaptiveFitness {
                tsb: f64::NAN,
                atl: 90.0,
                ctl: 50.0,
            },
            AdaptiveFitness {
                tsb: -40.0,
                atl: f64::INFINITY,
                ctl: 50.0,
            },
            AdaptiveFitness {
                tsb: -40.0,
                atl: 90.0,
                ctl: f64::NAN,
            },
        ];
        for f in not_fatigued {
            let r = adaptive_replan_remaining(&AdaptiveReplanInput {
                weeks: &weeks,
                today: "2026-07-01",
                fitness: Some(f),
            });
            assert_ne!(
                r.reason,
                AdaptiveReason::DeloadFatigue,
                "tsb {} atl {} ctl {}",
                f.tsb,
                f.atl,
                f.ctl
            );
        }
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
