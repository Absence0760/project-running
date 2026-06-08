/**
 * Nutrition budget — how much of each macro is left (or over) for the day.
 *
 * Pure functions, no Supabase / runes, so this is node:test-runnable and
 * shared by the rings card. Sits on top of `nutrition_totals.ts` (the
 * day's consumed totals) and `nutrition_targets.ts` (the day's goal): it
 * answers the one question the rings alone don't — "how much can I still
 * eat?".
 *
 * The crucial nuance is that overshooting means different things per macro:
 *
 * - **Calories** and **fat** are *ceilings*: going over is a warning (you've
 *   eaten more than the goal). The ring should signal it, not silently sit
 *   full — `ringFraction` clamps to 1, so without this an over day looks
 *   identical to an exactly-on-target day.
 * - **Protein** and **carbs** are *goals to reach*: hitting or exceeding the
 *   target is success (a runner wants to clear their protein floor), not a
 *   warning. Over here is neutral/good and must never render as an alert.
 *
 * Web-first; the mobile twin (`nutrition_totals.dart` + the rings card) does
 * not consume this yet — tracked in docs/product/followups.md.
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
	const remaining = Math.round(target - consumed);
	const over = Math.max(0, Math.round(consumed - target));
	const isCeiling = MACRO_IS_CEILING[kind];
	return {
		remaining,
		over,
		exceeded: isCeiling && consumed > target,
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
