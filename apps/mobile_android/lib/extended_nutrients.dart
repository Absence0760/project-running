/// Daily roll-up + budget for the five extended nutrients (`food_log`'s
/// `fiber_g` / `sugar_g` / `sodium_mg` / `saturated_fat_g` / `cholesterol_mg`,
/// issue #492).
///
/// Dart twin of `apps/web/src/lib/nutrition/extended_nutrients.ts` — keep the
/// algorithm, constants, edge cases, outputs, and test counts in lockstep.
///
/// The reason a plain sum is not enough — and the whole point of this module —
/// is **coverage**. Both food sources carry these fields unevenly, so a null is
/// the common case, and `sumMacros`' "null counts as 0" rule (right for
/// calories, where a partially-logged item should still contribute) becomes a
/// fail-open claim here: eight logged items of which two report sodium sum to a
/// number that reads as the day's intake and sits comfortably under a ceiling
/// it may in fact have blown past.
///
/// So a total is accompanied by how many entries actually reported it, and only
/// the claims that survive partial coverage are ever offered:
///
/// - `exceeded` (a ceiling nutrient past target) and `reached` (a floor
///   nutrient at/past target) are **monotone** — the reported entries alone
///   already clear the line, and the unreported ones can only add more. Sound
///   under partial coverage.
/// - `remaining` ("600 mg left") is a claim about the day's *whole* intake, and
///   the unreported entries could have consumed all of it. Withheld — null —
///   whenever coverage is partial.
///
/// Targets are public reference intakes, not prescriptions, and two of the five
/// deliberately have **none**:
///
/// - **Fibre** — floor, 14 g per 1000 kcal (IOM/DGA adequate intake). Scaled
///   off the *base* calorie goal, not the exercise-inflated one: the reference
///   is an adequacy figure for ordinary intake, and the extra carbohydrate a
///   long-run day earns is deliberately low-residue. Scaling it by workout
///   calories would prescribe 50 g+ of fibre on exactly the day a runner wants
///   least of it.
/// - **Sodium** — ceiling, 2300 mg (FDA daily value) plus a sweat allowance.
///   The population ceiling is the wrong ceiling for someone who just sweated
///   out two litres, so it rises with logged exercise on the same "base +
///   exercise" model as the calorie goal (decisions §134) and the water goal.
///   The per-minute figure is derived from `hydration.dart`'s own assumption:
///   480 ml/hr of sweat replacement at a conservative ~700 mg of sodium per
///   litre is ~5.6 mg/min, rounded to 6. It shares that module's
///   [maxExerciseMinutes] cap for the same reason — past four hours this is a
///   race fuel plan (`fuel_plan.dart`), not a daily baseline.
/// - **Saturated fat** — ceiling, 10 % of calories (DGA). A percentage of
///   energy, so it correctly scales with the *full* dynamic goal.
/// - **Sugar** — no target. The stored field is *total* sugars, including the
///   fruit and milk sugar in a perfectly good diet, while every published
///   ceiling (WHO's 10 % of energy) is about *free/added* sugars. Grading total
///   sugars against a free-sugar limit would flag a bowl of fruit as an
///   overshoot, so the total is reported and left ungraded.
/// - **Cholesterol** — no target. The 300 mg/day cap was removed from the
///   Dietary Guidelines in 2015 and no numeric limit replaced it. Reported,
///   ungraded — inventing a threshold would be worse than showing none.
///
/// Two idiomatic shape differences from the web twin, neither a divergence:
/// TypeScript indexes the row structurally with `keyof`, so this side carries a
/// nominal [ExtendedNutrientRow] with a [ExtendedNutrientRow.valueOf] lookup on
/// the same column names; and [NutrientSpec.labelKey] holds the camelCase ARB
/// identifier against web's dotted `MessageKey`, resolved at the render layer
/// exactly as `badges.dart` does — the key strings are not part of the
/// lockstep, the kinds / columns / directions / units / thresholds are.
///
/// Pure functions, no Flutter / Supabase deps.
library;

import 'dart:math' as math;

import 'hydration.dart' show maxExerciseMinutes;
import 'nutrition_targets.dart';

enum NutrientKind { fiber, sugar, sodium, saturatedFat, cholesterol }

/// Which way overshooting a nutrient reads. [NutrientDirection.none] = reported
/// but ungraded.
enum NutrientDirection { floor, ceiling, none }

/// The five nullable `food_log` nutrient columns a day is rolled up over.
class ExtendedNutrientRow {
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;
  final double? saturatedFatG;
  final double? cholesterolMg;

  const ExtendedNutrientRow({
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
    this.saturatedFatG,
    this.cholesterolMg,
  });

  double? valueOf(String column) {
    switch (column) {
      case 'fiber_g':
        return fiberG;
      case 'sugar_g':
        return sugarG;
      case 'sodium_mg':
        return sodiumMg;
      case 'saturated_fat_g':
        return saturatedFatG;
      case 'cholesterol_mg':
        return cholesterolMg;
    }
    return null;
  }
}

class NutrientSpec {
  final NutrientKind kind;
  final String column;
  final NutrientDirection direction;

  /// `'g'` or `'mg'`.
  final String unit;

  /// ARB key identifier for the nutrient's display name, resolved at the
  /// render layer.
  final String labelKey;

  const NutrientSpec({
    required this.kind,
    required this.column,
    required this.direction,
    required this.unit,
    required this.labelKey,
  });
}

/// Display order for the day's nutrient list: the three graded nutrients
/// first, most useful to a runner first, then the ungraded pair.
const extendedNutrients = <NutrientSpec>[
  NutrientSpec(
      kind: NutrientKind.sodium,
      column: 'sodium_mg',
      direction: NutrientDirection.ceiling,
      unit: 'mg',
      labelKey: 'nutritionSodium'),
  NutrientSpec(
      kind: NutrientKind.fiber,
      column: 'fiber_g',
      direction: NutrientDirection.floor,
      unit: 'g',
      labelKey: 'nutritionFiber'),
  NutrientSpec(
      kind: NutrientKind.saturatedFat,
      column: 'saturated_fat_g',
      direction: NutrientDirection.ceiling,
      unit: 'g',
      labelKey: 'nutritionSaturatedFat'),
  NutrientSpec(
      kind: NutrientKind.sugar,
      column: 'sugar_g',
      direction: NutrientDirection.none,
      unit: 'g',
      labelKey: 'nutritionSugar'),
  NutrientSpec(
      kind: NutrientKind.cholesterol,
      column: 'cholesterol_mg',
      direction: NutrientDirection.none,
      unit: 'mg',
      labelKey: 'nutritionCholesterol'),
];

/// Grams of fibre per 1000 kcal of the base calorie goal.
const fiberGPer1000Kcal = 14;

/// Flat population sodium ceiling before any sweat allowance (mg).
const sodiumBaselineMg = 2300;

/// Sodium the ceiling rises by per minute of logged exercise (mg).
const sodiumMgPerExerciseMin = 6;

/// Share of total calories allowed from saturated fat.
const saturatedFatKcalFraction = 0.1;

const _kcalPerGFat = 9;

/// Rounds half toward positive infinity, matching JS `Math.round` — so this
/// side agrees with the canonical web twin on negative .5 ties
/// (`Math.round(-0.5) == 0`, where Dart's `.round()` gives -1).
int _roundHalfUp(num value) => (value + 0.5).floor();

/// Daily reference intakes for the five extended nutrients. [targets] may be
/// null (no body metrics) — fibre and saturated fat then have no basis to
/// scale from and return null, while sodium still resolves, because its
/// reference is a flat ceiling plus a sweat allowance and needs neither
/// bodyweight nor a calorie goal. That is the same reason `hydrationTargetMl`
/// always answers.
Map<NutrientKind, int?> extendedNutrientTargets(
  NutritionTargets? targets,
  num? exerciseMinutes,
) {
  final countedMinutes = exerciseMinutes != null && exerciseMinutes > 0
      ? math.min(exerciseMinutes, maxExerciseMinutes)
      : 0;
  return <NutrientKind, int?>{
    NutrientKind.sodium:
        _roundHalfUp(sodiumBaselineMg + countedMinutes * sodiumMgPerExerciseMin),
    NutrientKind.fiber: targets != null && targets.baseCalories > 0
        ? _roundHalfUp((targets.baseCalories / 1000) * fiberGPer1000Kcal)
        : null,
    NutrientKind.saturatedFat: targets != null && targets.calories > 0
        ? _roundHalfUp(
            (saturatedFatKcalFraction * targets.calories) / _kcalPerGFat)
        : null,
    NutrientKind.sugar: null,
    NutrientKind.cholesterol: null,
  };
}

class NutrientBudget {
  final NutrientKind kind;
  final NutrientDirection direction;
  final String unit;
  final String labelKey;

  /// Sum over the entries that REPORTED this nutrient. Grams round to 0.1,
  /// milligrams to whole.
  final double consumed;
  final int? target;

  /// Headroom under a ceiling / shortfall to a floor, never negative. Null
  /// with no target AND null whenever coverage is partial: the unreported
  /// entries could have consumed all of it.
  final double? remaining;

  /// A ceiling nutrient measurably past its target. Monotone, so it holds
  /// under partial coverage.
  final bool exceeded;

  /// A floor nutrient at or past its target. Monotone, same as above.
  final bool reached;

  /// Entries that reported this nutrient, and the day's total entry count.
  final int reportedEntries;
  final int totalEntries;

  /// At least one entry did not report this nutrient, so [consumed] is a lower
  /// bound on the day rather than the day.
  final bool partial;

  const NutrientBudget({
    required this.kind,
    required this.direction,
    required this.unit,
    required this.labelKey,
    required this.consumed,
    required this.target,
    required this.remaining,
    required this.exceeded,
    required this.reached,
    required this.reportedEntries,
    required this.totalEntries,
    required this.partial,
  });
}

double _roundFor(String unit, double value) =>
    unit == 'g' ? _roundHalfUp(value * 10) / 10 : _roundHalfUp(value).toDouble();

/// One budget per extended nutrient that at least one entry reported, in
/// [extendedNutrients] order. A nutrient nothing reported is omitted rather
/// than shown as zero — an empty row is not a measurement, and the caller
/// self-hides the whole section on an empty result (anti-clutter,
/// multi_modal.md).
List<NutrientBudget> extendedNutrientBudgets(
  List<ExtendedNutrientRow> rows,
  Map<NutrientKind, int?> targets,
) {
  final out = <NutrientBudget>[];
  for (final spec in extendedNutrients) {
    var sum = 0.0;
    var reported = 0;
    for (final row in rows) {
      final raw = row.valueOf(spec.column);
      if (raw == null || !raw.isFinite) continue;
      sum += raw;
      reported += 1;
    }
    if (reported == 0) continue;
    // Graded against the ROUNDED total, i.e. the number the row displays, not
    // the raw sum — so a sub-half-unit overage can't flag `exceeded` while the
    // overage it would render rounds to "0 mg over". Same reasoning as
    // `nutrition_budget.dart`, which keys `exceeded` off its rounded `over`.
    final consumed = _roundFor(spec.unit, sum);
    final target = targets[spec.kind];
    final partial = reported < rows.length;
    final hasTarget = target != null && target > 0;
    out.add(NutrientBudget(
      kind: spec.kind,
      direction: spec.direction,
      unit: spec.unit,
      labelKey: spec.labelKey,
      consumed: consumed,
      target: hasTarget ? target : null,
      remaining: hasTarget && !partial
          ? math.max(0, _roundFor(spec.unit, target - consumed))
          : null,
      exceeded: hasTarget &&
          spec.direction == NutrientDirection.ceiling &&
          consumed > target,
      reached: hasTarget &&
          spec.direction == NutrientDirection.floor &&
          consumed >= target,
      reportedEntries: reported,
      totalEntries: rows.length,
      partial: partial,
    ));
  }
  return out;
}
