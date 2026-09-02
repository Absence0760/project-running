/// Calorie estimate for a recorded run.
///
/// Persona-hunt Round 3 finding Woman #5. Dart twin of
/// `apps/web/src/lib/runs/calories.ts` — keep both in lockstep. See
/// `docs/architecture/decisions.md § 77` for the formula choice + sources.
///
/// Pure functions, no Flutter / Supabase deps.

typedef CalorieGender = String?; // 'male' | 'female' | 'prefer_not_to_say' | null

const double kDefaultBodyWeightKg = 70;

const Map<String, double> kActivityKcalPerKgPerKm = {
  'run': 1.0,
  'walk': 0.5,
  'hike': 0.7,
  'cycle': 0.4,
  // Running while pushing a stroller — a touch above open running. Before
  // this key, stroller runs fell back to walk (0.5), ~50% low (#51).
  'stroller': 1.1,
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
  // Every input is checked for finiteness, not just for sign. `.round()`
  // THROWS on a non-finite double, and this getter is read during a widget
  // build, so an Infinity distance or weight took the run-detail screen down
  // where the web twin rendered `NaN kcal` for the same NaN. One formula
  // cannot have two answers, and neither of those two was the right one: an
  // unusable measurement contributes nothing, and an unusable weight or
  // coefficient falls back to the documented default exactly as an absent one
  // does.
  final dist = distanceM.isFinite && distanceM > 0 ? distanceM : 0.0;
  final distanceKm = dist / 1000;
  final weight = (weightKg != null && weightKg.isFinite && weightKg > 0)
      ? weightKg
      : kDefaultBodyWeightKg;
  final coef = (activityKcalPerKgPerKm != null &&
          activityKcalPerKgPerKm.isFinite &&
          activityKcalPerKgPerKm > 0)
      ? activityKcalPerKgPerKm
      : kActivityKcalPerKgPerKm['run']!;
  final g = _genderMultiplier(gender);
  // Finite inputs can still multiply out past the double range; the estimate
  // is a display figure, so an unrepresentable one is no estimate at all.
  final kcal = weight * coef * distanceKm * g;
  return kcal.isFinite ? kcal.round() : 0;
}
