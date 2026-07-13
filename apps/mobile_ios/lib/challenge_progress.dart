/// Pure challenge progress + ranking helpers, shared with the web twin
/// (apps/web/src/lib/social/challenge_progress.ts). Keep the two in lockstep:
/// algorithm, edge cases, outputs, and test counts must match.
///
/// `metricFromActivity` is the SAME metric-extraction the SQL aggregate
/// (challenge_leaderboard / recompute_challenge_completion) performs, so an
/// offline-optimistic client estimate computed from local stores can't drift
/// from the server board.
///
/// Pure functions, no Flutter / Supabase deps.
library;

enum ChallengeMetric { distance, duration, vert, activityCount, streakDays }

/// Fraction of the goal reached, clamped to 0..1. Null goal (pure-ranking
/// board) → null: there is no bar to fill.
double? progressFraction(num value, num? goal) {
  if (goal == null || goal <= 0) return null;
  final frac = value / goal;
  if (frac < 0) return 0;
  if (frac > 1) return 1;
  return frac.toDouble();
}

/// True once the goal is met (>=). Null goal → false (nothing to complete).
bool isComplete(num value, num? goal) {
  if (goal == null || goal <= 0) return false;
  return value >= goal;
}

/// Locale/unit-agnostic structured parts for a progress label. The CALLER
/// localises + unit-formats (km/mi, h/m, count, days) — this layer only carries
/// the raw numbers + the metric. `fraction` is null for a goal-less board.
class ProgressParts {
  final ChallengeMetric metric;
  final num value;
  final num? goal;
  final double? fraction;
  final bool complete;
  const ProgressParts({
    required this.metric,
    required this.value,
    required this.goal,
    required this.fraction,
    required this.complete,
  });
}

ProgressParts progressParts(ChallengeMetric metric, num value, num? goal) {
  return ProgressParts(
    metric: metric,
    value: value,
    goal: goal,
    fraction: progressFraction(value, goal),
    complete: isComplete(value, goal),
  );
}

/// One activity's contribution to a metric. `summary` mirrors the activities
/// view's summary jsonb (distance_m / duration_s, number or string). For
/// activity_count and streak_days a single activity always contributes 1 (the
/// day-distinctness of streak_days is resolved by the caller over a day-set,
/// not per activity). Returns 0 when the activity type doesn't match the
/// filter, or when the run is a DNF — mirroring the server aggregate
/// (`challenge_leaderboard` / `recompute_challenge_completion`, ADR 231), which
/// excludes DNF'd runs from every metric, so a client-side optimistic estimate
/// can't drift by counting a just-DNF'd run's distance. `is_dnf` rides the
/// activities-view runs summary (migration `20270408_001`); gym/meal
/// activities never carry it.
num metricFromActivity(
  Map<String, dynamic> summary,
  ChallengeMetric metric,
  String? activityTypeFilter,
) {
  if (activityTypeFilter != null &&
      (summary['activity_type'] as String? ?? 'run') != activityTypeFilter) {
    return 0;
  }
  if (summary['is_dnf'] == true) return 0;
  switch (metric) {
    case ChallengeMetric.distance:
      return _numberOf(summary['distance_m']);
    case ChallengeMetric.duration:
      return _numberOf(summary['duration_s']);
    case ChallengeMetric.vert:
      return _numberOf(summary['elevation_gain_m']);
    case ChallengeMetric.activityCount:
      return 1;
    case ChallengeMetric.streakDays:
      return 1;
  }
}

num _numberOf(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.isFinite ? v : 0;
  final n = num.tryParse(v.toString());
  return (n != null && n.isFinite) ? n : 0;
}

class RankableEntry {
  final String? userId;
  final String? teamClubId;
  final num value;
  const RankableEntry({this.userId, this.teamClubId, required this.value});
}

class RankedEntry {
  final RankableEntry entry;
  final int rank;
  const RankedEntry(this.entry, this.rank);
}

/// Deterministic leaderboard ordering + dense rank assignment, mirroring the
/// SQL `rank() over (order by value desc)` plus a stable tie-break: value
/// descending, then user_id ascending (team_club_id for a team board). Equal
/// values share a rank (1,1,3 — standard competition ranking).
List<RankedEntry> rankParticipants(List<RankableEntry> entries) {
  final sorted = [...entries]..sort(_compareEntries);
  final out = <RankedEntry>[];
  var rank = 0;
  var seen = 0;
  num? prevValue;
  for (final entry in sorted) {
    seen += 1;
    if (prevValue == null || entry.value != prevValue) {
      rank = seen;
      prevValue = entry.value;
    }
    out.add(RankedEntry(entry, rank));
  }
  return out;
}

int _compareEntries(RankableEntry a, RankableEntry b) {
  final byValue = (b.value - a.value);
  if (byValue != 0) return byValue > 0 ? 1 : -1;
  final ak = a.userId ?? a.teamClubId ?? '';
  final bk = b.userId ?? b.teamClubId ?? '';
  return ak.compareTo(bk);
}

const int _dayMs = 86400000;

/// Tolerance band around the even-pace line inside which a runner counts as
/// "on track" rather than ahead/behind — ±5 %. Shared with the web twin so the
/// verdict is identical on both platforms.
const double kOnPaceBand = 0.05;

enum ChallengePaceStatus { upcoming, active, ended }

enum PaceVerdict { ahead, onTrack, behind }

/// Locale/unit-agnostic on-pace projection for a time-boxed goal challenge. The
/// CALLER localises + unit-formats the numbers — this layer carries raw metric
/// units + the verdict enum. Everything goal-derived is null on a goal-less
/// (pure-ranking) board.
class ChallengePace {
  final ChallengePaceStatus status;
  final double elapsedFraction;
  final int daysRemaining;
  final num? expectedValue;
  final num? projectedValue;
  final num? remainingValue;
  final num? requiredPerDay;
  final PaceVerdict? verdict;
  const ChallengePace({
    required this.status,
    required this.elapsedFraction,
    required this.daysRemaining,
    required this.expectedValue,
    required this.projectedValue,
    required this.remainingValue,
    required this.requiredPerDay,
    required this.verdict,
  });
}

/// Project a joined runner's standing in a time-boxed goal challenge: where the
/// even-pace line sits now, whether they're ahead/behind it, and the daily rate
/// still needed to finish. All times are epoch ms so the helper stays pure and
/// timezone-free (the caller parses the ISO window). Mirrors the SQL-fed value
/// exactly — it only re-shapes the numbers the leaderboard already computed.
ChallengePace challengePace(
  num value,
  num? goal,
  int startMs,
  int endMs,
  int nowMs,
) {
  final hasGoal = goal != null && goal > 0;

  final ChallengePaceStatus status;
  final double elapsedFraction;
  if (nowMs < startMs) {
    status = ChallengePaceStatus.upcoming;
    elapsedFraction = 0;
  } else if (nowMs >= endMs || endMs <= startMs) {
    status = ChallengePaceStatus.ended;
    elapsedFraction = 1;
  } else {
    status = ChallengePaceStatus.active;
    elapsedFraction = (nowMs - startMs) / (endMs - startMs);
  }

  final daysRemaining =
      (endMs - nowMs) <= 0 ? 0 : ((endMs - nowMs) / _dayMs).ceil();
  final num? expectedValue = hasGoal ? goal * elapsedFraction : null;
  final num? remainingValue =
      hasGoal ? (goal - value > 0 ? goal - value : 0) : null;

  num? projectedValue;
  if (hasGoal && status == ChallengePaceStatus.active && elapsedFraction > 0) {
    projectedValue = value / elapsedFraction;
  } else if (hasGoal && status == ChallengePaceStatus.ended) {
    projectedValue = value;
  }

  num? requiredPerDay;
  if (hasGoal &&
      status != ChallengePaceStatus.ended &&
      daysRemaining > 0 &&
      remainingValue! > 0) {
    requiredPerDay = remainingValue / daysRemaining;
  }

  PaceVerdict? verdict;
  if (hasGoal &&
      status == ChallengePaceStatus.active &&
      value < goal &&
      expectedValue! > 0) {
    final ratio = value / expectedValue;
    if (ratio >= 1 + kOnPaceBand) {
      verdict = PaceVerdict.ahead;
    } else if (ratio < 1 - kOnPaceBand) {
      verdict = PaceVerdict.behind;
    } else {
      verdict = PaceVerdict.onTrack;
    }
  }

  return ChallengePace(
    status: status,
    elapsedFraction: elapsedFraction,
    daysRemaining: daysRemaining,
    expectedValue: expectedValue,
    projectedValue: projectedValue,
    remainingValue: remainingValue,
    requiredPerDay: requiredPerDay,
    verdict: verdict,
  );
}
