import 'package:flutter_test/flutter_test.dart';

import '../lib/nutrition_week.dart';

void main() {
  test('weeklyIntakeSummary: averages over logged days only, ignores empty days', () {
    // Three logged days (2000, 2400, 2200), four empty → avg 2200.
    final s = weeklyIntakeSummary([0, 2000, 0, 2400, 0, 2200, 0], 2300);
    expect(s.loggedDays, 3);
    expect(s.avgCalories, 2200);
    expect(s.deltaPerDay, -100); // 2200 − 2300 under goal
  });

  test('weeklyIntakeSummary: over goal yields a positive delta', () {
    final s = weeklyIntakeSummary([2600, 2600], 2300);
    expect(s.avgCalories, 2600);
    expect(s.deltaPerDay, 300);
  });

  test('weeklyIntakeSummary: exactly on goal yields a zero delta', () {
    final s = weeklyIntakeSummary([2300], 2300);
    expect(s.deltaPerDay, 0);
  });

  test('weeklyIntakeSummary: no logged days → zero avg, null delta', () {
    final s = weeklyIntakeSummary([0, 0, 0], 2300);
    expect(s.loggedDays, 0);
    expect(s.avgCalories, 0);
    expect(s.deltaPerDay, null);
  });

  test('weeklyIntakeSummary: empty input is all-zero, null delta', () {
    final s = weeklyIntakeSummary([], 2300);
    expect(s.loggedDays, 0);
    expect(s.avgCalories, 0);
    expect(s.deltaPerDay, null);
  });

  test('weeklyIntakeSummary: missing/non-positive target hides the delta', () {
    for (final t in <num?>[null, 0, -100]) {
      final s = weeklyIntakeSummary([2000, 2200], t);
      expect(s.avgCalories, 2100);
      expect(s.deltaPerDay, null);
    }
  });

  test('weeklyIntakeSummary: rounds a fractional average', () {
    final s = weeklyIntakeSummary([2000, 2001], 2000);
    expect(s.avgCalories, 2001); // round(4001/2) = round(2000.5) = 2001
    expect(s.deltaPerDay, 1);
  });

  test('weeklyIntakeSummary: a fractional target yields a whole-number delta (twin parity)', () {
    // The target is rounded before subtraction so the delta is always a whole
    // number of kcal, matching the web twin (avgCalories is already rounded).
    final s = weeklyIntakeSummary([2200], 2300.4);
    expect(s.deltaPerDay, -100);
  });

  test('weeklyProteinSummary: counts logged days that reached the protein goal', () {
    // Four logged days (150, 120, 165, 130), three empty. Goal 140 → 2 of 4 met.
    final s = weeklyProteinSummary([0, 150, 0, 120, 165, 0, 130], 140);
    expect(s.loggedDays, 4);
    expect(s.avgProteinG, 141); // round((150+120+165+130)/4) = round(141.25)
    expect(s.daysMetGoal, 2);
  });

  test('weeklyProteinSummary: hitting the target exactly counts as met (floor, not ceiling)', () {
    final s = weeklyProteinSummary([140, 139], 140);
    expect(s.daysMetGoal, 1);
  });

  test('weeklyProteinSummary: all logged days can meet the goal', () {
    final s = weeklyProteinSummary([150, 160, 170], 140);
    expect(s.loggedDays, 3);
    expect(s.daysMetGoal, 3);
  });

  test('weeklyProteinSummary: no logged days → zero avg, null daysMetGoal', () {
    final s = weeklyProteinSummary([0, 0, 0], 140);
    expect(s.loggedDays, 0);
    expect(s.avgProteinG, 0);
    expect(s.daysMetGoal, null);
  });

  test('weeklyProteinSummary: empty input is all-zero, null daysMetGoal', () {
    final s = weeklyProteinSummary([], 140);
    expect(s.loggedDays, 0);
    expect(s.avgProteinG, 0);
    expect(s.daysMetGoal, null);
  });

  test('weeklyProteinSummary: missing/non-positive target hides daysMetGoal but keeps the average', () {
    for (final t in <num?>[null, 0, -20]) {
      final s = weeklyProteinSummary([120, 140], t);
      expect(s.loggedDays, 2);
      expect(s.avgProteinG, 130);
      expect(s.daysMetGoal, null);
    }
  });
}
