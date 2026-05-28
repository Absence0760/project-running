/// Calorie estimate for a recorded run.
///
/// Persona-hunt Round 3 finding Woman #5. Dart twin of
/// `apps/web/src/lib/calories.ts` — keep both in lockstep. See
/// `docs/decisions.md § 77` for the formula choice + sources.
///
/// Pure functions, no Flutter / Supabase deps.

typedef CalorieGender = String?; // 'male' | 'female' | 'nonbinary' | null

const double kDefaultBodyWeightKg = 70;

const Map<String, double> kActivityKcalPerKgPerKm = {
  'run': 1.0,
  'walk': 0.5,
  'hike': 0.7,
  'cycle': 0.4,
};

// Female-specific calibration. See web `calories.ts` for the full
// rationale comment; keep both helpers in lockstep.
const double _kFemaleCalorieCalibration = 0.95;

double _genderMultiplier(CalorieGender gender) =>
    gender == 'female' ? _kFemaleCalorieCalibration : 1.0;

/// Returns the estimated calorie burn for a run, rounded to the
/// nearest integer. Always non-negative.
///
/// - [distanceM]: total distance in metres.
/// - [weightKg]: body weight in kg; null / zero / negative falls
///   back to [kDefaultBodyWeightKg].
/// - [activityKcalPerKgPerKm]: per-activity coefficient; null /
///   zero falls back to run (1.0).
/// - [gender]: optional. When 'female', the result is reduced by 5%.
int estimateRunCalories({
  required double distanceM,
  double? weightKg,
  double? activityKcalPerKgPerKm,
  CalorieGender gender,
}) {
  final dist = distanceM > 0 ? distanceM : 0.0;
  final distanceKm = dist / 1000;
  final weight = (weightKg != null && weightKg > 0)
      ? weightKg
      : kDefaultBodyWeightKg;
  final coef = (activityKcalPerKgPerKm != null && activityKcalPerKgPerKm > 0)
      ? activityKcalPerKgPerKm
      : kActivityKcalPerKgPerKm['run']!;
  final g = _genderMultiplier(gender);
  return (weight * coef * distanceKm * g).round();
}
