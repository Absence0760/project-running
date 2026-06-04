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
/// - **TDEE:** BMR x an activity factor (sedentary..very active). A goal delta
///   (-500 lose / 0 maintain / +300 gain kcal) is applied after.
/// - **Macros:** protein at 1.8 g/kg bodyweight (endurance-athlete range
///   1.6-2.0), fat at 30% of calories, carbohydrate filling the remainder.
///   Carbs floor at 0 if protein+fat already exhaust the budget.
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

/// Activity multipliers applied to BMR. Order is the display order in
/// Settings (least -> most active).
const activityLevels = <ActivityLevelOption>[
  ActivityLevelOption('sedentary', 'Sedentary (little exercise)', 1.2),
  ActivityLevelOption('light', 'Light (1-3 days/week)', 1.375),
  ActivityLevelOption('moderate', 'Moderate (3-5 days/week)', 1.55),
  ActivityLevelOption('active', 'Active (6-7 days/week)', 1.725),
  ActivityLevelOption('very_active', 'Very active (training twice a day)', 1.9),
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
  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  const NutritionTargets({
    required this.calories,
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
  const BodyMetricsInput({
    required this.weightKg,
    required this.heightCm,
    required this.ageYears,
    required this.sex,
    required this.activityLevel,
    required this.goal,
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
  final tdee =
      bmr * _factorFor(input.activityLevel) + (goalKcalDelta[input.goal] ?? 0);
  final calories = math.max(minCalorieTarget, (tdee / 10).round() * 10);

  final proteinG = (proteinGPerKg * weightKg).round();
  final fatG = ((fatKcalFraction * calories) / _kcalPerGFat).round();
  final carbsKcal = math.max(
    0,
    calories - proteinG * _kcalPerGProtein - fatG * _kcalPerGFat,
  );
  final carbsG = (carbsKcal / _kcalPerGCarb).round();

  return NutritionTargets(
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );
}
