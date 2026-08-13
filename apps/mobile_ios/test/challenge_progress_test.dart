import 'package:flutter_test/flutter_test.dart';

import '../lib/challenge_progress.dart';

const int _day = 86400000;

void main() {
  test('progressFraction clamps to 0..1', () {
    expect(progressFraction(50, 100), 0.5);
    expect(progressFraction(150, 100), 1);
    expect(progressFraction(-10, 100), 0);
  });

  test('progressFraction null goal -> null', () {
    expect(progressFraction(50, null), null);
    expect(progressFraction(50, 0), null);
  });

  test('isComplete respects >= goal', () {
    expect(isComplete(99, 100), false);
    expect(isComplete(100, 100), true);
    expect(isComplete(101, 100), true);
    expect(isComplete(100, null), false);
  });

  test('progressParts bundles fraction + complete', () {
    final p = progressParts(ChallengeMetric.distance, 60000, 100000);
    expect(p.metric, ChallengeMetric.distance);
    expect(p.value, 60000);
    expect(p.goal, 100000);
    expect(p.fraction, 0.6);
    expect(p.complete, false);
  });

  test('progressParts goal-less board has null fraction', () {
    final p = progressParts(ChallengeMetric.distance, 60000, null);
    expect(p.fraction, null);
    expect(p.complete, false);
  });

  test('metricFromActivity distance reads distance_m (number or string)', () {
    expect(metricFromActivity({'distance_m': 5000}, ChallengeMetric.distance, null), 5000);
    expect(metricFromActivity({'distance_m': '5000'}, ChallengeMetric.distance, null), 5000);
  });

  test('metricFromActivity duration reads duration_s', () {
    expect(metricFromActivity({'duration_s': 1800}, ChallengeMetric.duration, null), 1800);
  });

  test('metricFromActivity vert reads elevation_gain_m (number or string, missing → 0)', () {
    expect(metricFromActivity({'elevation_gain_m': 640}, ChallengeMetric.vert, null), 640);
    expect(metricFromActivity({'elevation_gain_m': '640'}, ChallengeMetric.vert, null), 640);
    expect(metricFromActivity({}, ChallengeMetric.vert, null), 0);
  });

  test('metricFromActivity count + streak each contribute 1', () {
    expect(metricFromActivity({}, ChallengeMetric.activityCount, null), 1);
    expect(metricFromActivity({}, ChallengeMetric.streakDays, null), 1);
  });

  test('metricFromActivity activity_type filter excludes non-matching', () {
    expect(
        metricFromActivity({'distance_m': 5000, 'activity_type': 'walk'}, ChallengeMetric.distance, 'run'),
        0);
    expect(
        metricFromActivity({'distance_m': 5000, 'activity_type': 'run'}, ChallengeMetric.distance, 'run'),
        5000);
  });

  test('metricFromActivity excludes a DNF run from every metric', () {
    // Mirrors the server aggregate's `and r.is_dnf = false` — a 42 km effort
    // dropped mid-race must not bank toward a "run 100 km" challenge estimate.
    expect(metricFromActivity({'distance_m': 42000, 'is_dnf': true}, ChallengeMetric.distance, null), 0);
    expect(metricFromActivity({'duration_s': 1800, 'is_dnf': true}, ChallengeMetric.duration, null), 0);
    expect(metricFromActivity({'is_dnf': true}, ChallengeMetric.activityCount, null), 0);
    // A finished (non-DNF) run still counts in full.
    expect(metricFromActivity({'distance_m': 42000, 'is_dnf': false}, ChallengeMetric.distance, null), 42000);
  });

  test('metricFromActivity defaults missing activity_type to run', () {
    expect(metricFromActivity({'distance_m': 5000}, ChallengeMetric.distance, 'run'), 5000);
  });

  test('metricFromActivity coerces null/garbage to 0', () {
    expect(metricFromActivity({'distance_m': null}, ChallengeMetric.distance, null), 0);
    expect(metricFromActivity({'distance_m': 'abc'}, ChallengeMetric.distance, null), 0);
  });

  test('rankParticipants orders by value desc with stable user_id tie-break', () {
    final ranked = rankParticipants([
      const RankableEntry(userId: 'b', value: 30),
      const RankableEntry(userId: 'a', value: 50),
      const RankableEntry(userId: 'c', value: 50),
    ]);
    expect(ranked.map((r) => [r.entry.userId, r.rank]).toList(), [
      ['a', 1],
      ['c', 1],
      ['b', 3],
    ]);
  });

  test('rankParticipants falls back to team_club_id for team boards', () {
    final ranked = rankParticipants([
      const RankableEntry(teamClubId: 'blue', value: 50),
      const RankableEntry(teamClubId: 'red', value: 50),
    ]);
    expect(ranked.map((r) => [r.entry.teamClubId, r.rank]).toList(), [
      ['blue', 1],
      ['red', 1],
    ]);
  });

  test('rankParticipants sorts the keyless team last, like the SQL nulls last',
      () {
    // challenge_leaderboard's team branch ends `order by rank, pt.team_club_id
    // nulls last`, so the unaffiliated bucket (a deleted club, or a member who
    // joined without picking one) trails the named clubs it ties with.
    // Collapsing the null key to '' would put it first.
    final ranked = rankParticipants([
      const RankableEntry(value: 50),
      const RankableEntry(teamClubId: 'red', value: 50),
      const RankableEntry(teamClubId: 'blue', value: 50),
    ]);
    expect(ranked.map((r) => [r.entry.teamClubId, r.rank]).toList(), [
      ['blue', 1],
      ['red', 1],
      [null, 1],
    ]);
  });

  test('a keyless entry still outranks a lower value — nulls last is a tie-break only',
      () {
    final ranked = rankParticipants([
      const RankableEntry(teamClubId: 'red', value: 10),
      const RankableEntry(value: 90),
    ]);
    expect(ranked.map((r) => [r.entry.teamClubId, r.rank]).toList(), [
      [null, 1],
      ['red', 2],
    ]);
  });

  test('challengePace on_track at the even-pace line mid-window', () {
    final p = challengePace(50, 100, 0, 10 * _day, 5 * _day);
    expect(p.status, ChallengePaceStatus.active);
    expect(p.elapsedFraction, 0.5);
    expect(p.expectedValue, 50);
    expect(p.projectedValue, 100);
    expect(p.remainingValue, 50);
    expect(p.daysRemaining, 5);
    expect(p.requiredPerDay, 10);
    expect(p.verdict, PaceVerdict.onTrack);
  });

  test('challengePace behind flags the daily rate needed to finish', () {
    final p = challengePace(30, 100, 0, 10 * _day, 5 * _day);
    expect(p.verdict, PaceVerdict.behind);
    expect(p.projectedValue, 60);
    expect(p.remainingValue, 70);
    expect(p.requiredPerDay, 14);
  });

  test('challengePace ahead when past the even-pace line', () {
    final p = challengePace(70, 100, 0, 10 * _day, 5 * _day);
    expect(p.verdict, PaceVerdict.ahead);
    expect(p.projectedValue, 140);
    expect(p.requiredPerDay, 6);
  });

  test('challengePace goal-less board nulls every goal-derived field', () {
    final p = challengePace(50, null, 0, 10 * _day, 5 * _day);
    expect(p.status, ChallengePaceStatus.active);
    expect(p.elapsedFraction, 0.5);
    expect(p.daysRemaining, 5);
    expect(p.expectedValue, null);
    expect(p.projectedValue, null);
    expect(p.remainingValue, null);
    expect(p.requiredPerDay, null);
    expect(p.verdict, null);
  });

  test('challengePace upcoming has no projection or verdict yet', () {
    final p = challengePace(0, 100, 2 * _day, 12 * _day, 0);
    expect(p.status, ChallengePaceStatus.upcoming);
    expect(p.elapsedFraction, 0);
    expect(p.projectedValue, null);
    expect(p.verdict, null);
    expect(p.daysRemaining, 10);
    expect(p.requiredPerDay, 10);
  });

  test('challengePace upcoming daysRemaining counts only the open window', () {
    final p = challengePace(0, 70, 2 * _day, 12 * _day, 0);
    expect(p.status, ChallengePaceStatus.upcoming);
    expect(p.daysRemaining, 10);
    expect(p.requiredPerDay, 7);
  });

  test('challengePace ended freezes projection to the final value', () {
    final p = challengePace(80, 100, 0, 10 * _day, 11 * _day);
    expect(p.status, ChallengePaceStatus.ended);
    expect(p.elapsedFraction, 1);
    expect(p.projectedValue, 80);
    expect(p.remainingValue, 20);
    expect(p.requiredPerDay, null);
    expect(p.verdict, null);
    expect(p.daysRemaining, 0);
  });

  test('challengePace complete drops the verdict + required rate', () {
    final p = challengePace(120, 100, 0, 10 * _day, 5 * _day);
    expect(p.verdict, null);
    expect(p.remainingValue, 0);
    expect(p.requiredPerDay, null);
  });

  test('challengePace daysRemaining ceils a partial day', () {
    final p = challengePace(40, 100, 0, 10 * _day, (5.5 * _day).round());
    expect(p.daysRemaining, 5);
    expect(p.requiredPerDay, 12);
  });

  RecomputeCandidate candidate({
    String id = 'c1',
    num? goalValue = 100,
    int startMs = 0,
    int endMs = 10 * _day,
    bool completed = false,
  }) =>
      RecomputeCandidate(
        id: id,
        goalValue: goalValue,
        startMs: startMs,
        endMs: endMs,
        completed: completed,
      );

  test('challengesToRecomputeForRun includes a goal challenge whose window covers the run',
      () {
    expect(challengesToRecomputeForRun([candidate()], 5 * _day), ['c1']);
  });

  test('challengesToRecomputeForRun excludes a goal-less (pure-ranking) board', () {
    expect(challengesToRecomputeForRun([candidate(goalValue: null)], 5 * _day), []);
  });

  test('challengesToRecomputeForRun excludes an already-completed challenge', () {
    expect(challengesToRecomputeForRun([candidate(completed: true)], 5 * _day), []);
  });

  test('challengesToRecomputeForRun excludes a run before the window opens', () {
    expect(challengesToRecomputeForRun([candidate(startMs: 2 * _day)], _day), []);
  });

  test('challengesToRecomputeForRun excludes a run at/after ends_at (half-open window)',
      () {
    expect(challengesToRecomputeForRun([candidate()], 10 * _day), []);
    expect(challengesToRecomputeForRun([candidate()], 0), ['c1']);
  });

  test('challengesToRecomputeForRun returns only the qualifying ids in input order', () {
    final cs = [
      candidate(id: 'a'),
      candidate(id: 'b', completed: true),
      candidate(id: 'c', goalValue: null),
      candidate(id: 'd', endMs: 3 * _day),
    ];
    expect(challengesToRecomputeForRun(cs, 5 * _day), ['a']);
  });

  test('challengesToRecomputeForRun returns [] for a non-finite run time', () {
    expect(challengesToRecomputeForRun([candidate()], double.nan), []);
  });
}
