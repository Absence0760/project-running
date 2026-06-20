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

enum ChallengeMetric { distance, duration, activityCount, streakDays }

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
/// not per activity). Returns 0 when the activity type doesn't match the filter.
num metricFromActivity(
  Map<String, dynamic> summary,
  ChallengeMetric metric,
  String? activityTypeFilter,
) {
  if (activityTypeFilter != null &&
      (summary['activity_type'] as String? ?? 'run') != activityTypeFilter) {
    return 0;
  }
  switch (metric) {
    case ChallengeMetric.distance:
      return _numberOf(summary['distance_m']);
    case ChallengeMetric.duration:
      return _numberOf(summary['duration_s']);
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
