//! Year / Month-in-Running recap — the pure aggregator behind the "Wrapped"
//! wrap-up card. Over a set of runs it emits the headline numbers a recap card
//! needs: total distance / time / elevation, run count, run-family longest +
//! fastest, top week, longest + current streak, a 12-month strip, unique routes,
//! most-used activity, and the earned trophy grid.
//!
//! Parity port of web `runs/recap.ts` (`buildYearInRunningRecap`,
//! `buildMonthInRunningRecap`, `computeRecapBadges`, `recapHeadline`) — keep the
//! aggregation rules, edge cases, badge tiers, and test count in lockstep. The
//! web-only share-image builders and the Dart-only `recapSnapshotJson` are NOT
//! part of this port.
//!
//! Two representational changes from the web copy, both following the
//! established `no_std` cores. First, ISO timestamps collapse to an integer
//! **day index** (calendar days since the Unix epoch, local tz) exactly as
//! [`training_load`](crate::training_load) / [`current_week`](crate::current_week)
//! do; pinning the epoch lets the module recover a run's calendar year + month
//! with [`civil_from_days`] and its day-of-week (for the week grouping) with the
//! reused [`current_week::dow_of`], so no timezone DB is needed. Second, the
//! per-run start clock and the week anchor are integers too: a start time is a
//! `start_minute` (minutes since local midnight) rather than an `hh:mm` string,
//! and [`RecapWeekTop::week_start`] is the Monday's day index rather than a
//! `YYYY-MM-DD` string.
//!
//! Badges carry only their stable id + Material Symbols icon ligature — both
//! identifiers, never the English label/detail prose (a display concern, like
//! [`badges`](crate::badges)); the dynamic counts a detail line would show all
//! live on the recap struct already.
//!
//! Pure logic, no peripherals, no allocator. `f64` distance / duration is kept
//! (web uses `number`) so the sums and pace match.

use core::fmt::Write;

use heapless::{String, Vec};

use crate::current_week::dow_of;
use crate::locale_defaults::DistanceUnit;

/// Distinct weeks a single year can touch. A year's runs span at most ~54
/// Mon-anchored weeks (the first can back-anchor into the prior December).
const MAX_WEEKS: usize = 56;
/// Distinct route ids counted per recap window. Runs beyond this are still
/// summed into the totals; only the unique-route tally saturates.
const MAX_ROUTES: usize = 256;
/// Distinct activity types tallied (`run` / `walk` / `hike` / `cycle` / …).
const MAX_ACTIVITIES: usize = 8;
/// Run days fed to the streak walk. The full run set is passed for streaks so a
/// December streak counts into the year; beyond this cap the extras are dropped.
const MAX_STREAK_DAYS: usize = 512;
/// One badge per catalogue category; the catalogue has 11 categories.
pub const MAX_RECAP_BADGES: usize = 11;

/// One month of the 12-month strip. `month` is 1-based (1 = Jan … 12 = Dec);
/// sparse months still appear with zeros.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RecapMonthBucket {
    pub month: u8,
    pub distance_m: f64,
    pub duration_s: f64,
    pub run_count: u32,
}

/// The busiest week. `week_start` is the Monday's day index (see the module
/// docs), the integer collapse of web's `YYYY-MM-DD` week-start string.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RecapWeekTop {
    pub week_start: i32,
    pub distance_m: f64,
    pub run_count: u32,
}

/// An earned trophy: its stable catalogue id and Material Symbols icon ligature,
/// both identifiers. The localized label/detail is resolved by a display layer
/// from the recap's own fields (streak days, counts, start time), never here.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RecapBadge {
    pub id: &'static str,
    pub icon: &'static str,
}

/// Counts the recap can't derive from runs alone — the caller supplies them.
/// Both default to 0 so the aggregate still works standalone. Web reads these as
/// `number`, so they stay `f64` and are clamped to a non-negative int on use.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct RecapExtras {
    pub photo_count: f64,
    pub personal_record_count: f64,
}

/// A run reduced to what the recap needs. `day` is a local-day index and
/// `start_minute` the minutes since local midnight (see the module docs); a
/// `None` activity is coalesced to `"run"`, matching web's `activity_type ?? 'run'`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RecapRun<'a> {
    pub day: i32,
    pub start_minute: u16,
    pub distance_m: f64,
    pub duration_s: f64,
    pub elevation_m: f64,
    pub route_id: Option<&'a str>,
    pub activity: Option<&'a str>,
}

/// The whole recap aggregate. `month` is present only on a monthly recap.
#[derive(Clone, Debug, PartialEq)]
pub struct YearInRunningRecap<'a> {
    pub year: i32,
    pub month: Option<u8>,
    pub run_count: u32,
    pub total_distance_m: f64,
    pub total_duration_s: f64,
    pub total_elevation_m: f64,
    pub longest_run_m: f64,
    pub fastest_pace_s_per_km: Option<f64>,
    pub best_streak_days: u32,
    pub current_streak_days: u32,
    /// Earliest / latest start as minutes since local midnight (web's `hh:mm`).
    pub earliest_start_min: Option<u16>,
    pub latest_start_min: Option<u16>,
    pub monthly: [RecapMonthBucket; 12],
    pub top_week: Option<RecapWeekTop>,
    pub unique_route_count: u32,
    pub most_used_activity: Option<&'a str>,
    pub photo_count: u32,
    pub personal_record_count: u32,
    pub badges: Vec<RecapBadge, MAX_RECAP_BADGES>,
}

/// Inputs the badge tiers read, gathered once during the build.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct RecapBadgeInput {
    pub total_distance_m: f64,
    pub run_count: u32,
    pub best_streak_days: u32,
    pub total_elevation_m: f64,
    pub longest_run_m: f64,
    pub active_months: u32,
    pub distinct_activities: u32,
    pub earliest_start_min: Option<u16>,
    pub latest_start_min: Option<u16>,
    pub photo_count: u32,
    pub personal_record_count: u32,
}

fn pick(out: &mut Vec<RecapBadge, MAX_RECAP_BADGES>, tiers: &[(bool, &'static str, &'static str)]) {
    if let Some(&(_, id, icon)) = tiers.iter().find(|t| t.0) {
        let _ = out.push(RecapBadge { id, icon });
    }
}

/// Earned-only trophy grid. Each category lists tiers high → low; the first
/// threshold met wins, so a 1,200 km year shows "1,000 km", not three distance
/// badges. Deterministic + side-effect-free.
pub fn compute_recap_badges(i: &RecapBadgeInput) -> Vec<RecapBadge, MAX_RECAP_BADGES> {
    let mut out: Vec<RecapBadge, MAX_RECAP_BADGES> = Vec::new();
    let km = i.total_distance_m / 1000.0;

    pick(
        &mut out,
        &[
            (km >= 2000.0, "dist-2000", "public"),
            (km >= 1000.0, "dist-1000", "public"),
            (km >= 500.0, "dist-500", "route"),
            (km >= 100.0, "dist-100", "route"),
        ],
    );
    pick(
        &mut out,
        &[
            (i.run_count >= 200, "runs-200", "sprint"),
            (i.run_count >= 100, "runs-100", "sprint"),
            (i.run_count >= 50, "runs-50", "sprint"),
        ],
    );
    pick(
        &mut out,
        &[
            (i.longest_run_m >= 50000.0, "long-ultra", "military_tech"),
            (i.longest_run_m >= 42195.0, "long-marathon", "military_tech"),
            (i.longest_run_m >= 21097.0, "long-half", "military_tech"),
        ],
    );
    pick(
        &mut out,
        &[
            (
                i.best_streak_days >= 30,
                "streak-30",
                "local_fire_department",
            ),
            (
                i.best_streak_days >= 14,
                "streak-14",
                "local_fire_department",
            ),
            (i.best_streak_days >= 7, "streak-7", "local_fire_department"),
        ],
    );
    pick(
        &mut out,
        &[
            (i.total_elevation_m >= 8849.0, "elev-everest", "terrain"),
            (i.total_elevation_m >= 5000.0, "elev-5000", "terrain"),
        ],
    );
    pick(
        &mut out,
        &[
            (i.active_months >= 12, "months-12", "calendar_month"),
            (i.active_months >= 6, "months-6", "calendar_month"),
        ],
    );
    pick(
        &mut out,
        &[
            (i.personal_record_count >= 5, "pr-5", "trophy"),
            (i.personal_record_count >= 1, "pr-1", "trophy"),
        ],
    );
    pick(
        &mut out,
        &[
            (i.photo_count >= 25, "photo-25", "photo_camera"),
            (i.photo_count >= 1, "photo-1", "photo_camera"),
        ],
    );
    pick(
        &mut out,
        &[(i.distinct_activities >= 3, "variety", "category")],
    );
    pick(
        &mut out,
        &[(
            i.earliest_start_min.is_some_and(|m| m < 6 * 60),
            "early",
            "wb_twilight",
        )],
    );
    pick(
        &mut out,
        &[(
            i.latest_start_min.is_some_and(|m| m >= 21 * 60),
            "night",
            "bedtime",
        )],
    );

    out
}

/// Civil date → day index (days since 1970-01-01), Howard Hinnant's algorithm.
fn days_from_civil(y: i32, m: u32, d: u32) -> i32 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = (if y >= 0 { y } else { y - 399 }) / 400;
    let yoe = (y - era * 400) as i64;
    let mp: i64 = if m > 2 {
        (m - 3) as i64
    } else {
        (m + 9) as i64
    };
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    (era as i64 * 146097 + doe - 719468) as i32
}

/// Day index → civil `(year, month 1-12, day)`, the inverse of [`days_from_civil`].
fn civil_from_days(z: i32) -> (i32, u8, u8) {
    let z = z as i64 + 719468;
    let era = (if z >= 0 { z } else { z - 146096 }) / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    ((y + i64::from(m <= 2)) as i32, m as u8, d as u8)
}

/// Day index of the first of a month, `new Date(year, month_index0, 1)` — a 0-based
/// month arg that may over/underflow into an adjacent year, exactly like JS.
fn first_of_month(year: i32, month_index0: i32) -> i32 {
    let y = year + month_index0.div_euclid(12);
    let m0 = month_index0.rem_euclid(12);
    days_from_civil(y, (m0 + 1) as u32, 1)
}

/// Day index of the last day of a 1-based month, matching web's
/// `new Date(year, month, 0)`.
fn end_of_month(year: i32, month: u8) -> i32 {
    first_of_month(year, month as i32) - 1
}

/// The Monday of the local week containing `day`, as a day index. Mirrors web's
/// `mondayOf`: JS day-of-week rotated so Monday is 0, then stepped back.
fn monday_of(day: i32) -> i32 {
    day - ((dow_of(day) as i32 + 6) % 7)
}

/// `Math.max(0, Math.trunc(x))` — NaN and negatives collapse to 0.
fn clamp_count(x: f64) -> u32 {
    let t = libm::trunc(x);
    if t.is_finite() && t > 0.0 {
        t as u32
    } else {
        0
    }
}

/// `{ current, best }` run streaks from a set of day indices, anchored on
/// `today`. A streak is consecutive local days with a run; a missing today does
/// not break it (Strava grace: count from yesterday). Port of web
/// `runs/streaks.ts` `computeRunStreaks`, day keys already being day indices.
fn compute_run_streaks(run_days: &[i32], today: i32) -> (u32, u32) {
    if run_days.is_empty() {
        return (0, 0);
    }
    let mut days: Vec<i32, MAX_STREAK_DAYS> = Vec::new();
    for &d in run_days {
        if d <= today && !days.contains(&d) {
            let _ = days.push(d);
        }
    }
    if days.is_empty() {
        return (0, 0);
    }
    days.sort_unstable();

    let mut best = 1u32;
    let mut run = 1u32;
    for w in days.windows(2) {
        if w[1] == w[0] + 1 {
            run += 1;
            if run > best {
                best = run;
            }
        } else {
            run = 1;
        }
    }

    let has = |d: i32| days.binary_search(&d).is_ok();
    let mut anchor = today;
    if !has(anchor) {
        anchor -= 1;
        if !has(anchor) {
            return (0, best);
        }
    }
    let mut current = 0u32;
    while has(anchor) {
        current += 1;
        anchor -= 1;
    }
    (current, best)
}

fn top_week_of(weekly: &[(i32, f64, u32)]) -> Option<RecapWeekTop> {
    let mut top: Option<RecapWeekTop> = None;
    for &(wk, dist, count) in weekly {
        let replace = match &top {
            None => true,
            Some(t) => dist > t.distance_m,
        };
        if replace {
            top = Some(RecapWeekTop {
                week_start: wk,
                distance_m: dist,
                run_count: count,
            });
        }
    }
    top
}

fn most_used_of<'a>(counts: &[(&'a str, u32)]) -> Option<&'a str> {
    let mut best: Option<&'a str> = None;
    let mut best_count = 0u32;
    for &(name, count) in counts {
        if best.is_none() || count > best_count {
            best = Some(name);
            best_count = count;
        }
    }
    best
}

/// Build the year-in-running aggregate. Pass *all* of the user's runs, not just
/// the target year's; streaks read the full set so a streak crossing the year
/// boundary still counts, and the helper filters the rest internally.
pub fn build_year_in_running_recap<'a>(
    runs: &[RecapRun<'a>],
    year: i32,
    extras: &RecapExtras,
) -> YearInRunningRecap<'a> {
    let mut total_distance = 0.0;
    let mut total_duration = 0.0;
    let mut total_elevation = 0.0;
    let mut longest = 0.0;
    let mut fastest: Option<f64> = None;
    let mut earliest_min: Option<u16> = None;
    let mut latest_min: Option<u16> = None;
    let mut in_year_count = 0u32;

    let mut monthly: [RecapMonthBucket; 12] = core::array::from_fn(|i| RecapMonthBucket {
        month: (i + 1) as u8,
        distance_m: 0.0,
        duration_s: 0.0,
        run_count: 0,
    });
    let mut weekly: Vec<(i32, f64, u32), MAX_WEEKS> = Vec::new();
    let mut routes: Vec<&'a str, MAX_ROUTES> = Vec::new();
    let mut activity_counts: Vec<(&'a str, u32), MAX_ACTIVITIES> = Vec::new();

    for r in runs {
        let (ry, rm, _rd) = civil_from_days(r.day);
        if ry != year {
            continue;
        }
        in_year_count += 1;
        total_distance += r.distance_m;
        total_duration += r.duration_s;
        total_elevation += r.elevation_m;

        let is_run_family = r.activity.unwrap_or("run") != "cycle";
        if is_run_family && r.distance_m > longest {
            longest = r.distance_m;
        }
        if is_run_family && r.distance_m > 500.0 && r.duration_s > 0.0 {
            let pace = r.duration_s / (r.distance_m / 1000.0);
            fastest = Some(fastest.map_or(pace, |f| f.min(pace)));
        }

        earliest_min = Some(earliest_min.map_or(r.start_minute, |m| m.min(r.start_minute)));
        latest_min = Some(latest_min.map_or(r.start_minute, |m| m.max(r.start_minute)));

        let md = &mut monthly[(rm - 1) as usize];
        md.distance_m += r.distance_m;
        md.duration_s += r.duration_s;
        md.run_count += 1;

        let wk = monday_of(r.day);
        if let Some(e) = weekly.iter_mut().find(|e| e.0 == wk) {
            e.1 += r.distance_m;
            e.2 += 1;
        } else {
            let _ = weekly.push((wk, r.distance_m, 1));
        }

        if let Some(rid) = r.route_id {
            if !routes.contains(&rid) {
                let _ = routes.push(rid);
            }
        }

        let activity = r.activity.unwrap_or("run");
        if let Some(e) = activity_counts.iter_mut().find(|e| e.0 == activity) {
            e.1 += 1;
        } else {
            let _ = activity_counts.push((activity, 1));
        }
    }

    let mut all_days: Vec<i32, MAX_STREAK_DAYS> = Vec::new();
    for r in runs {
        let _ = all_days.push(r.day);
    }
    let (current, best) = compute_run_streaks(&all_days, days_from_civil(year, 12, 31));

    let photo_count = clamp_count(extras.photo_count);
    let personal_record_count = clamp_count(extras.personal_record_count);
    let active_months = monthly.iter().filter(|m| m.run_count > 0).count() as u32;

    let badges = compute_recap_badges(&RecapBadgeInput {
        total_distance_m: total_distance,
        run_count: in_year_count,
        best_streak_days: best,
        total_elevation_m: total_elevation,
        longest_run_m: longest,
        active_months,
        distinct_activities: activity_counts.len() as u32,
        earliest_start_min: earliest_min,
        latest_start_min: latest_min,
        photo_count,
        personal_record_count,
    });

    YearInRunningRecap {
        year,
        month: None,
        run_count: in_year_count,
        total_distance_m: total_distance,
        total_duration_s: total_duration,
        total_elevation_m: total_elevation,
        longest_run_m: longest,
        fastest_pace_s_per_km: fastest,
        best_streak_days: best,
        current_streak_days: current,
        earliest_start_min: earliest_min,
        latest_start_min: latest_min,
        monthly,
        top_week: top_week_of(&weekly),
        unique_route_count: routes.len() as u32,
        most_used_activity: most_used_of(&activity_counts),
        photo_count,
        personal_record_count,
        badges,
    }
}

/// Monthly recap — same engine over one calendar month. Reuses
/// [`build_year_in_running_recap`] for the 12-month strip + the target bucket,
/// then re-derives the headline numbers from the month's runs so every per-run
/// rule stays identical by construction. `month` is 1-based.
pub fn build_month_in_running_recap<'a>(
    runs: &[RecapRun<'a>],
    year: i32,
    month: u8,
    extras: &RecapExtras,
) -> YearInRunningRecap<'a> {
    let year_recap = build_year_in_running_recap(runs, year, extras);
    let bucket = year_recap
        .monthly
        .get((month as usize).wrapping_sub(1))
        .copied()
        .unwrap_or(RecapMonthBucket {
            month,
            distance_m: 0.0,
            duration_s: 0.0,
            run_count: 0,
        });

    let mut total_elevation = 0.0;
    let mut longest = 0.0;
    let mut fastest: Option<f64> = None;
    let mut earliest_min: Option<u16> = None;
    let mut latest_min: Option<u16> = None;
    let mut weekly: Vec<(i32, f64, u32), MAX_WEEKS> = Vec::new();
    let mut routes: Vec<&'a str, MAX_ROUTES> = Vec::new();
    let mut activity_counts: Vec<(&'a str, u32), MAX_ACTIVITIES> = Vec::new();

    for r in runs {
        let (ry, rm, _rd) = civil_from_days(r.day);
        if ry != year || rm != month {
            continue;
        }
        total_elevation += r.elevation_m;

        let is_run_family = r.activity.unwrap_or("run") != "cycle";
        if is_run_family && r.distance_m > longest {
            longest = r.distance_m;
        }
        if is_run_family && r.distance_m > 500.0 && r.duration_s > 0.0 {
            let pace = r.duration_s / (r.distance_m / 1000.0);
            fastest = Some(fastest.map_or(pace, |f| f.min(pace)));
        }

        earliest_min = Some(earliest_min.map_or(r.start_minute, |m| m.min(r.start_minute)));
        latest_min = Some(latest_min.map_or(r.start_minute, |m| m.max(r.start_minute)));

        let wk = monday_of(r.day);
        if let Some(e) = weekly.iter_mut().find(|e| e.0 == wk) {
            e.1 += r.distance_m;
            e.2 += 1;
        } else {
            let _ = weekly.push((wk, r.distance_m, 1));
        }

        if let Some(rid) = r.route_id {
            if !routes.contains(&rid) {
                let _ = routes.push(rid);
            }
        }

        let activity = r.activity.unwrap_or("run");
        if let Some(e) = activity_counts.iter_mut().find(|e| e.0 == activity) {
            e.1 += 1;
        } else {
            let _ = activity_counts.push((activity, 1));
        }
    }

    let mut all_days: Vec<i32, MAX_STREAK_DAYS> = Vec::new();
    for r in runs {
        let _ = all_days.push(r.day);
    }
    let (current, best) = compute_run_streaks(&all_days, end_of_month(year, month));

    let photo_count = clamp_count(extras.photo_count);
    let personal_record_count = clamp_count(extras.personal_record_count);

    let badges = compute_recap_badges(&RecapBadgeInput {
        total_distance_m: bucket.distance_m,
        run_count: bucket.run_count,
        best_streak_days: best,
        total_elevation_m: total_elevation,
        longest_run_m: longest,
        active_months: if bucket.run_count > 0 { 1 } else { 0 },
        distinct_activities: activity_counts.len() as u32,
        earliest_start_min: earliest_min,
        latest_start_min: latest_min,
        photo_count,
        personal_record_count,
    });

    YearInRunningRecap {
        year,
        month: Some(month),
        run_count: bucket.run_count,
        total_distance_m: bucket.distance_m,
        total_duration_s: bucket.duration_s,
        total_elevation_m: total_elevation,
        longest_run_m: longest,
        fastest_pace_s_per_km: fastest,
        best_streak_days: best,
        current_streak_days: current,
        earliest_start_min: earliest_min,
        latest_start_min: latest_min,
        monthly: year_recap.monthly,
        top_week: top_week_of(&weekly),
        unique_route_count: routes.len() as u32,
        most_used_activity: most_used_of(&activity_counts),
        photo_count,
        personal_record_count,
        badges,
    }
}

/// Share-card headline copy, e.g. `2026: 1609 km across 12 runs.` — the distance
/// rounded to whole km/mi. An empty recap shows the "no runs" line.
pub fn recap_headline(recap: &YearInRunningRecap<'_>, unit: DistanceUnit) -> String<64> {
    let mut s: String<64> = String::new();
    if recap.run_count == 0 {
        let _ = write!(s, "No runs in {} yet.", recap.year);
        return s;
    }
    let (value, unit_str) = match unit {
        DistanceUnit::Mi => (libm::round(recap.total_distance_m / 1609.344), "mi"),
        DistanceUnit::Km => (libm::round(recap.total_distance_m / 1000.0), "km"),
    };
    let _ = write!(
        s,
        "{}: {} {} across {} runs.",
        recap.year, value as i64, unit_str, recap.run_count
    );
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/runs/recap.test.ts` — same scenarios, same
    /// expected values, with each web `Date` mapped to its local day index +
    /// start minute so the ports can't drift.
    fn run(
        y: i32,
        mo: u32,
        dd: u32,
        hh: u16,
        mm: u16,
        distance_m: f64,
        duration_s: f64,
    ) -> RecapRun<'static> {
        RecapRun {
            day: days_from_civil(y, mo, dd),
            start_minute: hh * 60 + mm,
            distance_m,
            duration_s,
            elevation_m: 0.0,
            route_id: None,
            activity: None,
        }
    }

    #[test]
    fn empty_input_zeros() {
        let r = build_year_in_running_recap(&[], 2026, &RecapExtras::default());
        assert_eq!(r.year, 2026);
        assert_eq!(r.run_count, 0);
        assert_eq!(r.total_distance_m, 0.0);
        assert_eq!(r.longest_run_m, 0.0);
        assert_eq!(r.fastest_pace_s_per_km, None);
        assert_eq!(r.top_week, None);
        assert_eq!(r.unique_route_count, 0);
        assert_eq!(r.most_used_activity, None);
        assert_eq!(r.monthly.len(), 12);
        assert!(r.monthly.iter().all(|m| m.run_count == 0));
    }

    #[test]
    fn filters_runs_by_year() {
        let runs = [
            run(2025, 12, 31, 10, 0, 5000.0, 1500.0),
            run(2026, 1, 15, 10, 0, 10000.0, 2700.0),
            run(2027, 1, 1, 10, 0, 5000.0, 1500.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.run_count, 1);
        assert_eq!(r.total_distance_m, 10000.0);
    }

    #[test]
    fn monthly_buckets_line_up_with_the_calendar() {
        let runs = [
            run(2026, 1, 15, 10, 0, 5000.0, 1500.0),
            run(2026, 1, 22, 10, 0, 5000.0, 1500.0),
            run(2026, 6, 1, 10, 0, 10000.0, 2700.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.monthly[0].run_count, 2);
        assert_eq!(r.monthly[0].distance_m, 10000.0);
        assert_eq!(r.monthly[5].run_count, 1);
        assert_eq!(r.monthly[5].distance_m, 10000.0);
        assert_eq!(r.monthly[3].run_count, 0);
    }

    #[test]
    fn longest_run_is_the_max() {
        let runs = [
            run(2026, 2, 1, 10, 0, 5000.0, 1500.0),
            run(2026, 3, 1, 10, 0, 21097.0, 7200.0),
            run(2026, 4, 1, 10, 0, 10000.0, 2700.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.longest_run_m, 21097.0);
    }

    #[test]
    fn fastest_pace_ignores_sub_500m_efforts() {
        let runs = [
            run(2026, 1, 1, 10, 0, 200.0, 60.0),
            run(2026, 2, 1, 10, 0, 10000.0, 2700.0),
            run(2026, 3, 1, 10, 0, 5000.0, 1200.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.fastest_pace_s_per_km, Some(240.0));
    }

    #[test]
    fn a_cycle_ride_is_not_the_fastest_pace_or_longest_run() {
        let runs = [
            run(2026, 3, 1, 10, 0, 5000.0, 1500.0),
            RecapRun {
                activity: Some("cycle"),
                ..run(2026, 4, 1, 10, 0, 40000.0, 4800.0)
            },
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.fastest_pace_s_per_km, Some(300.0));
        assert_eq!(r.longest_run_m, 5000.0);
        assert_eq!(r.total_distance_m, 45000.0);
    }

    #[test]
    fn top_week_sums_distance_in_a_mon_sun_window() {
        let runs = [
            run(2026, 2, 2, 10, 0, 5000.0, 1500.0),
            run(2026, 2, 4, 10, 0, 8000.0, 2400.0),
            run(2026, 2, 6, 10, 0, 6000.0, 1800.0),
            run(2026, 2, 10, 10, 0, 10000.0, 2700.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        let top = r.top_week.unwrap();
        assert_eq!(top.week_start, days_from_civil(2026, 2, 2));
        assert_eq!(top.distance_m, 19000.0);
        assert_eq!(top.run_count, 3);
    }

    #[test]
    fn unique_route_count_counts_distinct_route_ids() {
        let runs = [
            RecapRun {
                route_id: Some("r1"),
                ..run(2026, 2, 1, 10, 0, 5000.0, 1500.0)
            },
            RecapRun {
                route_id: Some("r1"),
                ..run(2026, 2, 2, 10, 0, 5000.0, 1500.0)
            },
            RecapRun {
                route_id: Some("r2"),
                ..run(2026, 2, 3, 10, 0, 5000.0, 1500.0)
            },
            run(2026, 2, 4, 10, 0, 5000.0, 1500.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.unique_route_count, 2);
    }

    #[test]
    fn most_used_activity_is_the_max_count_bucket() {
        let runs = [
            run(2026, 2, 1, 10, 0, 5000.0, 1500.0),
            run(2026, 2, 2, 10, 0, 5000.0, 1500.0),
            RecapRun {
                activity: Some("walk"),
                ..run(2026, 2, 3, 10, 0, 5000.0, 1500.0)
            },
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.most_used_activity, Some("run"));
    }

    #[test]
    fn streaks_read_the_full_set_not_just_the_year() {
        let runs = [
            run(2025, 12, 28, 12, 0, 5000.0, 1500.0),
            run(2025, 12, 29, 12, 0, 5000.0, 1500.0),
            run(2025, 12, 30, 12, 0, 5000.0, 1500.0),
            run(2025, 12, 31, 12, 0, 5000.0, 1500.0),
            run(2026, 1, 1, 12, 0, 5000.0, 1500.0),
            run(2026, 1, 2, 12, 0, 5000.0, 1500.0),
            run(2026, 1, 3, 12, 0, 5000.0, 1500.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert!(
            r.best_streak_days >= 3,
            "expected >=3, got {}",
            r.best_streak_days
        );
    }

    #[test]
    fn recap_headline_km_vs_mi() {
        let runs = [run(2026, 1, 1, 10, 0, 1_609_344.0, 540_000.0)];
        let recap = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(
            recap_headline(&recap, DistanceUnit::Km).as_str(),
            "2026: 1609 km across 1 runs."
        );
        assert_eq!(
            recap_headline(&recap, DistanceUnit::Mi).as_str(),
            "2026: 1000 mi across 1 runs."
        );
    }

    #[test]
    fn recap_headline_empty_shows_no_runs() {
        let recap = build_year_in_running_recap(&[], 2026, &RecapExtras::default());
        assert_eq!(
            recap_headline(&recap, DistanceUnit::Km).as_str(),
            "No runs in 2026 yet."
        );
    }

    #[test]
    fn earliest_and_latest_start_times() {
        let runs = [
            run(2026, 2, 1, 5, 30, 5000.0, 1500.0),
            run(2026, 2, 2, 12, 15, 5000.0, 1500.0),
            run(2026, 2, 3, 20, 45, 5000.0, 1500.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.earliest_start_min, Some(5 * 60 + 30));
        assert_eq!(r.latest_start_min, Some(20 * 60 + 45));
    }

    #[test]
    fn activity_type_missing_defaults_to_run() {
        let runs = [
            run(2026, 2, 1, 10, 0, 5000.0, 1500.0),
            run(2026, 2, 2, 10, 0, 5000.0, 1500.0),
            RecapRun {
                activity: Some("walk"),
                ..run(2026, 2, 3, 10, 0, 5000.0, 1500.0)
            },
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.most_used_activity, Some("run"));
    }

    #[test]
    fn top_week_anchor_is_a_monday() {
        let runs = [run(2026, 2, 1, 10, 0, 5000.0, 1500.0)];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        let top = r.top_week.unwrap();
        assert_eq!(top.week_start, days_from_civil(2026, 1, 26));
    }

    #[test]
    fn fastest_pace_is_seconds_per_km() {
        let runs = [run(2026, 2, 1, 10, 0, 10000.0, 3000.0)];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.fastest_pace_s_per_km, Some(300.0));
    }

    #[test]
    fn zero_duration_runs_do_not_produce_infinity_pace() {
        let runs = [
            run(2026, 2, 1, 10, 0, 5000.0, 0.0),
            run(2026, 2, 2, 10, 0, 5000.0, 1500.0),
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.fastest_pace_s_per_km, Some(300.0));
        assert!(r.fastest_pace_s_per_km.unwrap().is_finite());
    }

    #[test]
    fn zero_runs_null_earliest_latest_start() {
        let r = build_year_in_running_recap(&[], 2026, &RecapExtras::default());
        assert_eq!(r.earliest_start_min, None);
        assert_eq!(r.latest_start_min, None);
    }

    #[test]
    fn elevation_falls_back_to_zero_when_absent() {
        let runs = [
            run(2026, 2, 1, 10, 0, 5000.0, 1500.0),
            RecapRun {
                elevation_m: 50.0,
                ..run(2026, 2, 2, 10, 0, 5000.0, 1500.0)
            },
        ];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.total_elevation_m, 50.0);
    }

    #[test]
    fn extras_default_to_zero_and_emit_no_photo_or_pr_badge() {
        let runs = [run(2026, 3, 1, 10, 0, 5000.0, 1500.0)];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert_eq!(r.photo_count, 0);
        assert_eq!(r.personal_record_count, 0);
        assert!(!r.badges.iter().any(|b| b.id.starts_with("photo")));
        assert!(!r.badges.iter().any(|b| b.id.starts_with("pr")));
    }

    #[test]
    fn extras_surface_photo_and_pr_counts_and_badges() {
        let runs = [run(2026, 3, 1, 10, 0, 5000.0, 1500.0)];
        let r = build_year_in_running_recap(
            &runs,
            2026,
            &RecapExtras {
                photo_count: 30.0,
                personal_record_count: 6.0,
            },
        );
        assert_eq!(r.photo_count, 30);
        assert_eq!(r.personal_record_count, 6);
        assert_eq!(
            r.badges
                .iter()
                .find(|b| b.id.starts_with("photo"))
                .map(|b| b.id),
            Some("photo-25")
        );
        assert_eq!(
            r.badges
                .iter()
                .find(|b| b.id.starts_with("pr"))
                .map(|b| b.id),
            Some("pr-5")
        );
    }

    #[test]
    fn negative_or_fractional_extras_are_clamped() {
        let r = build_year_in_running_recap(
            &[],
            2026,
            &RecapExtras {
                photo_count: -3.0,
                personal_record_count: 2.9,
            },
        );
        assert_eq!(r.photo_count, 0);
        assert_eq!(r.personal_record_count, 2);
    }

    #[test]
    fn one_badge_per_category_highest_tier_wins() {
        let runs: [RecapRun; 12] = core::array::from_fn(|i| {
            let n = (i % 9 + 1) as u32;
            run(2026, n, n, 10, 0, 100_000.0, 30_000.0)
        });
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        let dist: std::vec::Vec<_> = r
            .badges
            .iter()
            .filter(|b| b.id.starts_with("dist-"))
            .collect();
        assert_eq!(dist.len(), 1);
        assert_eq!(dist[0].id, "dist-1000");
    }

    #[test]
    fn a_marathon_length_longest_run_earns_the_marathon_trophy() {
        let runs = [run(2026, 4, 1, 8, 0, 42_300.0, 14_400.0)];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert!(r.badges.iter().any(|b| b.id == "long-marathon"));
        assert!(!r.badges.iter().any(|b| b.id == "long-ultra"));
    }

    #[test]
    fn an_early_start_earns_the_early_bird_trophy() {
        let runs = [run(2026, 5, 1, 5, 15, 5000.0, 1500.0)];
        let r = build_year_in_running_recap(&runs, 2026, &RecapExtras::default());
        assert!(r.badges.iter().any(|b| b.id == "early"));
        assert!(!r.badges.iter().any(|b| b.id == "night"));
    }

    #[test]
    fn an_empty_year_earns_no_trophies() {
        let r = build_year_in_running_recap(&[], 2026, &RecapExtras::default());
        assert_eq!(r.badges.len(), 0);
    }

    #[test]
    fn month_recap_projects_out_a_single_month() {
        let runs = [
            run(2026, 3, 5, 10, 0, 5000.0, 1500.0),
            run(2026, 3, 20, 10, 0, 7000.0, 2100.0),
            run(2026, 6, 1, 10, 0, 10000.0, 2700.0),
        ];
        let r = build_month_in_running_recap(&runs, 2026, 3, &RecapExtras::default());
        assert_eq!(r.month, Some(3));
        assert_eq!(r.run_count, 2);
        assert_eq!(r.total_distance_m, 12000.0);
        assert_eq!(r.total_duration_s, 3600.0);
        assert_eq!(r.longest_run_m, 7000.0);
    }

    #[test]
    fn month_recap_empty_month_zeros_but_keeps_the_strip() {
        let runs = [run(2026, 6, 1, 10, 0, 10000.0, 2700.0)];
        let r = build_month_in_running_recap(&runs, 2026, 3, &RecapExtras::default());
        assert_eq!(r.month, Some(3));
        assert_eq!(r.run_count, 0);
        assert_eq!(r.total_distance_m, 0.0);
        assert_eq!(r.longest_run_m, 0.0);
        assert_eq!(r.monthly.len(), 12);
        assert_eq!(r.monthly[5].distance_m, 10000.0);
    }

    #[test]
    fn month_recap_cycle_is_not_the_month_longest_or_fastest() {
        let runs = [
            run(2026, 4, 1, 10, 0, 5000.0, 1500.0),
            RecapRun {
                activity: Some("cycle"),
                ..run(2026, 4, 2, 10, 0, 40000.0, 4800.0)
            },
        ];
        let r = build_month_in_running_recap(&runs, 2026, 4, &RecapExtras::default());
        assert_eq!(r.longest_run_m, 5000.0);
        assert_eq!(r.fastest_pace_s_per_km, Some(300.0));
        assert_eq!(r.total_distance_m, 45000.0);
    }

    #[test]
    fn month_recap_extras_flow_through_to_month_badges() {
        let runs = [run(2026, 5, 1, 10, 0, 5000.0, 1500.0)];
        let r = build_month_in_running_recap(
            &runs,
            2026,
            5,
            &RecapExtras {
                photo_count: 30.0,
                personal_record_count: 6.0,
            },
        );
        assert_eq!(r.photo_count, 30);
        assert_eq!(r.personal_record_count, 6);
        assert_eq!(
            r.badges
                .iter()
                .find(|b| b.id.starts_with("photo"))
                .map(|b| b.id),
            Some("photo-25")
        );
        assert_eq!(
            r.badges
                .iter()
                .find(|b| b.id.starts_with("pr"))
                .map(|b| b.id),
            Some("pr-5")
        );
    }

    #[test]
    fn month_recap_out_of_range_month_is_zero_never_panics() {
        let runs = [run(2026, 5, 1, 10, 0, 5000.0, 1500.0)];
        let r = build_month_in_running_recap(&runs, 2026, 13, &RecapExtras::default());
        assert_eq!(r.run_count, 0);
        assert_eq!(r.total_distance_m, 0.0);
    }
}
