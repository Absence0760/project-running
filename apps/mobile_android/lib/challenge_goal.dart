import 'preferences.dart';

/// Pure challenge-goal entry helpers, shared with the web twin
/// (apps/web/src/lib/social/challenge_goal.ts). Keep the two in lockstep:
/// algorithm, edge cases, outputs, and test counts must match.
///
/// `challenges.goal_value` is stored in the unit the SQL aggregate sums in —
/// metres for `distance` and `vert`, seconds for `duration`, a bare count for
/// `activity_count` and `streak_days`. That is not what a person types: nobody
/// enters a 100 km challenge as `100000`. [challengeGoalUnit] names the unit
/// the field asks for and [challengeGoalToStored] is the conversion into the
/// column, the same entry/exit split `UnitFormat.paceSecPerUnit` /
/// `paceSecPerKm` keeps for a typed pace.
///
/// [checkChallengeGoal] is the client half of `challenges_goal_ck` (migration
/// `20270615_001`): both halves must agree, or a refusal the constraint makes
/// reaches the author as a raw postgres 23514 naming neither bound.

const int _secondsPerHour = 3600;
const int _dayMs = 86400000;

/// The kind of unit a goal for a metric is typed in. `distance` and
/// `elevation` resolve further against the reader's own km/mi preference;
/// the other three are preference-free.
enum ChallengeGoalUnit { distance, elevation, hours, activities, days }

ChallengeGoalUnit challengeGoalUnit(String metric) {
  switch (metric) {
    case 'duration':
      return ChallengeGoalUnit.hours;
    case 'vert':
      return ChallengeGoalUnit.elevation;
    case 'activity_count':
      return ChallengeGoalUnit.activities;
    case 'streak_days':
      return ChallengeGoalUnit.days;
    case 'distance':
    default:
      return ChallengeGoalUnit.distance;
  }
}

/// A goal typed in the unit [challengeGoalUnit] names, converted into the unit
/// `challenges.goal_value` and the leaderboard aggregate both use.
num challengeGoalToStored(num typed, String metric, DistanceUnit unit) {
  switch (challengeGoalUnit(metric)) {
    case ChallengeGoalUnit.hours:
      return typed * _secondsPerHour;
    case ChallengeGoalUnit.elevation:
      return UnitFormat.elevationToMetres(typed.toDouble(), unit);
    case ChallengeGoalUnit.distance:
      return unit == DistanceUnit.mi ? typed * kMetresPerMile : typed * 1000;
    case ChallengeGoalUnit.activities:
    case ChallengeGoalUnit.days:
      return typed;
  }
}

/// The most distinct active days a `streak_days` board can ever count inside
/// `[startMs, endMs)`.
///
/// The aggregate counts `count(distinct (started_at at time zone 'UTC')::date)`
/// over the half-open window, so the ceiling is the number of calendar dates a
/// window of that length can touch — maximised when it opens just after
/// midnight, which is `floor(length / one day) + 1`. Deliberately the LOOSE
/// bound: a window ending exactly at midnight UTC touches one date fewer, and
/// refusing a goal the aggregate could in principle award is worse than
/// admitting one it cannot. `challenges_goal_ck` computes the same expression
/// in SQL, so the two never disagree on a row that can exist.
///
/// 0 for a window that is empty or inverted — `challenges_window_ck` refuses
/// those outright and the caller flags the window before the goal.
int maxStreakDaysInWindow(int startMs, int endMs) {
  if (endMs <= startMs) return 0;
  return (endMs - startMs) ~/ _dayMs + 1;
}

/// Why a stored goal cannot be saved. [notPositive] covers the whole
/// non-positive range including 0: the completion RPC compares `value >= goal`
/// with no floor, so a stored 0 awards the badge to every participant on the
/// nightly sweep while both clients render the challenge as goal-less.
enum ChallengeGoalRefusal { notPositive, exceedsWindow }

/// Grade a STORED goal against the row it would be written to. A null goal —
/// a pure-ranking board — is always fine. Null when the goal is acceptable.
ChallengeGoalRefusal? checkChallengeGoal(
  num? stored,
  String metric,
  int startMs,
  int endMs,
) {
  if (stored == null) return null;
  if (!stored.isFinite || stored <= 0) return ChallengeGoalRefusal.notPositive;
  // Only streak_days is bounded by the window. A `duration` goal is NOT:
  // the aggregate sums `duration_s` over runs whose START falls inside the
  // window, and a run started a minute before it closes carries its whole
  // duration — a 112-hour Moab finish included. The other three metrics are
  // unbounded outright.
  if (metric == 'streak_days' &&
      stored > maxStreakDaysInWindow(startMs, endMs)) {
    return ChallengeGoalRefusal.exceedsWindow;
  }
  return null;
}
