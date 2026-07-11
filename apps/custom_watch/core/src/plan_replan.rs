//! Training-plan re-planning around missed sessions — proposes changes to
//! FUTURE workouts only, leaving the frozen past and the sacred taper alone.
//! The caller previews the diff and applies it via the per-row update path.
//!
//! Deliberately conservative, matching the web engine's coach-defensible rules:
//! the past is frozen, taper/race weeks are never touched, missed easy volume
//! is let go (only the long run earns a make-up), a make-up can't spike the
//! next long run past [`MAKE_UP_MAX_INCREASE`], and cumulative over-running
//! triggers a one-week ease-off ([`EASE_OFF_SCALE`]).
//!
//! Parity port of web `training/plan_replan.ts` `replanRemaining` (twin of
//! `apps/mobile_android/lib/plan_replan.dart`) — keep the rules, edge cases,
//! and test count in lockstep. Reuses [`weekly_drift`] +
//! [`missed_workout_advice`] from [`crate::plan_adherence`].
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

use crate::plan_adherence::{
    missed_workout_advice, weekly_drift, DriftDirection, MakeUpRecommendation, MissedWorkoutInput,
    PLAN_DRIFT_THRESHOLD,
};

/// Cap on how far a make-up may stretch the next long run, so honouring a
/// missed 30 km run can't turn a planned 18 km long run into a 30 km spike.
pub const MAKE_UP_MAX_INCREASE: f64 = 0.15;

/// Multiplier applied to the next week's non-long workouts when the runner has
/// been over-running — bleed off accumulated fatigue.
pub const EASE_OFF_SCALE: f64 = 0.85;

/// A plan realistically runs to ~24 weeks; 32 leaves headroom. Extra weeks are
/// dropped rather than allocating.
pub const MAX_REPLAN_WEEKS: usize = 32;

/// At most one make-up plus one week's worth of eased workouts.
pub const MAX_REPLAN_CHANGES: usize = 16;

fn is_taper(phase: &str) -> bool {
    phase == "taper" || phase == "race"
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ReplanWorkout<'a> {
    pub id: &'a str,
    /// ISO scheduled date (YYYY-MM-DD).
    pub scheduled_date: &'a str,
    pub kind: &'a str,
    pub target_distance_m: Option<f64>,
    pub completed: bool,
    /// The runner explicitly dropped this workout (skipped_at stamped) — it's
    /// off the books, so a make-up is never proposed for it.
    pub skipped: bool,
    /// `scheduled_date` strictly before today.
    pub is_past: bool,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ReplanWeek<'a> {
    pub week_index: i32,
    pub phase: &'a str,
    pub planned_metres: f64,
    /// Summed actual run mileage dated inside this week's window.
    pub actual_metres: f64,
    /// Every day in the week is before today.
    pub is_complete: bool,
    pub workouts: &'a [ReplanWorkout<'a>],
}

pub struct ReplanInput<'a> {
    pub weeks: &'a [ReplanWeek<'a>],
    /// ISO today. Carried to mirror the web contract; the caller precomputes
    /// `is_past` / `is_complete`, so the algorithm never reads it directly.
    pub today: &'a str,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ReplanReason {
    MakeUpLong,
    EaseOverRunning,
}

/// The only field a re-plan mutates — future workout distances.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ReplanField {
    TargetDistanceM,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ReplanChange<'a> {
    pub workout_id: &'a str,
    pub scheduled_date: &'a str,
    pub reason: ReplanReason,
    pub field: ReplanField,
    pub from_metres: f64,
    pub to_metres: f64,
}

pub struct ReplanResult<'a> {
    pub changes: Vec<ReplanChange<'a>, MAX_REPLAN_CHANGES>,
    /// True when nothing needs changing — the plan is on track.
    pub on_track: bool,
}

/// Whether a step-back week (a >15% planned-volume drop) immediately follows
/// `weeks[idx]` — mirrors the heuristic the plan-detail adherence surface uses.
fn recovery_week_imminent(weeks: &[ReplanWeek], idx: usize) -> bool {
    let cur = &weeks[idx];
    match weeks.iter().find(|w| w.week_index == cur.week_index + 1) {
        Some(next) if cur.planned_metres > 0.0 && next.planned_metres > 0.0 => {
            next.planned_metres < cur.planned_metres * 0.85
        }
        _ => false,
    }
}

pub fn replan_remaining<'a>(input: &ReplanInput<'a>) -> ReplanResult<'a> {
    let mut weeks: Vec<ReplanWeek<'a>, MAX_REPLAN_WEEKS> = Vec::new();
    for w in input.weeks {
        if weeks.push(*w).is_err() {
            break;
        }
    }
    weeks.sort_unstable_by_key(|w| w.week_index);

    let mut changes: Vec<ReplanChange<'a>, MAX_REPLAN_CHANGES> = Vec::new();

    // ── 1. Missed long runs in past weeks → make up in the future ──
    // The missed run itself is FROZEN (past); it only triggers a forward
    // make-up. With several outstanding misses the make-up honours the LARGEST
    // one (the most demanding session to recover), not whichever came first.
    let mut max_missed_long = 0.0_f64;
    for (i, week) in weeks.iter().enumerate() {
        for wo in week.workouts {
            if wo.kind != "long" || !wo.is_past || wo.completed || wo.skipped {
                continue;
            }
            let advice = missed_workout_advice(&MissedWorkoutInput {
                kind: "long",
                is_taper: is_taper(week.phase),
                recovery_week_imminent: Some(recovery_week_imminent(&weeks, i)),
            });
            if advice.recommendation != MakeUpRecommendation::MakeUp {
                continue;
            }
            let d = wo.target_distance_m.unwrap_or(0.0);
            if d > max_missed_long {
                max_missed_long = d;
            }
        }
    }

    // Earliest future, non-taper long run available to absorb the make-up.
    let mut next_long: Option<&ReplanWorkout<'a>> = None;
    for w in weeks.iter() {
        if is_taper(w.phase) {
            continue;
        }
        for wo in w.workouts {
            if wo.is_past || wo.kind != "long" {
                continue;
            }
            match next_long {
                Some(cur) if wo.scheduled_date < cur.scheduled_date => next_long = Some(wo),
                None => next_long = Some(wo),
                _ => {}
            }
        }
    }

    if let (Some(next_long), true) = (next_long, max_missed_long > 0.0) {
        let planned_next = next_long.target_distance_m.unwrap_or(0.0);
        if planned_next > 0.0 {
            let capped =
                max_missed_long.min(libm::round(planned_next * (1.0 + MAKE_UP_MAX_INCREASE)));
            if capped > planned_next {
                let _ = changes.push(ReplanChange {
                    workout_id: next_long.id,
                    scheduled_date: next_long.scheduled_date,
                    reason: ReplanReason::MakeUpLong,
                    field: ReplanField::TargetDistanceM,
                    from_metres: planned_next,
                    to_metres: capped,
                });
            }
        }
    }

    // ── 2. Cumulative over-running → ease off the next future week ──
    // Use the most recent COMPLETE week as the signal.
    if let Some(last_complete) = weeks.iter().rev().find(|w| w.is_complete) {
        let drift = weekly_drift(
            last_complete.planned_metres,
            last_complete.actual_metres,
            PLAN_DRIFT_THRESHOLD,
        );
        if drift.direction == DriftDirection::Over {
            let next_week = weeks.iter().find(|w| {
                w.week_index > last_complete.week_index
                    && !is_taper(w.phase)
                    && w.workouts.iter().any(|wo| !wo.is_past)
            });
            if let Some(next_week) = next_week {
                for wo in next_week.workouts {
                    if wo.is_past || wo.kind == "rest" || wo.kind == "long" {
                        continue;
                    }
                    let td = match wo.target_distance_m {
                        None => continue,
                        Some(t) => t,
                    };
                    if td <= 0.0 {
                        continue;
                    }
                    if changes.iter().any(|c| c.workout_id == wo.id) {
                        continue;
                    }
                    let _ = changes.push(ReplanChange {
                        workout_id: wo.id,
                        scheduled_date: wo.scheduled_date,
                        reason: ReplanReason::EaseOverRunning,
                        field: ReplanField::TargetDistanceM,
                        from_metres: td,
                        to_metres: libm::round(td * EASE_OFF_SCALE),
                    });
                }
            }
        }
    }

    let on_track = changes.is_empty();
    ReplanResult { changes, on_track }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/plan_replan.test.ts` — same
    /// scenarios, same expected values, so the ports can't drift.
    fn wo<'a>(
        id: &'a str,
        scheduled_date: &'a str,
        kind: &'a str,
        target_distance_m: Option<f64>,
        completed: bool,
        skipped: bool,
        is_past: bool,
    ) -> ReplanWorkout<'a> {
        ReplanWorkout {
            id,
            scheduled_date,
            kind,
            target_distance_m,
            completed,
            skipped,
            is_past,
        }
    }

    fn week<'a>(
        week_index: i32,
        phase: &'a str,
        planned_metres: f64,
        actual_metres: f64,
        is_complete: bool,
        workouts: &'a [ReplanWorkout<'a>],
    ) -> ReplanWeek<'a> {
        ReplanWeek {
            week_index,
            phase,
            planned_metres,
            actual_metres,
            is_complete,
            workouts,
        }
    }

    fn find<'a, 'b>(r: &'b ReplanResult<'a>, id: &str) -> Option<&'b ReplanChange<'a>> {
        r.changes.iter().find(|c| c.workout_id == id)
    }

    #[test]
    fn an_on_track_plan_proposes_no_changes() {
        let w0 = [wo(
            "a",
            "2026-06-01",
            "long",
            Some(20_000.0),
            true,
            false,
            true,
        )];
        let w1 = [wo(
            "b",
            "2026-06-08",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 39_000.0, true, &w0),
            week(1, "build", 42_000.0, 0.0, false, &w1),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-05",
        });
        assert!(r.on_track);
        assert!(r.changes.is_empty());
    }

    #[test]
    fn a_missed_long_run_in_build_is_made_up_capped_15pct() {
        let w0 = [wo(
            "missed",
            "2026-06-01",
            "long",
            Some(28_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "next",
            "2026-06-08",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 20_000.0, true, &w0),
            week(1, "build", 42_000.0, 0.0, false, &w1),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-05",
        });
        assert!(find(&r, "missed").is_none());
        let make_up = find(&r, "next").unwrap();
        assert_eq!(make_up.reason, ReplanReason::MakeUpLong);
        assert_eq!(
            make_up.to_metres,
            libm::round(22_000.0 * (1.0 + MAKE_UP_MAX_INCREASE))
        );
    }

    #[test]
    fn a_make_up_never_shrinks_an_already_longer_next_long_run() {
        let w0 = [wo(
            "missed",
            "2026-06-01",
            "long",
            Some(16_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "next",
            "2026-06-08",
            "long",
            Some(24_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 20_000.0, true, &w0),
            week(1, "build", 42_000.0, 0.0, false, &w1),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-05",
        });
        assert!(r.on_track);
        assert!(r.changes.is_empty());
    }

    #[test]
    fn several_missed_long_runs_make_up_the_largest_not_the_earliest() {
        let w0 = [wo(
            "miss-a",
            "2026-06-01",
            "long",
            Some(24_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "miss-b",
            "2026-06-08",
            "long",
            Some(30_000.0),
            false,
            false,
            true,
        )];
        let w2 = [wo(
            "next",
            "2026-06-15",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 20_000.0, true, &w0),
            week(1, "build", 44_000.0, 22_000.0, true, &w1),
            week(2, "build", 46_000.0, 0.0, false, &w2),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-12",
        });
        let make_up = find(&r, "next").unwrap();
        assert_eq!(make_up.reason, ReplanReason::MakeUpLong);
        assert_eq!(
            make_up.to_metres,
            libm::round(22_000.0 * (1.0 + MAKE_UP_MAX_INCREASE))
        );
        assert_eq!(
            r.changes
                .iter()
                .filter(|c| c.reason == ReplanReason::MakeUpLong)
                .count(),
            1
        );
    }

    #[test]
    fn largest_missed_long_wins_even_when_it_is_the_earliest_week() {
        let w0 = [wo(
            "big",
            "2026-06-01",
            "long",
            Some(30_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "small",
            "2026-06-08",
            "long",
            Some(24_000.0),
            false,
            false,
            true,
        )];
        let w2 = [wo(
            "next",
            "2026-06-15",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 44_000.0, 22_000.0, true, &w0),
            week(1, "build", 40_000.0, 20_000.0, true, &w1),
            week(2, "build", 46_000.0, 0.0, false, &w2),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-12",
        });
        let make_up = find(&r, "next").unwrap();
        assert_eq!(
            make_up.to_metres,
            libm::round(22_000.0 * (1.0 + MAKE_UP_MAX_INCREASE))
        );
        assert_eq!(
            r.changes
                .iter()
                .filter(|c| c.reason == ReplanReason::MakeUpLong)
                .count(),
            1
        );
    }

    #[test]
    fn when_the_largest_miss_is_under_the_cap_the_make_up_reaches_it_exactly() {
        let w0 = [wo(
            "small",
            "2026-06-01",
            "long",
            Some(20_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "mid",
            "2026-06-08",
            "long",
            Some(24_000.0),
            false,
            false,
            true,
        )];
        let w2 = [wo(
            "next",
            "2026-06-15",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 20_000.0, true, &w0),
            week(1, "build", 42_000.0, 21_000.0, true, &w1),
            week(2, "build", 44_000.0, 0.0, false, &w2),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-12",
        });
        let make_up = find(&r, "next").unwrap();
        assert_eq!(make_up.to_metres, 24_000.0);
    }

    #[test]
    fn a_taper_miss_is_excluded_from_the_make_up_max_even_if_largest() {
        let w0 = [wo(
            "build-miss",
            "2026-06-01",
            "long",
            Some(23_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "taper-miss",
            "2026-06-08",
            "long",
            Some(35_000.0),
            false,
            false,
            true,
        )];
        let w2 = [wo(
            "next",
            "2026-06-15",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 20_000.0, true, &w0),
            week(1, "taper", 38_000.0, 10_000.0, true, &w1),
            week(2, "build", 42_000.0, 0.0, false, &w2),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-12",
        });
        let make_up = find(&r, "next").unwrap();
        assert_eq!(make_up.to_metres, 23_000.0);
    }

    #[test]
    fn three_missed_longs_still_produce_exactly_one_capped_make_up() {
        let w0 = [wo(
            "m1",
            "2026-06-01",
            "long",
            Some(18_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "m2",
            "2026-06-08",
            "long",
            Some(31_000.0),
            false,
            false,
            true,
        )];
        let w2 = [wo(
            "m3",
            "2026-06-15",
            "long",
            Some(24_000.0),
            false,
            false,
            true,
        )];
        let w3 = [wo(
            "next",
            "2026-06-22",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 36_000.0, 18_000.0, true, &w0),
            week(1, "build", 44_000.0, 22_000.0, true, &w1),
            week(2, "build", 40_000.0, 20_000.0, true, &w2),
            week(3, "build", 46_000.0, 0.0, false, &w3),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-19",
        });
        let make_ups: Vec<&ReplanChange, MAX_REPLAN_CHANGES> = r
            .changes
            .iter()
            .filter(|c| c.reason == ReplanReason::MakeUpLong)
            .collect();
        assert_eq!(make_ups.len(), 1);
        assert_eq!(
            make_ups[0].to_metres,
            libm::round(22_000.0 * (1.0 + MAKE_UP_MAX_INCREASE))
        );
    }

    #[test]
    fn a_missed_long_run_in_the_taper_is_skipped_never_made_up() {
        let w0 = [wo(
            "missed",
            "2026-06-01",
            "long",
            Some(18_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "race",
            "2026-06-08",
            "race",
            Some(42_195.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "taper", 25_000.0, 10_000.0, true, &w0),
            week(1, "race", 10_000.0, 0.0, false, &w1),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-05",
        });
        assert!(r.on_track);
        assert!(r.changes.is_empty());
    }

    #[test]
    fn an_explicitly_skipped_long_run_is_never_made_up() {
        let w0 = [wo(
            "skipped",
            "2026-06-01",
            "long",
            Some(30_000.0),
            false,
            true,
            true,
        )];
        let w1 = [wo(
            "next",
            "2026-06-08",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 44_000.0, 18_000.0, true, &w0),
            week(1, "build", 46_000.0, 0.0, false, &w1),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-05",
        });
        assert!(!r
            .changes
            .iter()
            .any(|c| c.reason == ReplanReason::MakeUpLong));
        assert!(r.on_track);
        assert!(r.changes.is_empty());
    }

    #[test]
    fn a_skipped_long_is_excluded_but_a_genuine_miss_still_makes_up() {
        let w0 = [wo(
            "genuine-miss",
            "2026-06-01",
            "long",
            Some(23_000.0),
            false,
            false,
            true,
        )];
        let w1 = [wo(
            "skipped",
            "2026-06-08",
            "long",
            Some(35_000.0),
            false,
            true,
            true,
        )];
        let w2 = [wo(
            "next",
            "2026-06-15",
            "long",
            Some(22_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 20_000.0, true, &w0),
            week(1, "build", 48_000.0, 12_000.0, true, &w1),
            week(2, "build", 42_000.0, 0.0, false, &w2),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-12",
        });
        let make_up = find(&r, "next").unwrap();
        assert_eq!(make_up.to_metres, 23_000.0);
    }

    #[test]
    fn cumulative_over_running_eases_the_next_future_week() {
        let w0 = [wo(
            "a",
            "2026-06-01",
            "easy",
            Some(10_000.0),
            true,
            false,
            true,
        )];
        let w1 = [
            wo(
                "tempo",
                "2026-06-08",
                "tempo",
                Some(12_000.0),
                false,
                false,
                false,
            ),
            wo(
                "long",
                "2026-06-13",
                "long",
                Some(22_000.0),
                false,
                false,
                false,
            ),
            wo("rest", "2026-06-09", "rest", None, false, false, false),
        ];
        let weeks = [
            week(0, "build", 40_000.0, 52_000.0, true, &w0),
            week(1, "build", 42_000.0, 0.0, false, &w1),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-05",
        });
        let ease = find(&r, "tempo").unwrap();
        assert_eq!(ease.reason, ReplanReason::EaseOverRunning);
        assert_eq!(ease.to_metres, libm::round(12_000.0 * EASE_OFF_SCALE));
        assert!(find(&r, "long").is_none());
        assert!(find(&r, "rest").is_none());
    }

    #[test]
    fn never_touches_a_past_frozen_future_week_placeholder_or_the_taper() {
        let w0 = [wo(
            "done",
            "2026-06-01",
            "tempo",
            Some(10_000.0),
            true,
            false,
            true,
        )];
        let w1 = [wo(
            "taper-tempo",
            "2026-06-08",
            "tempo",
            Some(8_000.0),
            false,
            false,
            false,
        )];
        let weeks = [
            week(0, "build", 40_000.0, 60_000.0, true, &w0),
            week(1, "taper", 30_000.0, 0.0, false, &w1),
        ];
        let r = replan_remaining(&ReplanInput {
            weeks: &weeks,
            today: "2026-06-05",
        });
        assert!(r.changes.is_empty());
        assert!(r.on_track);
    }
}
