/// Nutrition targets — daily calorie + macro goals from body metrics.
///
/// Dart twin of `apps/web/src/lib/nutrition/nutrition_targets.ts` — keep the
/// algorithm, constants, edge cases, and test counts in lockstep.
///
/// The numbers are well-known sports-nutrition heuristics, not proprietary
/// research, and are deliberately conservative — a default the user can
/// override in Settings, not a prescription:
///
/// - **BMR (Mifflin-St Jeor):** `10*kg + 6.25*cm - 5*age + sexOffset`, where
///   the sex offset is +5 (male) / -161 (female) / -78 (the male/female
///   average) when sex is non-binary, withheld, or unknown.
/// - **Base TDEE:** BMR x a *baseline* (non-exercise) activity factor
///   (sedentary..very active = daily lifestyle EXCLUDING workouts you log). A
///   goal delta (-500 lose / 0 maintain / +300 gain kcal) is applied after.
/// - **Dynamic TDEE:** measured workout calories (`exerciseKcal`, from
///   `exercise_calories.dart`) are added ON TOP of the base — the "base +
///   exercise" model (decisions §63 amendment). So the activity level should
///   reflect daily life only; logged runs/lifts raise the goal separately and
///   double-counting is avoided. `calories` is the final eat-to goal,
///   `baseCalories` the non-exercise floor, `exerciseKcal` the day's add-on.
/// - **Macros:** protein at 1.8 g/kg bodyweight (endurance-athlete range
///   1.6-2.0), fat at 30% of calories, carbohydrate filling the remainder, so
///   the extra exercise calories land mostly as fuel (carbs). Carbs floor at 0
///   if protein+fat already exhaust the budget.
///
/// [computeNutritionTargets] returns null when any required metric is missing
/// or non-physical, so the UI hides the rings rather than render a
/// zeroed/garbage target (anti-clutter checklist, multi_modal.md).
///
/// Pure functions, no Flutter / Supabase deps.
library;

import 'dart:math' as math;

class ActivityLevelOption {
  final String key;
  final String label;
  final double factor;
  const ActivityLevelOption(this.key, this.label, this.factor);
}

/// Baseline (non-exercise) activity multipliers applied to BMR. Order is the
/// display order in Settings (least -> most active). Labels describe daily
/// lifestyle EXCLUDING logged workouts — those are added separately as
/// `exerciseKcal`, so a runner picking a high level here AND logging runs
/// would double-count.
const activityLevels = <ActivityLevelOption>[
  ActivityLevelOption('sedentary', 'Mostly sitting (desk job)', 1.2),
  ActivityLevelOption('light', 'Lightly active (light daily movement)', 1.375),
  ActivityLevelOption('moderate', 'Moderately active (on your feet often)', 1.55),
  ActivityLevelOption('active', 'Very active day (physical job)', 1.725),
  ActivityLevelOption('very_active', 'Extremely active (hard physical labour)', 1.9),
];

/// Daily calorie delta applied after TDEE for the user's weight goal.
const goalKcalDelta = <String, double>{
  'lose': -500,
  'maintain': 0,
  'gain': 300,
};

/// Grams of protein per kg of bodyweight (endurance-athlete default).
const proteinGPerKg = 1.8;

/// Share of total calories from fat.
const fatKcalFraction = 0.3;

/// Lowest calorie target we will ever recommend — a safety floor, not a
/// medical clamp. Below this the default is suspect; the user can still
/// override.
const minCalorieTarget = 1200;

const _kcalPerGProtein = 4;
const _kcalPerGCarb = 4;
const _kcalPerGFat = 9;

class NutritionTargets {
  /// Final daily eat-to goal = baseCalories + exerciseKcal.
  final int calories;

  /// Non-exercise goal (BMR x baseline factor + goal delta), floored.
  final int baseCalories;

  /// Measured workout calories added on top for the day (0 when none).
  final int exerciseKcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  const NutritionTargets({
    required this.calories,
    required this.baseCalories,
    required this.exerciseKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

class BodyMetricsInput {
  final double? weightKg;
  final double? heightCm;
  final int? ageYears;
  final String? sex;
  final String activityLevel;
  final String goal;

  /// Calories burned by today's logged workouts, added on top of the base
  /// (dynamic TDEE). Defaults to 0 — omit for the static base goal.
  final double exerciseKcal;
  const BodyMetricsInput({
    required this.weightKg,
    required this.heightCm,
    required this.ageYears,
    required this.sex,
    required this.activityLevel,
    required this.goal,
    this.exerciseKcal = 0,
  });
}

double _sexOffset(String? sex) {
  if (sex == 'male') return 5;
  if (sex == 'female') return -161;
  return -78;
}

double _factorFor(String level) {
  for (final a in activityLevels) {
    if (a.key == level) return a.factor;
  }
  return 1.55;
}

/// Mifflin-St Jeor resting metabolic rate (kcal/day).
double mifflinStJeorBmr(
  double weightKg,
  double heightCm,
  int ageYears,
  String? sex,
) {
  return 10 * weightKg + 6.25 * heightCm - 5 * ageYears + _sexOffset(sex);
}

/// Whole-year age from an ISO `YYYY-MM-DD` date of birth, evaluated at
/// [nowMs]. Returns null on a missing / malformed date or an out-of-range
/// result. Parsed by calendar components (no timezone dependence) so the
/// TS twin matches exactly.
int? ageFromDob(String? dobIso, int nowMs) {
  if (dobIso == null || dobIso.isEmpty) return null;
  final head = dobIso.length >= 10 ? dobIso.substring(0, 10) : dobIso;
  final parts = head.split('-');
  if (parts.length < 3) return null;
  final by = int.tryParse(parts[0]);
  final bm = int.tryParse(parts[1]);
  final bd = int.tryParse(parts[2]);
  if (by == null || bm == null || bd == null || by == 0 || bm == 0 || bd == 0) {
    return null;
  }
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
  final ny = now.year;
  final nm = now.month;
  final nd = now.day;
  var age = ny - by;
  if (nm < bm || (nm == bm && nd < bd)) age -= 1;
  if (age < 0 || age > 120) return null;
  return age;
}

/// Daily calorie + macro targets, or null when a required metric is missing
/// or non-physical (so the caller can hide the surface).
NutritionTargets? computeNutritionTargets(BodyMetricsInput input) {
  final weightKg = input.weightKg;
  final heightCm = input.heightCm;
  final ageYears = input.ageYears;
  if (weightKg == null || heightCm == null || ageYears == null) return null;
  if (weightKg <= 0 || heightCm <= 0 || ageYears <= 0) return null;
  if (weightKg > 500 || heightCm > 300 || ageYears > 120) return null;

  final bmr = mifflinStJeorBmr(weightKg, heightCm, ageYears, input.sex);
  final baseTdee =
      bmr * _factorFor(input.activityLevel) + (goalKcalDelta[input.goal] ?? 0);
  final baseCalories = math.max(minCalorieTarget, (baseTdee / 10).round() * 10);
  // Workout calories add on top of the non-exercise base. Clamp to a
  // non-negative whole number so a stray negative can't lower the goal.
  final exerciseKcal = math.max(0, input.exerciseKcal.round());
  final calories = baseCalories + exerciseKcal;

  final proteinG = (proteinGPerKg * weightKg).round();
  final fatG = ((fatKcalFraction * calories) / _kcalPerGFat).round();
  final carbsKcal = math.max(
    0,
    calories - proteinG * _kcalPerGProtein - fatG * _kcalPerGFat,
  );
  final carbsG = (carbsKcal / _kcalPerGCarb).round();

  return NutritionTargets(
    calories: calories,
    baseCalories: baseCalories,
    exerciseKcal: exerciseKcal,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );
}
