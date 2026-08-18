import 'package:flutter_test/flutter_test.dart';

import '../lib/extended_nutrients.dart';
import '../lib/hydration.dart' show maxExerciseMinutes;
import '../lib/nutrition_targets.dart';

ExtendedNutrientRow _row({
  double? fiberG,
  double? sugarG,
  double? sodiumMg,
  double? saturatedFatG,
  double? cholesterolMg,
}) =>
    ExtendedNutrientRow(
      fiberG: fiberG,
      sugarG: sugarG,
      sodiumMg: sodiumMg,
      saturatedFatG: saturatedFatG,
      cholesterolMg: cholesterolMg,
    );

NutritionTargets _targets({
  int calories = 2500,
  int baseCalories = 2500,
  int exerciseKcal = 0,
  int proteinG = 126,
  int carbsG = 300,
  int fatG = 83,
}) =>
    NutritionTargets(
      calories: calories,
      baseCalories: baseCalories,
      exerciseKcal: exerciseKcal,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
    );

NutrientBudget _budgetFor(
  NutrientKind kind,
  List<ExtendedNutrientRow> rows, {
  NutritionTargets? targets,
  num mins = 0,
}) {
  final t = targets ?? _targets();
  final all = extendedNutrientBudgets(rows, extendedNutrientTargets(t, mins));
  final match = all.where((b) => b.kind == kind).toList();
  expect(match, hasLength(1), reason: 'expected a $kind budget');
  return match.single;
}

void main() {
  test('extendedNutrients covers every nullable food_log nutrient column once',
      () {
    final columns = extendedNutrients.map((s) => s.column).toList()..sort();
    expect(columns, [
      'cholesterol_mg',
      'fiber_g',
      'saturated_fat_g',
      'sodium_mg',
      'sugar_g',
    ]);
    expect(extendedNutrients.map((s) => s.kind).toSet(),
        hasLength(extendedNutrients.length));
  });

  test('targets: fibre scales off the BASE calorie goal, not the inflated one',
      () {
    final t = _targets(baseCalories: 2500, calories: 3300, exerciseKcal: 800);
    final got = extendedNutrientTargets(t, 0);
    expect(got[NutrientKind.fiber], ((2500 / 1000) * fiberGPer1000Kcal).round());
    expect(got[NutrientKind.fiber], 35);
  });

  test('targets: saturated fat is a share of the FULL dynamic calorie goal',
      () {
    final t = _targets(baseCalories: 2500, calories: 3300, exerciseKcal: 800);
    final got = extendedNutrientTargets(t, 0);
    expect(got[NutrientKind.saturatedFat],
        ((saturatedFatKcalFraction * 3300) / 9).round());
    expect(got[NutrientKind.saturatedFat], 37);
  });

  test('targets: sodium is the flat ceiling plus a per-minute sweat allowance',
      () {
    expect(extendedNutrientTargets(_targets(), 0)[NutrientKind.sodium],
        sodiumBaselineMg);
    expect(extendedNutrientTargets(_targets(), 60)[NutrientKind.sodium],
        sodiumBaselineMg + 60 * sodiumMgPerExerciseMin);
  });

  test('targets: the sodium sweat allowance stops at maxExerciseMinutes', () {
    final capped =
        sodiumBaselineMg + maxExerciseMinutes * sodiumMgPerExerciseMin;
    expect(
        extendedNutrientTargets(_targets(), maxExerciseMinutes)[
            NutrientKind.sodium],
        capped);
    expect(extendedNutrientTargets(_targets(), 12 * 60)[NutrientKind.sodium],
        capped);
  });

  test('targets: a negative or missing exercise duration adds nothing', () {
    expect(extendedNutrientTargets(_targets(), -30)[NutrientKind.sodium],
        sodiumBaselineMg);
    expect(extendedNutrientTargets(_targets(), null)[NutrientKind.sodium],
        sodiumBaselineMg);
  });

  test('targets: with no body metrics sodium still resolves, scaled ones do not',
      () {
    final got = extendedNutrientTargets(null, 45);
    expect(got[NutrientKind.sodium],
        sodiumBaselineMg + 45 * sodiumMgPerExerciseMin);
    expect(got[NutrientKind.fiber], isNull);
    expect(got[NutrientKind.saturatedFat], isNull);
  });

  test('targets: sugar and cholesterol are deliberately ungraded', () {
    final got = extendedNutrientTargets(_targets(), 90);
    expect(got[NutrientKind.sugar], isNull);
    expect(got[NutrientKind.cholesterol], isNull);
    for (final spec in extendedNutrients) {
      if (spec.kind == NutrientKind.sugar ||
          spec.kind == NutrientKind.cholesterol) {
        expect(spec.direction, NutrientDirection.none);
      }
    }
  });

  test('budgets: a nutrient no entry reported is omitted, not shown as zero',
      () {
    final out = extendedNutrientBudgets(
      [_row(sodiumMg: 400), _row(sodiumMg: 250)],
      extendedNutrientTargets(_targets(), 0),
    );
    expect(out.map((b) => b.kind).toList(), [NutrientKind.sodium]);
  });

  test('budgets: an empty day yields nothing, so the caller self-hides', () {
    expect(extendedNutrientBudgets([], extendedNutrientTargets(_targets(), 0)),
        isEmpty);
    expect(
        extendedNutrientBudgets(
            [_row()], extendedNutrientTargets(_targets(), 0)),
        isEmpty);
  });

  test('budgets: full coverage sums every entry and reports remaining', () {
    final b =
        _budgetFor(NutrientKind.sodium, [_row(sodiumMg: 400), _row(sodiumMg: 250)]);
    expect(b.consumed, 650);
    expect(b.reportedEntries, 2);
    expect(b.totalEntries, 2);
    expect(b.partial, isFalse);
    expect(b.target, sodiumBaselineMg);
    expect(b.remaining, sodiumBaselineMg - 650);
    expect(b.exceeded, isFalse);
  });

  test('budgets: an unreported entry makes the total a lower bound', () {
    final b =
        _budgetFor(NutrientKind.sodium, [_row(sodiumMg: 400), _row(fiberG: 3)]);
    expect(b.consumed, 400);
    expect(b.reportedEntries, 1);
    expect(b.totalEntries, 2);
    expect(b.partial, isTrue);
    expect(b.remaining, isNull,
        reason: 'a "1900 mg left" claim is unsound under partial coverage');
    expect(b.exceeded, isFalse);
  });

  test('budgets: exceeding a ceiling still holds under partial coverage', () {
    final b = _budgetFor(NutrientKind.sodium,
        [_row(sodiumMg: 2600), _row(fiberG: 3), _row()]);
    expect(b.partial, isTrue);
    expect(b.exceeded, isTrue,
        reason: 'the reported entries alone already clear the ceiling');
    expect(b.remaining, isNull);
  });

  test('budgets: reaching a floor still holds under partial coverage', () {
    final b = _budgetFor(
        NutrientKind.fiber, [_row(fiberG: 36), _row(sodiumMg: 100)]);
    expect(b.partial, isTrue);
    expect(b.reached, isTrue,
        reason: 'the reported entries alone already clear the floor');
    expect(b.exceeded, isFalse);
    expect(b.remaining, isNull);
  });

  test('budgets: exactly on a ceiling is not exceeded; on a floor is reached',
      () {
    final ceiling = _budgetFor(
        NutrientKind.sodium, [_row(sodiumMg: sodiumBaselineMg.toDouble())]);
    expect(ceiling.exceeded, isFalse);
    expect(ceiling.remaining, 0);
    final floor = _budgetFor(NutrientKind.fiber, [_row(fiberG: 35)]);
    expect(floor.reached, isTrue);
    expect(floor.remaining, 0);
  });

  test('budgets: a sub-half-unit overage rounds under rather than flagging',
      () {
    // 2300.4 mg displays as 2300 against a 2300 ceiling. Flagging `exceeded`
    // here would render an overage chip reading "0 mg over" — the broken state
    // nutrition_budget.dart avoids the same way.
    final b = _budgetFor(NutrientKind.sodium, [_row(sodiumMg: 2300.4)]);
    expect(b.consumed, sodiumBaselineMg);
    expect(b.exceeded, isFalse);
    expect(b.remaining, 0);
    // Half a milligram further and it is a real, renderable overage.
    final over = _budgetFor(NutrientKind.sodium, [_row(sodiumMg: 2300.6)]);
    expect(over.consumed, sodiumBaselineMg + 1);
    expect(over.exceeded, isTrue);
  });

  test('budgets: an ungraded nutrient reports its total and nothing else', () {
    final b = _budgetFor(NutrientKind.sugar, [_row(sugarG: 42.25)]);
    expect(b.consumed, 42.3);
    expect(b.target, isNull);
    expect(b.remaining, isNull);
    expect(b.exceeded, isFalse);
    expect(b.reached, isFalse);
  });

  test('budgets: with no targets at all the totals still report, ungraded', () {
    final out = extendedNutrientBudgets(
      [_row(fiberG: 12, sodiumMg: 900)],
      extendedNutrientTargets(null, 0),
    );
    final fiber = out.firstWhere((b) => b.kind == NutrientKind.fiber);
    expect(fiber.target, isNull);
    expect(fiber.reached, isFalse);
    final sodium = out.firstWhere((b) => b.kind == NutrientKind.sodium);
    expect(sodium.target, sodiumBaselineMg,
        reason: 'sodium needs no body metrics');
  });

  test('budgets: grams round to 0.1 and milligrams to whole', () {
    final fiber = _budgetFor(
        NutrientKind.fiber, [_row(fiberG: 3.04), _row(fiberG: 4.03)]);
    expect(fiber.consumed, 7.1);
    final sodium = _budgetFor(
        NutrientKind.sodium, [_row(sodiumMg: 100.4), _row(sodiumMg: 200.4)]);
    expect(sodium.consumed, 301);
  });

  test('budgets: a non-finite stored value is treated as unreported, not NaN',
      () {
    final b = _budgetFor(NutrientKind.sodium,
        [_row(sodiumMg: double.nan), _row(sodiumMg: 300)]);
    expect(b.consumed, 300);
    expect(b.reportedEntries, 1);
    expect(b.partial, isTrue);
  });

  test('budgets: results come back in extendedNutrients display order', () {
    final out = extendedNutrientBudgets(
      [
        _row(
            fiberG: 5,
            sugarG: 9,
            sodiumMg: 300,
            saturatedFatG: 2,
            cholesterolMg: 40)
      ],
      extendedNutrientTargets(_targets(), 0),
    );
    expect(out.map((b) => b.kind).toList(),
        extendedNutrients.map((s) => s.kind).toList());
  });

  test('budgets: an ungraded nutrient never claims remaining, however much',
      () {
    final none =
        _budgetFor(NutrientKind.cholesterol, [_row(cholesterolMg: 500)]);
    expect(none.target, isNull);
    expect(none.remaining, isNull);
    expect(none.exceeded, isFalse);
  });
}
