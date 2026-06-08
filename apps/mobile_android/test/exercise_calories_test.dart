import 'package:flutter_test/flutter_test.dart';

import '../lib/exercise_calories.dart';

void main() {
  test('runCalories: 70 kg over 10 km ~= 1.036*70*10', () {
    expect(runCalories(10000, 70), closeTo(kcalPerKgPerKm * 70 * 10, 1e-9));
  });

  test('runCalories: scales linearly with distance', () {
    expect(runCalories(5000, 70), closeTo(runCalories(10000, 70) / 2, 1e-9));
  });

  test('runCalories: missing or non-physical inputs -> 0', () {
    expect(runCalories(null, 70), 0);
    expect(runCalories(10000, null), 0);
    expect(runCalories(0, 70), 0);
    expect(runCalories(10000, 0), 0);
    expect(runCalories(-100, 70), 0);
    expect(runCalories(10000, -5), 0);
  });

  test('gymCalories: 70 kg for 1 h ~= MET*70*1', () {
    expect(gymCalories(3600, 70), closeTo(gymMet * 70, 1e-9));
  });

  test('gymCalories: half the duration -> half the burn', () {
    expect(gymCalories(1800, 70), closeTo(gymCalories(3600, 70) / 2, 1e-9));
  });

  test('gymCalories: missing or non-physical inputs -> 0', () {
    expect(gymCalories(null, 70), 0);
    expect(gymCalories(3600, null), 0);
    expect(gymCalories(0, 70), 0);
    expect(gymCalories(3600, 0), 0);
  });

  test('exerciseCaloriesForDay: sums runs + gym, rounded once', () {
    final total = exerciseCaloriesForDay(
      runs: const [RunForCalories(10000), RunForCalories(5000)],
      gymSessions: const [GymSessionForCalories(3600)],
      weightKg: 70,
    );
    final expected =
        (kcalPerKgPerKm * 70 * 10 + kcalPerKgPerKm * 70 * 5 + gymMet * 70)
            .round();
    expect(total, expected);
  });

  test('exerciseCaloriesForDay: unknown bodyweight -> 0', () {
    expect(
      exerciseCaloriesForDay(
        runs: const [RunForCalories(10000)],
        gymSessions: const [GymSessionForCalories(3600)],
        weightKg: null,
      ),
      0,
    );
  });

  test('exerciseCaloriesForDay: no activities -> 0', () {
    expect(
      exerciseCaloriesForDay(runs: const [], gymSessions: const [], weightKg: 70),
      0,
    );
  });

  test('exerciseCaloriesForDay: ignores rows missing their metric', () {
    expect(
      exerciseCaloriesForDay(
        runs: const [RunForCalories(null)],
        gymSessions: const [GymSessionForCalories(null)],
        weightKg: 70,
      ),
      0,
    );
  });
}
