/**
 * Hydration target — a daily water goal the water tracker can count toward,
 * instead of an open-ended cup counter with no finish line.
 *
 * Heuristics, deliberately simple + conservative — a default nudge, not a
 * clinical prescription, in the same spirit as `exercise_calories.ts`:
 *
 * - **Baseline:** ~35 ml per kg of bodyweight per day (the common 30–40
 *   ml/kg range). Falls back to a flat 2 L when bodyweight is unknown, so a
 *   target always exists — the water card is a simple tracker that should
 *   work for everyone, unlike the macro rings which hide without metrics.
 * - **Exercise add:** ~480 ml per hour of logged activity (8 ml/min) for
 *   sweat replacement, so a hard training day raises the goal — the same
 *   "base + exercise" idea the calorie goal uses (decisions §134).
 *
 * The target rounds to a tidy 50 ml. Water is a *floor* to reach (over is
 * fine), so the budget only ever reports remaining-to-goal and a `reached`
 * flag, never an over-budget warning.
 *
 * Web-only for now; the mobile water tracker (same per-day localStorage
 * counter) does not have a target yet — mirror tracked in followups.md.
 */

/// Baseline daily water, ml per kg of bodyweight.
export const BASELINE_ML_PER_KG = 35;
/// Flat baseline when bodyweight is unknown (~2 L).
export const DEFAULT_BASELINE_ML = 2000;
/// Extra water per minute of logged exercise (~480 ml/hr sweat replacement).
export const EXERCISE_ML_PER_MIN = 8;
/// Targets round to this for a tidy number.
export const TARGET_ROUND_ML = 50;

/// Daily water goal in ml from bodyweight + today's exercise minutes. Always
/// returns a positive target (the flat baseline covers missing bodyweight).
export function hydrationTargetMl(
	weightKg: number | null | undefined,
	exerciseMinutes: number | null | undefined,
): number {
	const baseline =
		weightKg != null && weightKg > 0 ? weightKg * BASELINE_ML_PER_KG : DEFAULT_BASELINE_ML;
	const exercise =
		exerciseMinutes != null && exerciseMinutes > 0 ? exerciseMinutes * EXERCISE_ML_PER_MIN : 0;
	return Math.round((baseline + exercise) / TARGET_ROUND_ML) * TARGET_ROUND_ML;
}

export interface HydrationBudget {
	targetMl: number;
	consumedMl: number;
	/// Water still to drink, never negative (0 once the goal is met).
	remainingMl: number;
	/// True once consumed reaches or clears the target — a win, not a warning.
	reached: boolean;
	/// Progress toward the goal, clamped to [0, 1] for the fill bar.
	fraction: number;
}

/// Budget for the day's water given consumed + target ml.
export function hydrationBudget(consumedMl: number, targetMl: number): HydrationBudget {
	const consumed = Math.max(0, Math.round(consumedMl));
	const target = Math.max(0, Math.round(targetMl));
	const remainingMl = Math.max(0, target - consumed);
	const reached = target > 0 && consumed >= target;
	const fraction = target > 0 ? Math.max(0, Math.min(1, consumed / target)) : 0;
	return { targetMl: target, consumedMl: consumed, remainingMl, reached, fraction };
}
