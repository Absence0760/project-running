//! Multi-metric run goals — evaluate a goal's distance / time / average-pace /
//! run-count targets over a week or month window and roll them into an overall
//! progress fraction + completion flag.
//!
//! Parity port of web `apps/web/src/lib/training/goals.ts` (twin of
//! `apps/mobile_android/lib/goals.dart`) — keep the target math, the
//! cycling-excluded distance-weighted pace, the pending-target rule (an
//! unmeasurable pace target must not drag the overall ring), and the
//! period-window arithmetic in lockstep.
//!
//! Three web concerns are deliberately NOT ported, because they are platform
//! I/O or display text with no place in a `no_std` core:
//!   - `loadGoals` / `saveGoals` / the JSON wire shape — `localStorage`
//!     persistence. The watch's goals arrive over the phone link, not a browser
//!     store.
//!   - `newGoalId` — a UUID/clock/RNG id generator. The core has no clock or
//!     entropy source; ids are assigned upstream.
//!   - `periodLabel` — the English "This week" / "This month" display strings.
//!     The [`GoalPeriod`] enum IS that identifier; the watch localises the label
//!     itself, so the core never carries the English text. Likewise the per-row
//!     `label` field ("Distance" / "Avg pace" / …) is dropped: [`TargetKind`]
//!     encodes it.
//!
//! Like [`current_week`](crate::current_week), the web copies parse each run's
//! `started_at` ISO timestamp with `Date` arithmetic; that has no place in
//! firmware. Here a run carries a plain **day index** ([`GoalRun::day`]) —
//! calendar days since the Unix epoch (1970-01-01, a Thursday) in the runner's
//! local zone — and "now" is an integer `now_day`. The period bounds are day
//! indices too, so filtering a run into the window is a `day >= start &&
//! day < end` comparison exactly matching the web's midnight-to-midnight
//! timestamp span. Pinning the epoch lets [`period_start`] recover the calendar
//! (day-of-week for the week anchor, first-of-month for the month anchor) with
//! [`days_from_civil`] / [`civil_from_days`] instead of a timezone database.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use core::fmt::Write;

use heapless::Vec;

/// Upper bound for every formatted label this module returns. A "10000.0 km"
/// distance, a "999h 59m" time, and a "199:59/km" pace all fit inside 16 bytes
/// (the em-dash sentinel is 3); 24 leaves headroom without reaching for a heap.
pub const GOAL_FMT_CAP: usize = 24;

pub type GoalString = heapless::String<GOAL_FMT_CAP>;

/// A goal's evaluation window. Mirrors the web `'week' | 'month'` union; the
/// call sites default to `Week`, as on web.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GoalPeriod {
    #[default]
    Week,
    Month,
}

/// Which weekday the calendar week starts on. Mirrors the web
/// `'monday' | 'sunday'` union; Monday is the default, as on web.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum WeekStart {
    Sunday,
    #[default]
    Monday,
}

/// The minimum a run exposes to the evaluator: which local day it happened on
/// (a day index; see the module docs), its distance + duration, and whether it
/// was a cycle ride. Pace targets exclude cycling — a single long bike ride
/// would otherwise dominate the distance-weighted average.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct GoalRun {
    pub day: i32,
    pub distance_m: f64,
    pub duration_s: f64,
    pub is_cycle: bool,
}

/// A goal's four optional targets over a period. A target is active only when
/// its field is `Some` AND strictly positive, matching the web `!= null && > 0`
/// gate. `pace_sec_per_km` is canonical seconds per kilometre, lower-is-better.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RunGoal {
    pub period: GoalPeriod,
    pub distance_metres: Option<f64>,
    pub time_seconds: Option<f64>,
    pub pace_sec_per_km: Option<f64>,
    pub run_count: Option<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum TargetKind {
    Distance,
    Time,
    Pace,
    RunCount,
}

/// One active target's progress. `current_label` / `target_label` are the
/// formatted display values (km / h+m / m:ss/km / count); `percent` is clamped
/// 0..1; `pending` marks a target that can't be evaluated yet (a pace target
/// with no pace-eligible runs) — excluded from the overall average so it
/// doesn't drag the ring to a fake 0%.
#[derive(Clone, Debug, PartialEq)]
pub struct TargetProgress {
    pub kind: TargetKind,
    pub current_label: GoalString,
    pub target_label: GoalString,
    pub percent: f64,
    pub complete: bool,
    pub pending: bool,
}

/// A goal has at most four targets (distance / time / pace / run-count).
pub const MAX_GOAL_TARGETS: usize = 4;

#[derive(Clone, Debug, PartialEq)]
pub struct GoalProgress {
    pub targets: Vec<TargetProgress, MAX_GOAL_TARGETS>,
    pub overall_percent: f64,
    pub complete: bool,
    pub run_count: u32,
}

/// JS day-of-week (0 = Sunday .. 6 = Saturday) for a day index. 1970-01-01 is
/// day 0 and a Thursday (`getDay` 4), so `(day + 4) mod 7`; `rem_euclid` keeps
/// it non-negative for pre-epoch indices.
pub fn dow_of(day: i32) -> u8 {
    (day + 4).rem_euclid(7) as u8
}

/// Days since the Unix epoch for a proleptic-Gregorian civil date (Hinnant's
/// `days_from_civil`). `month` is 1..=12, `day` 1..=31. Lets the caller map a
/// local calendar date to the day index [`evaluate_goal`] windows on.
pub fn days_from_civil(year: i32, month: u32, day: u32) -> i32 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = (if y >= 0 { y } else { y - 399 }) / 400;
    let yoe = (y - era * 400) as i64;
    let m = month as i64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + day as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    (era as i64 * 146097 + doe - 719468) as i32
}

/// Inverse of [`days_from_civil`] (Hinnant's `civil_from_days`): a day index →
/// `(year, month 1..=12, day 1..=31)`.
pub fn civil_from_days(day_index: i32) -> (i32, u32, u32) {
    let z = day_index as i64 + 719468;
    let era = (if z >= 0 { z } else { z - 146096 }) / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { y + 1 } else { y };
    (year as i32, month as u32, day as u32)
}

/// First day index of the period containing `now_day`. For a week, the Monday
/// (or Sunday) on/before `now_day`; for a month, the first of that calendar
/// month. Mirrors web `periodStart` with the time-of-day dropped (a day index
/// has no sub-day component — the web value is always midnight).
pub fn period_start(period: GoalPeriod, now_day: i32, week_start: WeekStart) -> i32 {
    match period {
        GoalPeriod::Week => {
            let offset = match week_start {
                WeekStart::Sunday => dow_of(now_day) as i32,
                WeekStart::Monday => (dow_of(now_day) as i32 + 6) % 7,
            };
            now_day - offset
        }
        GoalPeriod::Month => {
            let (y, m, _) = civil_from_days(now_day);
            days_from_civil(y, m, 1)
        }
    }
}

/// One past the last day index of the period (exclusive upper bound). A week is
/// `period_start + 7`; a month is the first of the following month, wrapping the
/// year. Mirrors web `periodEnd`.
pub fn period_end(period: GoalPeriod, now_day: i32, week_start: WeekStart) -> i32 {
    let start = period_start(period, now_day, week_start);
    match period {
        GoalPeriod::Week => start + 7,
        GoalPeriod::Month => {
            let (y, m, _) = civil_from_days(start);
            let (ny, nm) = if m == 12 { (y + 1, 1) } else { (y, m + 1) };
            days_from_civil(ny, nm, 1)
        }
    }
}

fn format_km(metres: f64) -> GoalString {
    let mut out = GoalString::new();
    let _ = write!(out, "{:.1} km", metres / 1000.0);
    out
}

fn format_minutes(seconds: f64) -> GoalString {
    let h = libm::floor(seconds / 3600.0) as i64;
    let m = libm::floor((seconds % 3600.0) / 60.0) as i64;
    let mut out = GoalString::new();
    if h > 0 {
        let _ = write!(out, "{h}h {m}m");
    } else {
        let _ = write!(out, "{m}m");
    }
    out
}

/// `secondsPerKm` -> `m:ss/km`, or the em-dash "—" if zero / negative /
/// non-finite. Mirrors web `formatPaceSecPerKm` (which delegates to
/// `paceMinutesSeconds`): round to the nearest second FIRST so the seconds
/// field is always 0..59 and never renders a malformed ":60".
pub fn format_pace_sec_per_km(sec_per_km: f64) -> GoalString {
    let mut out = GoalString::new();
    if !sec_per_km.is_finite() || sec_per_km <= 0.0 {
        let _ = out.push_str("—");
        return out;
    }
    let total = libm::round(sec_per_km) as i64;
    let minutes = total / 60;
    let seconds = total % 60;
    let _ = write!(out, "{minutes}:{seconds:02}/km");
    out
}

/// Pure evaluator: given a goal and the full run list, compute progress per
/// active target, the overall percent (mean of measurable targets), and the
/// completion flag. Mirrors web `evaluateGoal`.
pub fn evaluate_goal(
    goal: &RunGoal,
    runs: &[GoalRun],
    now_day: i32,
    week_start: WeekStart,
) -> GoalProgress {
    let start = period_start(goal.period, now_day, week_start);
    let end = period_end(goal.period, now_day, week_start);

    let mut in_count: u32 = 0;
    let mut total_metres = 0.0;
    let mut total_seconds = 0.0;
    let mut pace_metres = 0.0;
    let mut pace_seconds = 0.0;
    for r in runs {
        if r.day >= start && r.day < end {
            in_count += 1;
            total_metres += r.distance_m;
            total_seconds += r.duration_s;
            if !r.is_cycle {
                pace_metres += r.distance_m;
                pace_seconds += r.duration_s;
            }
        }
    }

    let mut targets: Vec<TargetProgress, MAX_GOAL_TARGETS> = Vec::new();

    if let Some(dm) = goal.distance_metres.filter(|&v| v > 0.0) {
        let _ = targets.push(TargetProgress {
            kind: TargetKind::Distance,
            current_label: format_km(total_metres),
            target_label: format_km(dm),
            percent: (total_metres / dm).min(1.0),
            complete: total_metres >= dm,
            pending: false,
        });
    }
    if let Some(ts) = goal.time_seconds.filter(|&v| v > 0.0) {
        let _ = targets.push(TargetProgress {
            kind: TargetKind::Time,
            current_label: format_minutes(total_seconds),
            target_label: format_minutes(ts),
            percent: (total_seconds / ts).min(1.0),
            complete: total_seconds >= ts,
            pending: false,
        });
    }
    if let Some(pk) = goal.pace_sec_per_km.filter(|&v| v > 0.0) {
        let current = if pace_metres > 10.0 {
            pace_seconds / (pace_metres / 1000.0)
        } else {
            0.0
        };
        let pending = current <= 0.0;
        let (percent, complete) = if pending {
            (0.0, false)
        } else if current <= pk {
            (1.0, true)
        } else {
            ((pk / current).clamp(0.0, 1.0), false)
        };
        let current_label = if pending {
            let mut o = GoalString::new();
            let _ = o.push_str("—");
            o
        } else {
            format_pace_sec_per_km(current)
        };
        let _ = targets.push(TargetProgress {
            kind: TargetKind::Pace,
            current_label,
            target_label: format_pace_sec_per_km(pk),
            percent,
            complete,
            pending,
        });
    }
    if let Some(rc) = goal.run_count.filter(|&v| v > 0) {
        let mut current_label = GoalString::new();
        let _ = write!(current_label, "{in_count}");
        let mut target_label = GoalString::new();
        let _ = write!(target_label, "{rc}");
        let _ = targets.push(TargetProgress {
            kind: TargetKind::RunCount,
            current_label,
            target_label,
            percent: (in_count as f64 / rc as f64).min(1.0),
            complete: in_count >= rc,
            pending: false,
        });
    }

    // Exclude pending targets from the overall average + completion so an
    // ineligible pace target doesn't drag the ring down with a fake 0%.
    let mut sum = 0.0;
    let mut measurable = 0u32;
    let mut all_complete = true;
    for t in &targets {
        if !t.pending {
            sum += t.percent;
            measurable += 1;
            if !t.complete {
                all_complete = false;
            }
        }
    }
    let overall_percent = if measurable == 0 {
        0.0
    } else {
        sum / measurable as f64
    };
    let complete = measurable > 0 && all_complete;

    GoalProgress {
        targets,
        overall_percent,
        complete,
        run_count: in_count,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/goals.test.ts` — same scenarios,
    /// same expected values, with each web `Date` mapped to its day index.
    /// The web fixtures live in April 2026; `NOW` is 2026-04-08, a Wednesday.
    fn idx(year: i32, month: u32, day: u32) -> i32 {
        days_from_civil(year, month, day)
    }

    fn now() -> i32 {
        idx(2026, 4, 8)
    }

    fn grun(day: i32, distance_m: f64, duration_s: f64) -> GoalRun {
        GoalRun {
            day,
            distance_m,
            duration_s,
            is_cycle: false,
        }
    }

    fn gcycle(day: i32, distance_m: f64, duration_s: f64) -> GoalRun {
        GoalRun {
            day,
            distance_m,
            duration_s,
            is_cycle: true,
        }
    }

    fn find(p: &GoalProgress, kind: TargetKind) -> &TargetProgress {
        p.targets.iter().find(|t| t.kind == kind).unwrap()
    }

    // ─────────────── period_start / period_end ───────────────

    #[test]
    fn period_start_week_starts_on_monday_by_default() {
        // 2026-04-08 is a Wednesday. Monday before is 2026-04-06. The web test
        // also asserts hours == 0 / minutes == 0; a day index has no sub-day
        // component, so "midnight" is implicit.
        let s = period_start(GoalPeriod::Week, idx(2026, 4, 8), WeekStart::Monday);
        let (_, month, day) = civil_from_days(s);
        assert_eq!(day, 6);
        assert_eq!(month, 4); // April (web getMonth() == 3, 0-based)
    }

    #[test]
    fn period_start_week_with_sunday_anchors_on_sunday() {
        let s = period_start(GoalPeriod::Week, idx(2026, 4, 8), WeekStart::Sunday);
        assert_eq!(dow_of(s), 0); // Sunday
        let (_, _, day) = civil_from_days(s);
        assert_eq!(day, 5);
    }

    #[test]
    fn period_start_month_starts_on_the_first() {
        let s = period_start(GoalPeriod::Month, idx(2026, 4, 15), WeekStart::Monday);
        let (_, month, day) = civil_from_days(s);
        assert_eq!(day, 1);
        assert_eq!(month, 4);
    }

    #[test]
    fn period_end_week_is_start_plus_7_days() {
        let e = period_end(GoalPeriod::Week, idx(2026, 4, 8), WeekStart::Monday);
        // Start was 2026-04-06; end is 2026-04-13.
        let (_, _, day) = civil_from_days(e);
        assert_eq!(day, 13);
    }

    #[test]
    fn period_end_month_wraps_at_year_boundary() {
        let e = period_end(GoalPeriod::Month, idx(2026, 12, 15), WeekStart::Monday);
        let (year, month, _) = civil_from_days(e);
        assert_eq!(month, 1); // January (web getMonth() == 0)
        assert_eq!(year, 2027);
    }

    // ─────────────── format_pace_sec_per_km ───────────────

    #[test]
    fn format_pace_em_dash_for_non_positive_or_non_finite() {
        assert_eq!(format_pace_sec_per_km(0.0).as_str(), "—");
        assert_eq!(format_pace_sec_per_km(-10.0).as_str(), "—");
        assert_eq!(format_pace_sec_per_km(f64::INFINITY).as_str(), "—");
        assert_eq!(format_pace_sec_per_km(f64::NAN).as_str(), "—");
    }

    #[test]
    fn format_pace_formats_m_ss_per_km() {
        assert_eq!(format_pace_sec_per_km(330.0).as_str(), "5:30/km");
        assert_eq!(format_pace_sec_per_km(60.0).as_str(), "1:00/km");
        assert_eq!(format_pace_sec_per_km(125.0).as_str(), "2:05/km"); // pads seconds
    }

    #[test]
    fn format_pace_rounds_seconds_half_up() {
        assert_eq!(format_pace_sec_per_km(330.4).as_str(), "5:30/km");
        assert_eq!(format_pace_sec_per_km(330.6).as_str(), "5:31/km");
    }

    #[test]
    fn format_pace_rolls_over_instead_of_a_malformed_60() {
        assert_eq!(format_pace_sec_per_km(299.6).as_str(), "5:00/km");
        assert_eq!(format_pace_sec_per_km(359.7).as_str(), "6:00/km");
    }

    // ─────────────── evaluate_goal ───────────────

    #[test]
    fn evaluate_empty_run_list_yields_0_percent_targets() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: Some(30_000.0),
            time_seconds: None,
            pace_sec_per_km: None,
            run_count: None,
        };
        let p = evaluate_goal(&goal, &[], now(), WeekStart::Monday);
        assert_eq!(p.targets.len(), 1);
        assert_eq!(p.targets[0].percent, 0.0);
        assert!(!p.complete);
        assert_eq!(p.run_count, 0);
        assert_eq!(p.overall_percent, 0.0);
    }

    #[test]
    fn evaluate_runs_outside_the_period_are_excluded() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: Some(30_000.0),
            time_seconds: None,
            pace_sec_per_km: None,
            run_count: None,
        };
        let last_week = grun(idx(2026, 3, 30), 30_000.0, 9000.0);
        let p = evaluate_goal(&goal, &[last_week], now(), WeekStart::Monday);
        assert_eq!(p.run_count, 0);
        assert_eq!(p.targets[0].percent, 0.0);
    }

    #[test]
    fn evaluate_distance_accumulates_and_reports_complete_on_hit() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: Some(30_000.0),
            time_seconds: None,
            pace_sec_per_km: None,
            run_count: None,
        };
        let monday = grun(idx(2026, 4, 6), 12_000.0, 3600.0);
        let wed = grun(idx(2026, 4, 8), 18_500.0, 5400.0);
        let p = evaluate_goal(&goal, &[monday, wed], now(), WeekStart::Monday);
        assert_eq!(p.run_count, 2);
        assert_eq!(p.targets.len(), 1);
        assert_eq!(p.targets[0].kind, TargetKind::Distance);
        assert_eq!(p.targets[0].percent, 1.0);
        assert!(p.targets[0].complete);
        assert!(p.complete);
    }

    #[test]
    fn evaluate_pace_excludes_cycling_from_the_average() {
        let running = grun(idx(2026, 4, 8), 10_000.0, 3000.0); // 5:00/km
        let cycling = gcycle(idx(2026, 4, 8), 30_000.0, 3600.0); // 2:00/km-equiv
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: None,
            time_seconds: None,
            pace_sec_per_km: Some(320.0), // 5:20/km target
            run_count: None,
        };
        let p = evaluate_goal(&goal, &[running, cycling], now(), WeekStart::Monday);
        let pace = find(&p, TargetKind::Pace);
        // Runner-only pace = 3000 s / 10 km = 300 s/km, which beats 320.
        assert!(pace.complete);
        assert_eq!(pace.percent, 1.0);
    }

    #[test]
    fn evaluate_pace_with_no_qualifying_runs_is_pending_not_complete() {
        let cycling_only = gcycle(idx(2026, 4, 8), 30_000.0, 3600.0);
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: None,
            time_seconds: None,
            pace_sec_per_km: Some(300.0),
            run_count: None,
        };
        let p = evaluate_goal(&goal, &[cycling_only], now(), WeekStart::Monday);
        let pace = find(&p, TargetKind::Pace);
        assert!(!pace.complete);
        assert_eq!(pace.percent, 0.0);
        assert_eq!(pace.current_label.as_str(), "—");
        assert!(pace.pending);
    }

    #[test]
    fn evaluate_pending_pace_target_does_not_drag_overall_percent() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: Some(30_000.0),
            time_seconds: None,
            pace_sec_per_km: Some(300.0),
            run_count: Some(3),
        };
        let acts = [
            gcycle(idx(2026, 4, 6), 10_000.0, 1500.0),
            gcycle(idx(2026, 4, 7), 10_000.0, 1500.0),
            gcycle(idx(2026, 4, 8), 10_000.0, 1500.0),
        ];
        let p = evaluate_goal(&goal, &acts, now(), WeekStart::Monday);
        let pace = find(&p, TargetKind::Pace);
        assert!(pace.pending);
        // Distance (30 km) + runCount (3) both met → overall ~1.0, not dragged
        // to ~0.66 by the pending pace target.
        assert!(p.overall_percent > 0.99);
        assert!(p.complete);
    }

    #[test]
    fn evaluate_pace_reports_lower_is_better_partial_progress() {
        // 10 km at 6:00/km (360 s/km), target 5:00 (300 s/km): 300/360 ≈ 0.833.
        let slow = grun(idx(2026, 4, 8), 10_000.0, 3600.0);
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: None,
            time_seconds: None,
            pace_sec_per_km: Some(300.0),
            run_count: None,
        };
        let p = evaluate_goal(&goal, &[slow], now(), WeekStart::Monday);
        let pace = find(&p, TargetKind::Pace);
        assert!(!pace.complete);
        assert!(pace.percent > 0.8 && pace.percent < 0.9);
    }

    #[test]
    fn evaluate_time_target_sums_duration_across_the_period() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: None,
            time_seconds: Some(7200.0),
            pace_sec_per_km: None,
            run_count: None,
        };
        let r1 = grun(idx(2026, 4, 6), 5000.0, 1800.0);
        let r2 = grun(idx(2026, 4, 8), 10_000.0, 3600.0);
        let p = evaluate_goal(&goal, &[r1, r2], now(), WeekStart::Monday);
        let time = find(&p, TargetKind::Time);
        assert_eq!(time.percent, 0.75); // 5400 / 7200
        assert!(!time.complete);
    }

    #[test]
    fn evaluate_run_count_target_counts_in_period_runs() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: None,
            time_seconds: None,
            pace_sec_per_km: None,
            run_count: Some(4),
        };
        let runs = [
            grun(idx(2026, 4, 6), 5000.0, 1800.0),
            grun(idx(2026, 4, 7), 5000.0, 1800.0),
            grun(idx(2026, 4, 8), 5000.0, 1800.0),
        ];
        let p = evaluate_goal(&goal, &runs, now(), WeekStart::Monday);
        let c = find(&p, TargetKind::RunCount);
        assert_eq!(c.percent, 0.75);
        assert!(!c.complete);
    }

    #[test]
    fn evaluate_multi_target_complete_only_when_every_target_hit() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: Some(20_000.0),
            time_seconds: None,
            pace_sec_per_km: None,
            run_count: Some(3),
        };
        let runs = [
            grun(idx(2026, 4, 6), 10_000.0, 3600.0),
            grun(idx(2026, 4, 8), 10_000.0, 3600.0),
        ];
        let p = evaluate_goal(&goal, &runs, now(), WeekStart::Monday);
        assert_eq!(p.targets.len(), 2);
        assert!(find(&p, TargetKind::Distance).complete);
        assert!(!find(&p, TargetKind::RunCount).complete);
        assert!(!p.complete);
    }

    #[test]
    fn evaluate_overall_percent_is_the_mean_of_target_percents() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: Some(20_000.0),
            time_seconds: None,
            pace_sec_per_km: None,
            run_count: Some(4),
        };
        let r = grun(idx(2026, 4, 8), 10_000.0, 3600.0);
        let p = evaluate_goal(&goal, &[r], now(), WeekStart::Monday);
        // distance: 0.5, runCount: 0.25 → mean 0.375.
        assert_eq!(p.overall_percent, 0.375);
    }

    #[test]
    fn evaluate_zero_or_negative_target_is_ignored() {
        let goal = RunGoal {
            period: GoalPeriod::Week,
            distance_metres: Some(0.0),
            time_seconds: None,
            pace_sec_per_km: None,
            run_count: Some(3),
        };
        let r = grun(idx(2026, 4, 8), 10_000.0, 3600.0);
        let p = evaluate_goal(&goal, &[r], now(), WeekStart::Monday);
        assert_eq!(p.targets.len(), 1);
        assert_eq!(p.targets[0].kind, TargetKind::RunCount);
    }
}
