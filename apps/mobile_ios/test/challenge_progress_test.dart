import 'package:flutter_test/flutter_test.dart';

import '../lib/challenge_progress.dart';

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
}
