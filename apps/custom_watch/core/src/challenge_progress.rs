//! Challenge progress + ranking + on-pace projection — the watch's view of a
//! joined club challenge (progress bar, leaderboard rank, "am I on pace" hint).
//!
//! A parity port of web `social/challenge_progress.ts` (twin of
//! `challenge_progress.dart`). Keep the three in lockstep: algorithm, edge
//! cases, outputs, and test counts must match.
//!
//! [`metric_from_activity`] is the SAME metric-extraction the SQL aggregate
//! (`challenge_leaderboard` / `recompute_challenge_completion`) performs, so an
//! offline-optimistic on-device estimate can't drift from the server board.
//!
//! The ±5 % on-pace dead-band is NOT redefined here: the watch already carries
//! it as [`crate::pacer::ON_PACE_BAND`] (documented there as the
//! `challenge_progress` twin), so this module reuses that constant to keep the
//! challenge hint and the pacer verdict from grading "on pace" differently.
//! Web's canonical home for the band is `challenge_progress.ts`; the watch
//! placed it in `pacer` first, so `pacer` owns it on-device.
//!
//! Pure logic, no peripherals, no allocator.

use crate::pacer::ON_PACE_BAND;
use heapless::Vec;

/// Whole-milliseconds in a day — the challenge-window unit web computes in.
const DAY_MS: f64 = 86_400_000.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ChallengeMetric {
    Distance,
    Duration,
    Vert,
    ActivityCount,
    StreakDays,
}

/// Narrow activity-type union mirroring web `ActivityType`. An absent type on a
/// summary is treated as [`Run`](ActivityType::Run) (web's `?? 'run'`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ActivityType {
    Run,
    Walk,
    Hike,
    Cycle,
    Stroller,
}

/// One numeric summary field. Mirrors web's `number | string | null`: the
/// activities view stores `distance_m` / `duration_s` as either a number or a
/// numeric string, and a missing field reads 0.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum SummaryValue<'a> {
    Num(f64),
    Text(&'a str),
    #[default]
    Absent,
}

/// One activity's summary — the fields [`metric_from_activity`] reads. Mirrors
/// the `summary` jsonb shape the SQL leaderboard aggregate consumes.
#[derive(Clone, Copy, Debug, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ActivitySummary<'a> {
    pub distance_m: SummaryValue<'a>,
    pub duration_s: SummaryValue<'a>,
    pub elevation_gain_m: SummaryValue<'a>,
    pub activity_type: Option<ActivityType>,
}

/// Fraction of the goal reached, clamped to 0..1. `None` goal (pure-ranking
/// board) or non-positive goal → `None`: there is no bar to fill.
pub fn progress_fraction(value: f64, goal: Option<f64>) -> Option<f64> {
    let g = match goal {
        Some(g) if g > 0.0 => g,
        _ => return None,
    };
    let frac = value / g;
    if frac < 0.0 {
        Some(0.0)
    } else if frac > 1.0 {
        Some(1.0)
    } else {
        Some(frac)
    }
}

/// True once the goal is met (>=). `None` / non-positive goal → false.
pub fn is_complete(value: f64, goal: Option<f64>) -> bool {
    matches!(goal, Some(g) if g > 0.0 && value >= g)
}

/// Locale/unit-agnostic structured parts for a progress label. The caller
/// localises + unit-formats — this layer carries the raw numbers + the metric.
/// `fraction` is `None` for a goal-less board.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ProgressParts {
    pub metric: ChallengeMetric,
    pub value: f64,
    pub goal: Option<f64>,
    pub fraction: Option<f64>,
    pub complete: bool,
}

pub fn progress_parts(metric: ChallengeMetric, value: f64, goal: Option<f64>) -> ProgressParts {
    ProgressParts {
        metric,
        value,
        goal,
        fraction: progress_fraction(value, goal),
        complete: is_complete(value, goal),
    }
}

/// One activity's contribution to a metric, mirroring the SQL aggregate. For
/// `ActivityCount` / `StreakDays` a single activity contributes 1 (day
/// distinctness of a streak is resolved by the caller over a day-set, not per
/// activity). Returns 0 when the activity type doesn't match the filter.
pub fn metric_from_activity(
    summary: &ActivitySummary,
    metric: ChallengeMetric,
    activity_type_filter: Option<ActivityType>,
) -> f64 {
    if let Some(filter) = activity_type_filter {
        if summary.activity_type.unwrap_or(ActivityType::Run) != filter {
            return 0.0;
        }
    }
    match metric {
        ChallengeMetric::Distance => number_of(&summary.distance_m),
        ChallengeMetric::Duration => number_of(&summary.duration_s),
        ChallengeMetric::Vert => number_of(&summary.elevation_gain_m),
        ChallengeMetric::ActivityCount => 1.0,
        ChallengeMetric::StreakDays => 1.0,
    }
}

fn number_of(v: &SummaryValue) -> f64 {
    match v {
        SummaryValue::Num(n) if n.is_finite() => *n,
        SummaryValue::Text(s) => match s.parse::<f64>() {
            Ok(n) if n.is_finite() => n,
            _ => 0.0,
        },
        _ => 0.0,
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RankableEntry<'a> {
    pub user_id: Option<&'a str>,
    pub team_club_id: Option<&'a str>,
    pub value: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RankedEntry<'a> {
    pub entry: RankableEntry<'a>,
    pub rank: u32,
}

/// Deterministic leaderboard ordering + dense rank assignment, mirroring the
/// SQL `rank() over (order by value desc)` plus a stable tie-break: value
/// descending, then user_id (else team_club_id) ascending, so two refreshes
/// never swap equal rows. Equal values share a rank (1,1,3 — competition
/// ranking, matching SQL `rank()`). Output beyond `N` is dropped.
pub fn rank_participants<'a, const N: usize>(
    entries: &[RankableEntry<'a>],
) -> Vec<RankedEntry<'a>, N> {
    let mut sorted: Vec<RankableEntry<'a>, N> = Vec::new();
    for e in entries {
        let _ = sorted.push(*e);
    }
    sorted.sort_unstable_by(compare_entries);

    let mut out: Vec<RankedEntry<'a>, N> = Vec::new();
    let mut rank: u32 = 0;
    let mut seen: u32 = 0;
    let mut prev_value: Option<f64> = None;
    for entry in sorted.iter() {
        seen += 1;
        if !matches!(prev_value, Some(p) if p == entry.value) {
            rank = seen;
            prev_value = Some(entry.value);
        }
        let _ = out.push(RankedEntry {
            entry: *entry,
            rank,
        });
    }
    out
}

fn compare_entries(a: &RankableEntry, b: &RankableEntry) -> core::cmp::Ordering {
    match b.value.partial_cmp(&a.value) {
        Some(core::cmp::Ordering::Equal) | None => {
            let ak = a.user_id.or(a.team_club_id).unwrap_or("");
            let bk = b.user_id.or(b.team_club_id).unwrap_or("");
            ak.cmp(bk)
        }
        Some(other) => other,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ChallengePaceStatus {
    Upcoming,
    Active,
    Ended,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PaceVerdict {
    Ahead,
    OnTrack,
    Behind,
}

/// Locale/unit-agnostic on-pace projection for a time-boxed goal challenge. The
/// caller localises + unit-formats. Every goal-derived field is `None` on a
/// goal-less (pure-ranking) board.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ChallengePace {
    pub status: ChallengePaceStatus,
    /// Fraction of the challenge window elapsed at `now_ms`, clamped 0..1.
    pub elapsed_fraction: f64,
    /// Whole days until the window closes (ceil), floored at 0.
    pub days_remaining: f64,
    /// Where an even-paced runner would be at `now_ms` (goal × elapsed).
    pub expected_value: Option<f64>,
    /// Linear projection of the final value from the current rate
    /// (value / elapsed). `None` before the window opens; the frozen `value`
    /// once it has closed.
    pub projected_value: Option<f64>,
    /// Metric units still needed to reach the goal (goal − value), floored at 0.
    pub remaining_value: Option<f64>,
    /// Metric units per day needed over the remaining window to still finish.
    /// `None` once complete, with no days left, or the window has closed.
    pub required_per_day: Option<f64>,
    /// ahead / on_track / behind vs the even-pace line, within [`ON_PACE_BAND`].
    /// `None` outside the active window or once the goal is already met.
    pub verdict: Option<PaceVerdict>,
}

/// Project a joined runner's standing in a time-boxed goal challenge. All times
/// are epoch ms so the helper stays pure and timezone-free (the caller parses
/// the ISO window). Only re-shapes the numbers the leaderboard already computed.
pub fn challenge_pace(
    value: f64,
    goal: Option<f64>,
    start_ms: f64,
    end_ms: f64,
    now_ms: f64,
) -> ChallengePace {
    let goal_value = match goal {
        Some(g) if g > 0.0 => Some(g),
        _ => None,
    };

    let (status, elapsed_fraction) = if now_ms < start_ms {
        (ChallengePaceStatus::Upcoming, 0.0)
    } else if now_ms >= end_ms || end_ms <= start_ms {
        (ChallengePaceStatus::Ended, 1.0)
    } else {
        (
            ChallengePaceStatus::Active,
            (now_ms - start_ms) / (end_ms - start_ms),
        )
    };

    let days_remaining = libm::ceil((end_ms - now_ms) / DAY_MS).max(0.0);
    let expected_value = goal_value.map(|g| g * elapsed_fraction);
    let remaining_value = goal_value.map(|g| (g - value).max(0.0));

    let projected_value = match goal_value {
        Some(_) if status == ChallengePaceStatus::Active && elapsed_fraction > 0.0 => {
            Some(value / elapsed_fraction)
        }
        Some(_) if status == ChallengePaceStatus::Ended => Some(value),
        _ => None,
    };

    let required_per_day = match (goal_value, remaining_value) {
        (Some(_), Some(rem))
            if status != ChallengePaceStatus::Ended && days_remaining > 0.0 && rem > 0.0 =>
        {
            Some(rem / days_remaining)
        }
        _ => None,
    };

    let verdict = match (goal_value, expected_value) {
        (Some(g), Some(exp)) if status == ChallengePaceStatus::Active && value < g && exp > 0.0 => {
            let ratio = value / exp;
            Some(if ratio >= 1.0 + ON_PACE_BAND {
                PaceVerdict::Ahead
            } else if ratio < 1.0 - ON_PACE_BAND {
                PaceVerdict::Behind
            } else {
                PaceVerdict::OnTrack
            })
        }
        _ => None,
    };

    ChallengePace {
        status,
        elapsed_fraction,
        days_remaining,
        expected_value,
        projected_value,
        remaining_value,
        required_per_day,
        verdict,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DAY: f64 = 86_400_000.0;

    #[test]
    fn progress_fraction_clamps_to_0_1() {
        assert_eq!(progress_fraction(50.0, Some(100.0)), Some(0.5));
        assert_eq!(progress_fraction(150.0, Some(100.0)), Some(1.0));
        assert_eq!(progress_fraction(-10.0, Some(100.0)), Some(0.0));
    }

    #[test]
    fn progress_fraction_null_goal_is_none() {
        assert_eq!(progress_fraction(50.0, None), None);
        assert_eq!(progress_fraction(50.0, Some(0.0)), None);
    }

    #[test]
    fn is_complete_respects_ge_goal() {
        assert!(!is_complete(99.0, Some(100.0)));
        assert!(is_complete(100.0, Some(100.0)));
        assert!(is_complete(101.0, Some(100.0)));
        assert!(!is_complete(100.0, None));
    }

    #[test]
    fn progress_parts_bundles_fraction_and_complete() {
        let p = progress_parts(ChallengeMetric::Distance, 60000.0, Some(100000.0));
        assert_eq!(p.metric, ChallengeMetric::Distance);
        assert_eq!(p.value, 60000.0);
        assert_eq!(p.goal, Some(100000.0));
        assert_eq!(p.fraction, Some(0.6));
        assert!(!p.complete);
    }

    #[test]
    fn progress_parts_goal_less_board_has_none_fraction() {
        let p = progress_parts(ChallengeMetric::Distance, 60000.0, None);
        assert_eq!(p.fraction, None);
        assert!(!p.complete);
    }

    #[test]
    fn metric_from_activity_distance_reads_distance_m() {
        let num = ActivitySummary {
            distance_m: SummaryValue::Num(5000.0),
            ..Default::default()
        };
        let text = ActivitySummary {
            distance_m: SummaryValue::Text("5000"),
            ..Default::default()
        };
        assert_eq!(
            metric_from_activity(&num, ChallengeMetric::Distance, None),
            5000.0
        );
        assert_eq!(
            metric_from_activity(&text, ChallengeMetric::Distance, None),
            5000.0
        );
    }

    #[test]
    fn metric_from_activity_duration_reads_duration_s() {
        let s = ActivitySummary {
            duration_s: SummaryValue::Num(1800.0),
            ..Default::default()
        };
        assert_eq!(
            metric_from_activity(&s, ChallengeMetric::Duration, None),
            1800.0
        );
    }

    #[test]
    fn metric_from_activity_vert_reads_elevation_gain_m() {
        let num = ActivitySummary {
            elevation_gain_m: SummaryValue::Num(640.0),
            ..Default::default()
        };
        let text = ActivitySummary {
            elevation_gain_m: SummaryValue::Text("640"),
            ..Default::default()
        };
        let missing = ActivitySummary::default();
        assert_eq!(
            metric_from_activity(&num, ChallengeMetric::Vert, None),
            640.0
        );
        assert_eq!(
            metric_from_activity(&text, ChallengeMetric::Vert, None),
            640.0
        );
        assert_eq!(
            metric_from_activity(&missing, ChallengeMetric::Vert, None),
            0.0
        );
    }

    #[test]
    fn metric_from_activity_count_and_streak_each_contribute_1() {
        let s = ActivitySummary::default();
        assert_eq!(
            metric_from_activity(&s, ChallengeMetric::ActivityCount, None),
            1.0
        );
        assert_eq!(
            metric_from_activity(&s, ChallengeMetric::StreakDays, None),
            1.0
        );
    }

    #[test]
    fn metric_from_activity_type_filter_excludes_non_matching() {
        let walk = ActivitySummary {
            distance_m: SummaryValue::Num(5000.0),
            activity_type: Some(ActivityType::Walk),
            ..Default::default()
        };
        let run = ActivitySummary {
            distance_m: SummaryValue::Num(5000.0),
            activity_type: Some(ActivityType::Run),
            ..Default::default()
        };
        assert_eq!(
            metric_from_activity(&walk, ChallengeMetric::Distance, Some(ActivityType::Run)),
            0.0
        );
        assert_eq!(
            metric_from_activity(&run, ChallengeMetric::Distance, Some(ActivityType::Run)),
            5000.0
        );
    }

    #[test]
    fn metric_from_activity_defaults_missing_type_to_run() {
        let s = ActivitySummary {
            distance_m: SummaryValue::Num(5000.0),
            ..Default::default()
        };
        assert_eq!(
            metric_from_activity(&s, ChallengeMetric::Distance, Some(ActivityType::Run)),
            5000.0
        );
    }

    #[test]
    fn metric_from_activity_coerces_null_garbage_to_0() {
        let absent = ActivitySummary {
            distance_m: SummaryValue::Absent,
            ..Default::default()
        };
        let garbage = ActivitySummary {
            distance_m: SummaryValue::Text("abc"),
            ..Default::default()
        };
        assert_eq!(
            metric_from_activity(&absent, ChallengeMetric::Distance, None),
            0.0
        );
        assert_eq!(
            metric_from_activity(&garbage, ChallengeMetric::Distance, None),
            0.0
        );
    }

    #[test]
    fn rank_participants_orders_by_value_desc_with_stable_tie_break() {
        let ranked = rank_participants::<8>(&[
            RankableEntry {
                user_id: Some("b"),
                team_club_id: None,
                value: 30.0,
            },
            RankableEntry {
                user_id: Some("a"),
                team_club_id: None,
                value: 50.0,
            },
            RankableEntry {
                user_id: Some("c"),
                team_club_id: None,
                value: 50.0,
            },
        ]);
        let got: Vec<(Option<&str>, u32), 8> =
            ranked.iter().map(|r| (r.entry.user_id, r.rank)).collect();
        assert_eq!(
            got.as_slice(),
            &[(Some("a"), 1), (Some("c"), 1), (Some("b"), 3)]
        );
    }

    #[test]
    fn rank_participants_falls_back_to_team_club_id() {
        let ranked = rank_participants::<8>(&[
            RankableEntry {
                user_id: None,
                team_club_id: Some("blue"),
                value: 50.0,
            },
            RankableEntry {
                user_id: None,
                team_club_id: Some("red"),
                value: 50.0,
            },
        ]);
        let got: Vec<(Option<&str>, u32), 8> = ranked
            .iter()
            .map(|r| (r.entry.team_club_id, r.rank))
            .collect();
        assert_eq!(got.as_slice(), &[(Some("blue"), 1), (Some("red"), 1)]);
    }

    #[test]
    fn challenge_pace_on_track_at_the_even_pace_line_mid_window() {
        let p = challenge_pace(50.0, Some(100.0), 0.0, 10.0 * DAY, 5.0 * DAY);
        assert_eq!(p.status, ChallengePaceStatus::Active);
        assert_eq!(p.elapsed_fraction, 0.5);
        assert_eq!(p.expected_value, Some(50.0));
        assert_eq!(p.projected_value, Some(100.0));
        assert_eq!(p.remaining_value, Some(50.0));
        assert_eq!(p.days_remaining, 5.0);
        assert_eq!(p.required_per_day, Some(10.0));
        assert_eq!(p.verdict, Some(PaceVerdict::OnTrack));
    }

    #[test]
    fn challenge_pace_behind_flags_the_daily_rate_needed() {
        let p = challenge_pace(30.0, Some(100.0), 0.0, 10.0 * DAY, 5.0 * DAY);
        assert_eq!(p.verdict, Some(PaceVerdict::Behind));
        assert_eq!(p.projected_value, Some(60.0));
        assert_eq!(p.remaining_value, Some(70.0));
        assert_eq!(p.required_per_day, Some(14.0));
    }

    #[test]
    fn challenge_pace_ahead_when_past_the_even_pace_line() {
        let p = challenge_pace(70.0, Some(100.0), 0.0, 10.0 * DAY, 5.0 * DAY);
        assert_eq!(p.verdict, Some(PaceVerdict::Ahead));
        assert_eq!(p.projected_value, Some(140.0));
        assert_eq!(p.required_per_day, Some(6.0));
    }

    #[test]
    fn challenge_pace_goal_less_board_nulls_every_goal_derived_field() {
        let p = challenge_pace(50.0, None, 0.0, 10.0 * DAY, 5.0 * DAY);
        assert_eq!(p.status, ChallengePaceStatus::Active);
        assert_eq!(p.elapsed_fraction, 0.5);
        assert_eq!(p.days_remaining, 5.0);
        assert_eq!(p.expected_value, None);
        assert_eq!(p.projected_value, None);
        assert_eq!(p.remaining_value, None);
        assert_eq!(p.required_per_day, None);
        assert_eq!(p.verdict, None);
    }

    #[test]
    fn challenge_pace_upcoming_has_no_projection_or_verdict_yet() {
        let p = challenge_pace(0.0, Some(100.0), 2.0 * DAY, 12.0 * DAY, 0.0);
        assert_eq!(p.status, ChallengePaceStatus::Upcoming);
        assert_eq!(p.elapsed_fraction, 0.0);
        assert_eq!(p.projected_value, None);
        assert_eq!(p.verdict, None);
        assert_eq!(p.days_remaining, 12.0);
    }

    #[test]
    fn challenge_pace_ended_freezes_projection_to_the_final_value() {
        let p = challenge_pace(80.0, Some(100.0), 0.0, 10.0 * DAY, 11.0 * DAY);
        assert_eq!(p.status, ChallengePaceStatus::Ended);
        assert_eq!(p.elapsed_fraction, 1.0);
        assert_eq!(p.projected_value, Some(80.0));
        assert_eq!(p.remaining_value, Some(20.0));
        assert_eq!(p.required_per_day, None);
        assert_eq!(p.verdict, None);
        assert_eq!(p.days_remaining, 0.0);
    }

    #[test]
    fn challenge_pace_complete_drops_verdict_and_required_rate() {
        let p = challenge_pace(120.0, Some(100.0), 0.0, 10.0 * DAY, 5.0 * DAY);
        assert_eq!(p.verdict, None);
        assert_eq!(p.remaining_value, Some(0.0));
        assert_eq!(p.required_per_day, None);
    }

    #[test]
    fn challenge_pace_days_remaining_ceils_a_partial_day() {
        let p = challenge_pace(40.0, Some(100.0), 0.0, 10.0 * DAY, 5.5 * DAY);
        assert_eq!(p.days_remaining, 5.0);
        assert_eq!(p.required_per_day, Some(12.0));
    }
}
