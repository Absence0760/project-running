//! Plan-progress derivations — the two stats the plan-detail header was
//! missing: the longest long run completed so far, and the overall
//! base→build→peak→taper arc the current week sits in.
//!
//! A parity port of web `training/plan_progress.ts` (twin of
//! `plan_progress.dart`). Pure logic — no peripherals, no allocator; the
//! caller formats + localizes the results.
//!
//! **Two of web's four exports are deliberately not ported**, which is why the
//! suites do not match one for one. `planWorkoutProgress` (completed / skipped
//! / remaining, excluding rest days from BOTH the numerator and the denominator
//! so a plan cannot report over 100 %) and `planDistanceBanked` (km run against
//! km planned) each need the plan's whole WORKOUT list. Nothing pushes one: the
//! two plan glance pages this device has, `PlanReplan` and `PlanAdaptive`,
//! render pre-computed views the phone sends over `SET1`, and a workout list is
//! a per-week table with no wire and no room on a 168x96 panel to show it.
//! Porting them would add two functions no page can reach, over data no frame
//! carries — a port made for the count rather than for the wrist (decisions.md
//! § 24). The two that ARE here are ported because the phone sends their
//! INPUTS: a phase list and a long-run distance are single values.
//!
//! The trigger that changes it is a wire carrying the plan's workouts, at which
//! point both come across together — they are the same shape and the same
//! decision.

use heapless::Vec;

/// The distinct phases a plan moves through, in canonical order. Plans don't
/// always use every phase, and the rows aren't guaranteed to be stored in
/// order, so the marker derives its sequence from this rather than row order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PlanPhase {
    Base,
    Build,
    Peak,
    Taper,
    Race,
    Graduation,
}

impl PlanPhase {
    pub const fn name(self) -> &'static str {
        match self {
            PlanPhase::Base => "base",
            PlanPhase::Build => "build",
            PlanPhase::Peak => "peak",
            PlanPhase::Taper => "taper",
            PlanPhase::Race => "race",
            PlanPhase::Graduation => "graduation",
        }
    }

    pub fn from_name(s: &str) -> Option<PlanPhase> {
        match s {
            "base" => Some(PlanPhase::Base),
            "build" => Some(PlanPhase::Build),
            "peak" => Some(PlanPhase::Peak),
            "taper" => Some(PlanPhase::Taper),
            "race" => Some(PlanPhase::Race),
            "graduation" => Some(PlanPhase::Graduation),
            _ => None,
        }
    }
}

/// Canonical phase ordering, mirroring web's `PLAN_PHASE_ORDER`.
pub const PLAN_PHASE_ORDER: [PlanPhase; 6] = [
    PlanPhase::Base,
    PlanPhase::Build,
    PlanPhase::Peak,
    PlanPhase::Taper,
    PlanPhase::Race,
    // The terminal week of every beginner walk-run plan — `generatePlan` stamps
    // it on the last week instead of `race`, so a C25K plan's whole arc is
    // `build` then this. Omitting it did not mis-order the marker, it deleted
    // the ending: `from_name` answered None and the phase was dropped.
    PlanPhase::Graduation,
];

/// The distinct phases the plan moves through, de-duplicated and sorted into
/// canonical order. Unknown phase strings are ignored. Drives the overall
/// phase marker.
pub fn ordered_plan_phases(phases: &[&str]) -> Vec<PlanPhase, 6> {
    let mut out: Vec<PlanPhase, 6> = Vec::new();
    for &phase in PLAN_PHASE_ORDER.iter() {
        if phases
            .iter()
            .any(|p| PlanPhase::from_name(p) == Some(phase))
        {
            let _ = out.push(phase);
        }
    }
    out
}

/// A planned workout, narrowed to just the fields the long-run stat reads.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct LongRunWorkout<'a> {
    pub kind: &'a str,
    pub target_distance_m: Option<f64>,
    pub completed_run_id: Option<&'a str>,
    pub manually_completed: Option<bool>,
}

/// Longest long run completed so far, in metres. Prefers the actual recorded
/// distance of the linked run (looked up by run id via `actual_by_id`); falls
/// back to the workout's planned target when the run isn't found (e.g. it
/// dropped off the recent-runs window). Returns `None` when no long run has
/// been completed yet.
///
/// Pass `|_| None` for the empty-map default.
pub fn longest_completed_long_run_metres(
    workouts: &[LongRunWorkout],
    actual_by_id: impl Fn(&str) -> Option<f64>,
) -> Option<f64> {
    let mut max: Option<f64> = None;
    for w in workouts {
        if w.kind != "long" {
            continue;
        }
        let completed = w.manually_completed == Some(true) || w.completed_run_id.is_some();
        if !completed {
            continue;
        }
        let actual = w.completed_run_id.and_then(&actual_by_id);
        // A non-positive actual (degenerate / distance-less linked run) is
        // treated as missing, falling back to the planned target — keeping a 0
        // would drop the long run from the max entirely.
        let dist = match actual {
            Some(a) if a > 0.0 => a,
            _ => w.target_distance_m.unwrap_or(0.0),
        };
        if dist > 0.0 && max.is_none_or(|m| dist > m) {
            max = Some(dist);
        }
    }
    max
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordered_plan_phases_dedupes_and_sorts_into_canonical_order() {
        let weeks = ["build", "base", "build", "taper", "peak"];
        assert_eq!(
            ordered_plan_phases(&weeks).as_slice(),
            &[
                PlanPhase::Base,
                PlanPhase::Build,
                PlanPhase::Peak,
                PlanPhase::Taper,
            ]
        );
    }

    #[test]
    fn ordered_plan_phases_empty_plan_yields_no_phases() {
        assert!(ordered_plan_phases(&[]).is_empty());
    }

    /// Mirror of web's `orderedPlanPhases: a walk-run plan orders build before
    /// graduation` and its Dart twin. `generatePlan(beginnerWalkRun)` stamps
    /// `graduation` on the terminal week rather than `race`, so this is the
    /// whole arc of every C25K plan — and the phase this port had no name for,
    /// which deleted the ending rather than mis-ordering it.
    #[test]
    fn ordered_plan_phases_a_walk_run_plan_orders_build_before_graduation() {
        assert_eq!(
            ordered_plan_phases(&["graduation", "build", "build"]).as_slice(),
            &[PlanPhase::Build, PlanPhase::Graduation]
        );
    }

    /// The ladder as strings, so a reader comparing this rail against
    /// `PLAN_PHASE_ORDER` in `plan_progress.ts` / `planPhaseOrder` in
    /// `plan_progress.dart` diffs one line — and so a variant added to the enum
    /// without a `from_name` arm fails here rather than silently dropping every
    /// week carrying it.
    #[test]
    fn plan_phase_order_names_the_whole_canonical_ladder_and_round_trips() {
        let names: Vec<&str, 6> = PLAN_PHASE_ORDER.iter().map(|p| p.name()).collect();
        assert_eq!(
            names.as_slice(),
            &["base", "build", "peak", "taper", "race", "graduation"]
        );
        for p in PLAN_PHASE_ORDER.iter() {
            assert_eq!(PlanPhase::from_name(p.name()), Some(*p));
        }
    }

    #[test]
    fn ordered_plan_phases_ignores_unknown_phase_strings() {
        assert_eq!(
            ordered_plan_phases(&["base", "mystery"]).as_slice(),
            &[PlanPhase::Base]
        );
    }

    #[test]
    fn longest_null_when_no_long_run_is_completed() {
        let workouts = [
            LongRunWorkout {
                kind: "long",
                target_distance_m: Some(25_000.0),
                completed_run_id: None,
                manually_completed: None,
            },
            LongRunWorkout {
                kind: "easy",
                target_distance_m: Some(8_000.0),
                completed_run_id: Some("r1"),
                manually_completed: Some(false),
            },
        ];
        assert_eq!(longest_completed_long_run_metres(&workouts, |_| None), None);
    }

    #[test]
    fn longest_picks_the_max_completed_long_run_target() {
        let workouts = [
            LongRunWorkout {
                kind: "long",
                target_distance_m: Some(18_000.0),
                completed_run_id: None,
                manually_completed: Some(true),
            },
            LongRunWorkout {
                kind: "long",
                target_distance_m: Some(28_000.0),
                completed_run_id: None,
                manually_completed: Some(true),
            },
            LongRunWorkout {
                kind: "long",
                target_distance_m: Some(32_000.0),
                completed_run_id: None,
                manually_completed: None,
            },
        ];
        assert_eq!(
            longest_completed_long_run_metres(&workouts, |_| None),
            Some(28_000.0)
        );
    }

    #[test]
    fn longest_prefers_actual_run_distance_over_the_planned_target() {
        let workouts = [LongRunWorkout {
            kind: "long",
            target_distance_m: Some(30_000.0),
            completed_run_id: Some("r1"),
            manually_completed: None,
        }];
        let actual = |id: &str| if id == "r1" { Some(31_200.0) } else { None };
        assert_eq!(
            longest_completed_long_run_metres(&workouts, actual),
            Some(31_200.0)
        );
    }

    #[test]
    fn longest_falls_back_to_target_when_the_run_is_off_window() {
        let workouts = [LongRunWorkout {
            kind: "long",
            target_distance_m: Some(30_000.0),
            completed_run_id: Some("r-old"),
            manually_completed: None,
        }];
        assert_eq!(
            longest_completed_long_run_metres(&workouts, |_| None),
            Some(30_000.0)
        );
    }

    #[test]
    fn longest_zero_distance_linked_run_falls_back_to_the_planned_target() {
        let workouts = [LongRunWorkout {
            kind: "long",
            target_distance_m: Some(30_000.0),
            completed_run_id: Some("r1"),
            manually_completed: None,
        }];
        let actual = |id: &str| if id == "r1" { Some(0.0) } else { None };
        assert_eq!(
            longest_completed_long_run_metres(&workouts, actual),
            Some(30_000.0)
        );
    }

    #[test]
    fn longest_zero_distance_linked_run_does_not_beat_a_real_longer_run() {
        let workouts = [
            LongRunWorkout {
                kind: "long",
                target_distance_m: Some(18_000.0),
                completed_run_id: Some("r1"),
                manually_completed: None,
            },
            LongRunWorkout {
                kind: "long",
                target_distance_m: Some(22_000.0),
                completed_run_id: Some("r2"),
                manually_completed: None,
            },
        ];
        let actual = |id: &str| match id {
            "r1" => Some(0.0),
            "r2" => Some(24_000.0),
            _ => None,
        };
        assert_eq!(
            longest_completed_long_run_metres(&workouts, actual),
            Some(24_000.0)
        );
    }

    #[test]
    fn longest_ignores_non_long_completed_workouts() {
        let workouts = [
            LongRunWorkout {
                kind: "tempo",
                target_distance_m: Some(40_000.0),
                completed_run_id: None,
                manually_completed: Some(true),
            },
            LongRunWorkout {
                kind: "long",
                target_distance_m: Some(12_000.0),
                completed_run_id: None,
                manually_completed: Some(true),
            },
        ];
        assert_eq!(
            longest_completed_long_run_metres(&workouts, |_| None),
            Some(12_000.0)
        );
    }
}
