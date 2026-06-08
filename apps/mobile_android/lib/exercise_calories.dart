/// Exercise-calorie estimator — energy burned by a run or a gym session, for
/// the dynamic-TDEE "base + exercise" nutrition goal (decisions §63 amendment,
/// multi_modal.md § Nutrition).
///
/// Dart twin of `apps/web/src/lib/nutrition/exercise_calories.ts` — keep the
/// algorithm, constants, edge cases, and test counts in lockstep.
///
/// Heuristics, deliberately simple + conservative — a default that nudges the
/// day's goal, not a lab measurement:
///
/// - **Running:** gross energy ~= 1.036 kcal per kg of bodyweight per km — the
///   widely-cited, roughly pace-independent flat cost of running. Needs
///   distance + bodyweight; returns 0 when either is missing.
/// - **Gym:** MET model. Resistance training ~= 5.0 MET ("vigorous effort",
///   Compendium of Physical Activities). kcal = MET * kg * hours. Needs
///   session duration + bodyweight.
///
/// Gross (not net of resting metabolism) by design: the daily base TDEE is a
/// conservative non-exercise baseline, so adding gross workout energy keeps a
/// hard training day from being under-fuelled. All functions return whole kcal
/// (or an unrounded per-activity figure that the day aggregate rounds once).
library;

/// Gross running energy cost, kcal per kg of bodyweight per km.
const double kcalPerKgPerKm = 1.036;

/// MET for resistance training (Compendium "vigorous effort").
const double gymMet = 5.0;

/// Calories burned by one run. 0 when distance or bodyweight is missing /
/// non-physical (can't estimate without both).
double runCalories(double? distanceM, double? weightKg) {
  if (weightKg == null || weightKg <= 0) return 0;
  if (distanceM == null || distanceM <= 0) return 0;
  return kcalPerKgPerKm * weightKg * (distanceM / 1000);
}

/// Calories burned by one gym session. 0 when duration or bodyweight is
/// missing / non-physical.
double gymCalories(double? durationS, double? weightKg) {
  if (weightKg == null || weightKg <= 0) return 0;
  if (durationS == null || durationS <= 0) return 0;
  return gymMet * weightKg * (durationS / 3600);
}

/// One run's distance in metres (null when unknown).
class RunForCalories {
  final double? distanceM;
  const RunForCalories(this.distanceM);
}

/// One gym session's duration in seconds (null when unknown).
class GymSessionForCalories {
  final double? durationS;
  const GymSessionForCalories(this.durationS);
}

/// Total whole-kcal burned across a day's runs + gym sessions. Returns 0 when
/// bodyweight is unknown (can't estimate) or nothing qualifies. Rounded once,
/// at the end, so the displayed total matches the sum of its parts.
int exerciseCaloriesForDay({
  required List<RunForCalories> runs,
  required List<GymSessionForCalories> gymSessions,
  required double? weightKg,
}) {
  if (weightKg == null || weightKg <= 0) return 0;
  double total = 0;
  for (final r in runs) {
    total += runCalories(r.distanceM, weightKg);
  }
  for (final g in gymSessions) {
    total += gymCalories(g.durationS, weightKg);
  }
  return total.round();
}
