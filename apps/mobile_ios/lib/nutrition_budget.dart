/// Nutrition budget — how much of each macro is left (or over) for the day.
///
/// Dart twin of `apps/web/src/lib/nutrition/nutrition_budget.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// Overshooting means different things per macro, which is why the budget is
/// direction-aware rather than a single remaining number:
///
/// - **Calories** and **fat** are *ceilings*: going over is a warning. The
///   ring must signal it, since a ring fraction clamps to 1 — without this an
///   over day looks identical to an exactly-on-target day.
/// - **Protein** and **carbs** are *goals to reach*: hitting or exceeding the
///   target is success (clearing a protein floor), not a warning, and must
///   never render as an alert.
///
/// Pure functions, no Flutter / Supabase deps.
library;

import 'food_search.dart';
import 'nutrition_targets.dart';

enum MacroKind { calories, protein, carbs, fat }

/// Rounds half toward positive infinity, matching JS `Math.round` — so the
/// budget agrees with the canonical web twin on negative .5 ties
/// (`Math.round(-0.5) == 0`, where Dart's `.round()` gives -1).
int _roundHalfUp(num value) => (value + 0.5).floor();

/// Whether overshooting a macro is a warning. Calories + fat are ceilings
/// (over = warning); protein + carbs are goals to reach (over = fine).
const macroIsCeiling = <MacroKind, bool>{
  MacroKind.calories: true,
  MacroKind.protein: false,
  MacroKind.carbs: false,
  MacroKind.fat: true,
};

class MacroBudget {
  /// Signed headroom: target − consumed. Positive = still to eat, negative =
  /// over. Null when there's no positive target (hide the comparison).
  final int? remaining;

  /// How far over target, never negative; 0 when under target or untargeted.
  final int over;

  /// True only for a *ceiling* macro eaten past its target — the one case the
  /// UI should flag. False for goal macros (protein/carbs) even when they
  /// exceed target, and whenever there's no target.
  final bool exceeded;

  /// True for a *goal* macro that has reached or cleared its target — the
  /// positive counterpart of [exceeded]. False for ceiling macros.
  final bool reached;

  const MacroBudget({
    required this.remaining,
    required this.over,
    required this.exceeded,
    required this.reached,
  });
}

/// Budget for one macro given its consumed amount, target, and kind.
MacroBudget macroBudget(num consumed, num? target, MacroKind kind) {
  if (target == null || target <= 0) {
    return const MacroBudget(remaining: null, over: 0, exceeded: false, reached: false);
  }
  final remaining = _roundHalfUp(target - consumed);
  final over = _roundHalfUp(consumed - target);
  final isCeiling = macroIsCeiling[kind]!;
  // `exceeded` keys off the rounded `over`, not raw consumed > target, so a
  // sub-0.5 overage that rounds to 0 never renders the broken "0 over" chip.
  final overClamped = over > 0 ? over : 0;
  return MacroBudget(
    remaining: remaining,
    over: overClamped,
    exceeded: isCeiling && overClamped > 0,
    reached: !isCeiling && consumed >= target,
  );
}

class DayBudget {
  final MacroBudget calories;
  final MacroBudget protein;
  final MacroBudget carbs;
  final MacroBudget fat;
  const DayBudget({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// Budget for all four macros of a day, or null when there's no target set (so
/// the caller hides the whole summary rather than render four nulls).
DayBudget? computeDayBudget(FoodMacros consumed, NutritionTargets? targets) {
  if (targets == null) return null;
  return DayBudget(
    calories: macroBudget(consumed.calories, targets.calories, MacroKind.calories),
    protein: macroBudget(consumed.proteinG, targets.proteinG, MacroKind.protein),
    carbs: macroBudget(consumed.carbsG, targets.carbsG, MacroKind.carbs),
    fat: macroBudget(consumed.fatG, targets.fatG, MacroKind.fat),
  );
}
