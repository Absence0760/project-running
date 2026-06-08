/**
 * Nutrition budget — how much of each macro is left (or over) for the day.
 *
 * Overshooting means different things per macro, which is why the budget is
 * direction-aware rather than a single remaining number:
 *
 * - **Calories** and **fat** are *ceilings*: going over is a warning. The
 *   ring must signal it, since `ringFraction` clamps to 1 — without this an
 *   over day looks identical to an exactly-on-target day.
 * - **Protein** and **carbs** are *goals to reach*: hitting or exceeding the
 *   target is success (clearing a protein floor), not a warning, and must
 *   never render as an alert.
 *
 * Web-only for now; the mobile mirror is tracked in docs/product/followups.md.
 */

import type { FoodMacros } from './food_search';
import type { NutritionTargets } from './nutrition_targets';

export type MacroKind = 'calories' | 'protein' | 'carbs' | 'fat';

/// Whether overshooting a macro is a warning. Calories + fat are ceilings
/// (over = warning); protein + carbs are goals to reach (over = fine).
export const MACRO_IS_CEILING: Record<MacroKind, boolean> = {
	calories: true,
	protein: false,
	carbs: false,
	fat: true,
};

export interface MacroBudget {
	/// Signed headroom: target − consumed. Positive = still to eat, negative
	/// = over. Null when there's no positive target (hide the comparison).
	remaining: number | null;
	/// How far over target, never negative; 0 when under target or untargeted.
	over: number;
	/// True only for a *ceiling* macro eaten past its target — the one case
	/// the UI should flag. False for goal macros (protein/carbs) even when
	/// they exceed target, and whenever there's no target.
	exceeded: boolean;
	/// True for a *goal* macro that has reached or cleared its target — the
	/// positive counterpart of `exceeded`. False for ceiling macros.
	reached: boolean;
}

/// Budget for one macro given its consumed amount, target, and kind.
export function macroBudget(
	consumed: number,
	target: number | null | undefined,
	kind: MacroKind,
): MacroBudget {
	if (target == null || target <= 0) {
		return { remaining: null, over: 0, exceeded: false, reached: false };
	}
	const remaining = Math.round(target - consumed) || 0; // normalise -0 → 0
	const over = Math.max(0, Math.round(consumed - target));
	const isCeiling = MACRO_IS_CEILING[kind];
	// `exceeded` keys off the rounded `over`, not raw `consumed > target`, so a
	// sub-0.5 overage that rounds to 0 never renders the broken "0 over" chip.
	return {
		remaining,
		over,
		exceeded: isCeiling && over > 0,
		reached: !isCeiling && consumed >= target,
	};
}

export interface DayBudget {
	calories: MacroBudget;
	protein: MacroBudget;
	carbs: MacroBudget;
	fat: MacroBudget;
}

/// Budget for all four macros of a day, or null when there's no target set
/// (so the caller hides the whole summary rather than render four nulls).
export function computeDayBudget(
	consumed: FoodMacros,
	targets: NutritionTargets | null,
): DayBudget | null {
	if (!targets) return null;
	return {
		calories: macroBudget(consumed.calories, targets.calories, 'calories'),
		protein: macroBudget(consumed.proteinG, targets.proteinG, 'protein'),
		carbs: macroBudget(consumed.carbsG, targets.carbsG, 'carbs'),
		fat: macroBudget(consumed.fatG, targets.fatG, 'fat'),
	};
}
