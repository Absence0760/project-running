import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';

import '../lib/challenge_goal.dart';

const int _day = 86400000;
const List<String> _metrics = [
  'distance',
  'duration',
  'vert',
  'activity_count',
  'streak_days',
];

void main() {
  test('challengeGoalUnit names one unit for every metric the CHECK admits',
      () {
    expect(_metrics.map(challengeGoalUnit).toList(), [
      ChallengeGoalUnit.distance,
      ChallengeGoalUnit.hours,
      ChallengeGoalUnit.elevation,
      ChallengeGoalUnit.activities,
      ChallengeGoalUnit.days,
    ]);
  });

  test('a distance goal is typed in the reader own unit', () {
    expect(challengeGoalToStored(100, 'distance', DistanceUnit.km), 100000);
    expect(challengeGoalToStored(100, 'distance', DistanceUnit.mi), 160934.4);
  });

  test('an elevation goal is metres for km, feet for mi', () {
    expect(challengeGoalToStored(2000, 'vert', DistanceUnit.km), 2000);
    expect(
      challengeGoalToStored(1000, 'vert', DistanceUnit.mi),
      closeTo(304.8, 0.01),
    );
  });

  test('a duration goal is typed in hours and stored in seconds', () {
    expect(challengeGoalToStored(5, 'duration', DistanceUnit.km), 18000);
    expect(challengeGoalToStored(0.5, 'duration', DistanceUnit.mi), 1800);
  });

  test('the two counting metrics pass through unconverted under either unit',
      () {
    for (final unit in DistanceUnit.values) {
      expect(challengeGoalToStored(10, 'activity_count', unit), 10);
      expect(challengeGoalToStored(7, 'streak_days', unit), 7);
    }
  });

  test('maxStreakDaysInWindow is the count of dates a window can touch', () {
    expect(maxStreakDaysInWindow(0, _day), 2);
    expect(maxStreakDaysInWindow(0, _day + 1), 2);
    expect(maxStreakDaysInWindow(0, 2 * _day), 3);
    expect(maxStreakDaysInWindow(0, 30 * _day), 31);
  });

  test('maxStreakDaysInWindow claims nothing for an empty or inverted window',
      () {
    expect(maxStreakDaysInWindow(_day, _day), 0);
    expect(maxStreakDaysInWindow(2 * _day, _day), 0);
  });

  test('a goal-less board is always acceptable', () {
    for (final metric in _metrics) {
      expect(checkChallengeGoal(null, metric, 0, 30 * _day), null);
    }
  });

  test('a zero goal is refused — the completion RPC awards it to everyone', () {
    expect(
      checkChallengeGoal(0, 'distance', 0, 30 * _day),
      ChallengeGoalRefusal.notPositive,
    );
  });

  test('a negative or non-finite goal is refused', () {
    expect(
      checkChallengeGoal(-1, 'distance', 0, 30 * _day),
      ChallengeGoalRefusal.notPositive,
    );
    expect(
      checkChallengeGoal(double.nan, 'distance', 0, 30 * _day),
      ChallengeGoalRefusal.notPositive,
    );
    expect(
      checkChallengeGoal(double.infinity, 'distance', 0, 30 * _day),
      ChallengeGoalRefusal.notPositive,
    );
  });

  test('a streak goal inside the window ceiling is accepted', () {
    expect(checkChallengeGoal(31, 'streak_days', 0, 30 * _day), null);
  });

  test('a streak goal above the window ceiling is refused', () {
    expect(
      checkChallengeGoal(32, 'streak_days', 0, 30 * _day),
      ChallengeGoalRefusal.exceedsWindow,
    );
    expect(
      checkChallengeGoal(8, 'streak_days', 0, 3 * _day),
      ChallengeGoalRefusal.exceedsWindow,
    );
  });

  test('a duration goal longer than its own window is NOT refused', () {
    // The aggregate sums duration_s over runs whose START is in the window; a
    // run started a minute before it closes carries its whole duration, so a
    // 112-hour finish can satisfy a goal the window itself could not hold.
    expect(checkChallengeGoal(112 * 3600, 'duration', 0, _day), null);
  });

  test('the three unbounded metrics take any positive goal', () {
    for (final metric in ['distance', 'vert', 'activity_count']) {
      expect(checkChallengeGoal(1000000000, metric, 0, _day), null);
    }
  });
}
