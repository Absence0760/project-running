//! Re-link candidate selection — which of a runner's runs may be re-linked to a
//! planned workout, and in what order.
//!
//! Parity port of the web canonical
//! `apps/web/src/lib/training/relink_candidates.ts` (twin of
//! `apps/mobile_android/lib/relink_candidates.dart`) — the same
//! `filterRelinkCandidates`: a run is eligible when it is in-window (within
//! ±`window_days` of the scheduled date) AND not already linked to a
//! *different* workout, so `plan_progress` can never double-count one run
//! against two workouts. The workout's own current pick stays selectable
//! regardless of window so the current row is always visible.
//!
//! **Ordering is newest-DAY-first, and within a day it is the caller's own
//! order.** Web and Dart sort on the full `started_at` instant, so a double day
//! puts the evening run above the morning one; this rail is handed a day index
//! and nothing finer, so there is nothing here to order that pair BY. What it
//! can do — and does — is not scramble them: the sort below is stable, so two
//! runs on one day come out in the order the phone sent them, which is the
//! phone's own newest-first list. An unstable sort would have reordered them
//! against it, which is the one difference this collapse did not have to have.
//!
//! The one representational change from the canonical helper: web/Dart parse
//! `started_at` / `scheduled_date` from ISO into `Date`s and take a
//! UTC-anchored calendar-day gap (the whole reason the web helper carries a DST
//! comment). Neither ISO parsing nor a timezone database belongs in a `no_std`
//! firmware core, so here a run carries a plain **day index**
//! ([`RelinkCandidateRun::day`]) and the workout a `scheduled_day` — integer
//! counts of calendar days from any fixed epoch. Only the day *difference*
//! matters, so this is the honest collapse of the web's day-gap math, and the
//! DST subtlety disappears entirely: an exact 8-day gap is simply `8`. Every
//! test scenario maps a web `Date` offset to a day offset one-for-one.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

/// Default half-window in days around the scheduled date. A run started within
/// ±`DEFAULT_RELINK_WINDOW_DAYS` of the scheduled date is in-window.
pub const DEFAULT_RELINK_WINDOW_DAYS: i32 = 7;

/// Max candidates the picker emits. A single runner's few-week window never
/// approaches this; extra runs beyond the cap are dropped rather than grown
/// unboundedly on a device with no allocator.
pub const MAX_RELINK_CANDIDATES: usize = 64;

/// One run offered (or not) to the re-link picker. Mirrors the web
/// `RelinkCandidateRun`; `distance_m` / `duration_s` are carried through
/// untouched for the caller's row rendering.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RelinkCandidateRun<'a> {
    pub id: &'a str,
    /// Calendar-day index the run started on (days from any fixed epoch).
    pub day: i32,
    pub distance_m: f64,
    pub duration_s: f64,
}

/// Inputs for [`filter_relink_candidates`], mirroring the web `RelinkFilterInput`.
pub struct RelinkFilterInput<'a> {
    /// The owner's runs, any order.
    pub runs: &'a [RelinkCandidateRun<'a>],
    /// Run ids already linked to ANY of the owner's plan workouts — including
    /// the workout being re-linked.
    pub linked_run_ids: &'a [&'a str],
    /// The workout's current pick, if any. It lives in `linked_run_ids` but
    /// stays selectable so the picker can show (and re-confirm) it.
    pub current_run_id: Option<&'a str>,
    /// The workout's scheduled calendar-day index.
    pub scheduled_day: i32,
    /// Half-window in days; `None` falls back to [`DEFAULT_RELINK_WINDOW_DAYS`].
    pub window_days: Option<i32>,
}

/// True when a run is linked to a *different* workout — the current pick is
/// exempt so it stays offered.
fn linked_to_other(id: &str, linked: &[&str], current: Option<&str>) -> bool {
    if current == Some(id) {
        return false;
    }
    linked.contains(&id)
}

/// Eligible re-link candidates for a workout, newest-first.
pub fn filter_relink_candidates<'a>(
    input: &RelinkFilterInput<'a>,
) -> Vec<RelinkCandidateRun<'a>, MAX_RELINK_CANDIDATES> {
    let window = input.window_days.unwrap_or(DEFAULT_RELINK_WINDOW_DAYS);
    let mut out: Vec<RelinkCandidateRun<'a>, MAX_RELINK_CANDIDATES> = Vec::new();

    for r in input.runs {
        if linked_to_other(r.id, input.linked_run_ids, input.current_run_id) {
            continue;
        }
        let eligible =
            input.current_run_id == Some(r.id) || (r.day - input.scheduled_day).abs() <= window;
        if eligible && out.push(*r).is_err() {
            break;
        }
    }

    sort_by_day_desc(&mut out);
    out
}

/// Descending by day, STABLE. `slice::sort` lives in `alloc`, and `core` offers
/// only `sort_unstable`, so the stability the ordering contract above depends on
/// is written out: swapping only on a strict `<` leaves an equal-day pair in the
/// order it arrived.
fn sort_by_day_desc(runs: &mut [RelinkCandidateRun]) {
    for i in 1..runs.len() {
        let mut j = i;
        while j > 0 && runs[j - 1].day < runs[j].day {
            runs.swap(j - 1, j);
            j -= 1;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(id: &str, day: i32) -> RelinkCandidateRun<'_> {
        RelinkCandidateRun {
            id,
            day,
            distance_m: 5000.0,
            duration_s: 1800.0,
        }
    }

    fn ids<'a>(out: &[RelinkCandidateRun<'a>]) -> heapless::Vec<&'a str, MAX_RELINK_CANDIDATES> {
        out.iter().map(|r| r.id).collect()
    }

    #[test]
    fn returns_in_window_runs_newest_first() {
        let runs = [run("a", 0), run("b", 2), run("c", -2)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &[],
            current_run_id: None,
            scheduled_day: 0,
            window_days: None,
        });
        assert_eq!(ids(&out).as_slice(), &["b", "a", "c"]);
    }

    #[test]
    fn excludes_runs_outside_the_window() {
        let runs = [run("near", 1), run("far", 15)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &[],
            current_run_id: None,
            scheduled_day: 0,
            window_days: Some(7),
        });
        assert_eq!(ids(&out).as_slice(), &["near"]);
    }

    #[test]
    fn boundary_day_is_in_window_inclusive() {
        let runs = [run("edge", 7)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &[],
            current_run_id: None,
            scheduled_day: 0,
            window_days: Some(7),
        });
        assert_eq!(ids(&out).as_slice(), &["edge"]);
    }

    #[test]
    fn one_day_past_the_boundary_is_excluded() {
        let runs = [run("past", 8)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &[],
            current_run_id: None,
            scheduled_day: 0,
            window_days: Some(7),
        });
        assert!(out.is_empty());
    }

    #[test]
    fn excludes_a_run_linked_to_another_workout() {
        let runs = [run("linked-elsewhere", 0), run("free", 0)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &["linked-elsewhere"],
            current_run_id: None,
            scheduled_day: 0,
            window_days: None,
        });
        assert_eq!(ids(&out).as_slice(), &["free"]);
    }

    #[test]
    fn keeps_the_workouts_own_current_run_even_though_linked() {
        let runs = [run("current", 0), run("other-linked", 0)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &["current", "other-linked"],
            current_run_id: Some("current"),
            scheduled_day: 0,
            window_days: None,
        });
        assert_eq!(ids(&out).as_slice(), &["current"]);
    }

    #[test]
    fn the_current_run_stays_visible_even_when_out_of_window() {
        let runs = [run("current-far", 26)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &["current-far"],
            current_run_id: Some("current-far"),
            scheduled_day: 0,
            window_days: Some(7),
        });
        assert_eq!(ids(&out).as_slice(), &["current-far"]);
    }

    #[test]
    fn empty_runs_yields_empty() {
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &[],
            linked_run_ids: &["x"],
            current_run_id: Some("x"),
            scheduled_day: 0,
            window_days: None,
        });
        assert!(out.is_empty());
    }

    #[test]
    fn default_window_is_7_days() {
        assert_eq!(DEFAULT_RELINK_WINDOW_DAYS, 7);
        let runs = [run("d8", 8), run("d7", 7)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &[],
            current_run_id: None,
            scheduled_day: 0,
            window_days: None,
        });
        assert_eq!(ids(&out).as_slice(), &["d7"]);
    }

    #[test]
    fn exact_calendar_day_gap_excluded_at_7() {
        // The web twin carries a DST-straddling case here: a run 8 calendar days
        // before the workout is OUT of a ±7 window. Under the day-index collapse
        // the gap is simply an integer, so the DST subtlety cannot arise — the
        // 8-day run is excluded, the 6-day run kept.
        let runs = [run("dst-edge", -8), run("inside", -6)];
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &[],
            current_run_id: None,
            scheduled_day: 0,
            window_days: None,
        });
        assert_eq!(ids(&out).as_slice(), &["inside"]);
    }

    /// A double day, and enough rows that the answer is a real claim about the
    /// sort rather than about its small-slice path — `sort_unstable` is
    /// insertion sort under ~20 elements and is stable there by accident, so a
    /// four-run case pinned nothing. Web and Dart order a same-day pair by time
    /// of day; this rail is handed only a day index, so the most it can promise
    /// is that same-day runs come out in the order the phone sent them, which
    /// is the phone's own newest-first list.
    #[test]
    fn same_day_runs_keep_the_order_they_arrived_in() {
        const IDS: [&str; 40] = [
            "r00", "r01", "r02", "r03", "r04", "r05", "r06", "r07", "r08", "r09", "r10", "r11",
            "r12", "r13", "r14", "r15", "r16", "r17", "r18", "r19", "r20", "r21", "r22", "r23",
            "r24", "r25", "r26", "r27", "r28", "r29", "r30", "r31", "r32", "r33", "r34", "r35",
            "r36", "r37", "r38", "r39",
        ];
        let runs: heapless::Vec<RelinkCandidateRun, 40> = IDS
            .iter()
            .enumerate()
            .map(|(i, id)| run(id, -((i % 4) as i32)))
            .collect();
        let out = filter_relink_candidates(&RelinkFilterInput {
            runs: &runs,
            linked_run_ids: &[],
            current_run_id: None,
            scheduled_day: 0,
            window_days: None,
        });
        // Four day buckets, each holding every tenth id in arrival order.
        let mut want: heapless::Vec<&str, 40> = heapless::Vec::new();
        for bucket in 0..4 {
            for (i, id) in IDS.iter().enumerate() {
                if i % 4 == bucket {
                    let _ = want.push(id);
                }
            }
        }
        assert_eq!(ids(&out).as_slice(), want.as_slice());
    }
}
