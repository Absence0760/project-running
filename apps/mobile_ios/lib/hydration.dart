/// Hydration target — a daily water goal the water tracker counts toward.
///
/// Dart twin of `apps/web/src/lib/nutrition/hydration.ts` — keep the
/// algorithm, constants, edge cases, and test counts in lockstep.
///
/// Heuristic constants (~35 ml/kg/day, +8 ml/min of exercise) are a
/// conservative nudge, in the spirit of `exercise_calories.dart`. The one
/// non-obvious choice: unlike the macro rings, this always returns a target
/// (flat 2 L when bodyweight is unknown), because a water tracker should work
/// for everyone. Water is a floor to reach, so the budget reports only
/// remaining-to-goal + a `reached` flag, never an over-budget warning.
///
/// Pure functions, no Flutter / Supabase deps.
library;

/// Baseline daily water, ml per kg of bodyweight.
const baselineMlPerKg = 35;

/// Flat baseline when bodyweight is unknown (~2 L).
const defaultBaselineMl = 2000;

/// Extra water per minute of logged exercise (~480 ml/hr sweat replacement).
const exerciseMlPerMin = 8;

/// Targets round to this for a tidy number.
const targetRoundMl = 50;

/// Daily water goal in ml from bodyweight + today's exercise minutes. Always
/// returns a positive target (the flat baseline covers missing bodyweight).
int hydrationTargetMl(num? weightKg, num? exerciseMinutes) {
  final baseline =
      weightKg != null && weightKg > 0 ? weightKg * baselineMlPerKg : defaultBaselineMl;
  final exercise =
      exerciseMinutes != null && exerciseMinutes > 0 ? exerciseMinutes * exerciseMlPerMin : 0;
  return ((baseline + exercise) / targetRoundMl).round() * targetRoundMl;
}

class HydrationBudget {
  final int targetMl;
  final int consumedMl;

  /// Water still to drink, never negative (0 once the goal is met).
  final int remainingMl;

  /// True once consumed reaches or clears the target — a win, not a warning.
  final bool reached;

  /// Progress toward the goal, clamped to [0, 1] for the fill bar.
  final double fraction;

  const HydrationBudget({
    required this.targetMl,
    required this.consumedMl,
    required this.remainingMl,
    required this.reached,
    required this.fraction,
  });
}

/// Budget for the day's water given consumed + target ml.
HydrationBudget hydrationBudget(num consumedMl, num targetMl) {
  final consumed = consumedMl.round() > 0 ? consumedMl.round() : 0;
  final target = targetMl.round() > 0 ? targetMl.round() : 0;
  final remainingMl = (target - consumed) > 0 ? target - consumed : 0;
  final reached = target > 0 && consumed >= target;
  final fraction = target > 0 ? (consumed / target).clamp(0.0, 1.0).toDouble() : 0.0;
  return HydrationBudget(
    targetMl: target,
    consumedMl: consumed,
    remainingMl: remainingMl,
    reached: reached,
    fraction: fraction,
  );
}
