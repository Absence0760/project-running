import 'package:flutter_test/flutter_test.dart';

import '../lib/food_search.dart';
import '../lib/nutrition_budget.dart';
import '../lib/nutrition_targets.dart';

void main() {
  test('macroBudget: under a ceiling macro reports remaining, no flags', () {
    final b = macroBudget(1400, 2000, MacroKind.calories);
    expect(b.remaining, 600);
    expect(b.over, 0);
    expect(b.exceeded, false);
    expect(b.reached, false);
  });

  test('macroBudget: over a ceiling macro flags exceeded with the overage', () {
    final b = macroBudget(2300, 2000, MacroKind.calories);
    expect(b.remaining, -300);
    expect(b.over, 300);
    expect(b.exceeded, true);
    expect(b.reached, false);
  });

  test('macroBudget: exactly on a ceiling target is not yet exceeded', () {
    final b = macroBudget(2000, 2000, MacroKind.calories);
    expect(b.remaining, 0);
    expect(b.over, 0);
    expect(b.exceeded, false);
  });

  test('macroBudget: reaching a goal macro flags reached, never exceeded', () {
    final b = macroBudget(150, 120, MacroKind.protein);
    expect(b.remaining, -30); // signed headroom is still negative
    expect(b.over, 30);
    expect(b.exceeded, false); // protein over target is a win, not a warning
    expect(b.reached, true);
  });

  test('macroBudget: a goal macro exactly on target counts as reached', () {
    expect(macroBudget(120, 120, MacroKind.protein).reached, true);
  });

  test('macroBudget: a goal macro under target is neither reached nor exceeded', () {
    final b = macroBudget(90, 120, MacroKind.carbs);
    expect(b.remaining, 30);
    expect(b.reached, false);
    expect(b.exceeded, false);
  });

  test('macroBudget: no / non-positive target hides the comparison', () {
    for (final t in <num?>[null, 0, -5]) {
      final b = macroBudget(500, t, MacroKind.calories);
      expect(b.remaining, null);
      expect(b.over, 0);
      expect(b.exceeded, false);
      expect(b.reached, false);
    }
  });

  test('macroBudget: rounds fractional consumed/target', () {
    final b = macroBudget(1999.6, 2000.2, MacroKind.calories);
    expect(b.remaining, 1); // round(2000.2 - 1999.6) = round(0.6) = 1
    expect(b.over, 0);
  });

  test('macroBudget: a sub-0.5 overage rounds to on-target, not "0 over"', () {
    // exceeded must key off the rounded `over`, never raw consumed > target —
    // otherwise the chip renders a broken "0 kcal over".
    final b = macroBudget(2000.4, 2000, MacroKind.calories);
    expect(b.over, 0);
    expect(b.exceeded, false);
    expect(b.remaining, 0);
  });

  test('macroIsCeiling: calories + fat are ceilings, protein + carbs goals', () {
    const expected = <MacroKind, bool>{
      MacroKind.calories: true,
      MacroKind.protein: false,
      MacroKind.carbs: false,
      MacroKind.fat: true,
    };
    expect(macroIsCeiling, expected);
  });

  const targets = NutritionTargets(
    calories: 2200,
    baseCalories: 2000,
    exerciseKcal: 200,
    proteinG: 120,
    carbsG: 250,
    fatG: 70,
  );

  test('computeDayBudget: returns null when no targets', () {
    const consumed = FoodMacros(calories: 500, proteinG: 20, carbsG: 40, fatG: 10);
    expect(computeDayBudget(consumed, null), null);
  });

  test('computeDayBudget: assembles all four macro budgets', () {
    const consumed = FoodMacros(calories: 2400, proteinG: 130, carbsG: 200, fatG: 80);
    final day = computeDayBudget(consumed, targets)!;
    // calories over a ceiling → exceeded
    expect(day.calories.exceeded, true);
    expect(day.calories.over, 200);
    // protein past its goal → reached, not exceeded
    expect(day.protein.reached, true);
    expect(day.protein.exceeded, false);
    // carbs under → remaining positive
    expect(day.carbs.remaining, 50);
    expect(day.carbs.reached, false);
    // fat over a ceiling → exceeded
    expect(day.fat.exceeded, true);
    expect(day.fat.over, 10);
  });
}
