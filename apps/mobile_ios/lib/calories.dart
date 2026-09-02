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

/// Ceiling on an estimate either platform can carry the same way. Past 2^53-1
/// a JS number stops being an exact integer while Dart's `int` saturates at
/// 2^63-1 — so `(7e19).round()` is 9223372036854775807 here and 7e19 on web
/// for the same input. An estimate that large is not one. Reported as no
/// estimate, the same answer a negative distance gets.
const int kMaxEstimableKcal = 9007199254740991;

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
  // Weight and coefficient are checked for FINITENESS, not just for sign. A
  // NaN fails the `> 0` test the way a zero does and so already fell back to
  // the default, but an Infinity passed it — and `.round()` THROWS on a
  // non-finite double, inside a getter read during the run-detail widget
  // build, where the web twin merely returned Infinity. An unusable weight is
  // no more usable than an absent one, so both take the documented default.
  final weight = (weightKg != null && weightKg.isFinite && weightKg > 0)
      ? weightKg
      : kDefaultBodyWeightKg;
  final coef = (activityKcalPerKgPerKm != null &&
          activityKcalPerKgPerKm.isFinite &&
          activityKcalPerKgPerKm > 0)
      ? activityKcalPerKgPerKm
      : kActivityKcalPerKgPerKm['run']!;
  final g = _genderMultiplier(gender);
  // One comparison does both jobs, which is why there is no separate
  // finiteness test here: a NaN and a +Infinity each FAIL `<=`, and the
  // remaining inputs cannot produce a negative product. That covers the
  // DISTANCE too — a NaN goes to zero here where the web twin's `Math.max`
  // keeps it, but either way the product is unusable, so grading the product
  // is what makes the two agree rather than a per-input check no input could
  // reach past this one.
  final kcal = weight * coef * distanceKm * g;
  return kcal <= kMaxEstimableKcal ? kcal.round() : 0;
}
