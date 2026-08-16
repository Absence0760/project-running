/**
 * Daily roll-up + budget for the five extended nutrients (`food_log`'s
 * `fiber_g` / `sugar_g` / `sodium_mg` / `saturated_fat_g` / `cholesterol_mg`,
 * issue #492). Until now they were captured per item and surfaced only on the
 * portion preview and `/nutrition/[date]/[slot]`; nothing rolled them up to a
 * day or measured them against anything.
 *
 * The reason a plain sum is not enough — and the whole point of this module —
 * is **coverage**. Both food sources carry these fields unevenly, so a null is
 * the common case, and `sumMacros`' "null counts as 0" rule (right for
 * calories, where a partially-logged item should still contribute) becomes a
 * fail-open claim here: eight logged items of which two report sodium sum to a
 * number that reads as the day's intake and sits comfortably under a ceiling
 * it may in fact have blown past.
 *
 * So a total is accompanied by how many entries actually reported it, and only
 * the claims that survive partial coverage are ever offered:
 *
 * - `exceeded` (a ceiling nutrient past target) and `reached` (a floor
 *   nutrient at/past target) are **monotone** — the reported entries alone
 *   already clear the line, and the unreported ones can only add more. Sound
 *   under partial coverage.
 * - `remaining` ("600 mg left") is a claim about the day's *whole* intake, and
 *   the unreported entries could have consumed all of it. Withheld — null —
 *   whenever coverage is partial.
 *
 * Targets are public reference intakes, not prescriptions, and two of the five
 * deliberately have **none**:
 *
 * - **Fibre** — floor, 14 g per 1000 kcal (IOM/DGA adequate intake). Scaled
 *   off the *base* calorie goal, not the exercise-inflated one: the reference
 *   is an adequacy figure for ordinary intake, and the extra carbohydrate a
 *   long-run day earns is deliberately low-residue. Scaling it by workout
 *   calories would prescribe 50 g+ of fibre on exactly the day a runner wants
 *   least of it.
 * - **Sodium** — ceiling, 2300 mg (FDA daily value) plus a sweat allowance.
 *   The population ceiling is the wrong ceiling for someone who just sweated
 *   out two litres, so it rises with logged exercise on the same "base +
 *   exercise" model as the calorie goal (decisions §134) and the water goal.
 *   The per-minute figure is derived from `hydration.ts`'s own assumption:
 *   480 ml/hr of sweat replacement at a conservative ~700 mg of sodium per
 *   litre is ~5.6 mg/min, rounded to 6. It shares that module's
 *   `MAX_EXERCISE_MINUTES` cap for the same reason — past four hours this is a
 *   race fuel plan (`fuel_plan.ts`), not a daily baseline.
 * - **Saturated fat** — ceiling, 10 % of calories (DGA). A percentage of
 *   energy, so it correctly scales with the *full* dynamic goal.
 * - **Sugar** — no target. The stored field is *total* sugars, including the
 *   fruit and milk sugar in a perfectly good diet, while every published
 *   ceiling (WHO's 10 % of energy) is about *free/added* sugars. Grading total
 *   sugars against a free-sugar limit would flag a bowl of fruit as an
 *   overshoot, so the total is reported and left ungraded.
 * - **Cholesterol** — no target. The 300 mg/day cap was removed from the
 *   Dietary Guidelines in 2015 and no numeric limit replaced it. Reported,
 *   ungraded — inventing a threshold would be worse than showing none.
 *
 * Web-only. Nothing here is required by the `nutrition_targets` /
 * `nutrition_budget` Dart twins, which budget kcal + the three headline macros
 * and are unchanged.
 */

import type { MessageKey } from '../i18n/messages';

import { MAX_EXERCISE_MINUTES } from './hydration';
import type { NutritionTargets } from './nutrition_targets';

export type NutrientKind = 'fiber' | 'sugar' | 'sodium' | 'saturatedFat' | 'cholesterol';

/// Which way overshooting a nutrient reads. `none` = reported but ungraded.
export type NutrientDirection = 'floor' | 'ceiling' | 'none';

export interface ExtendedNutrientRow {
	fiber_g: number | null;
	sugar_g: number | null;
	sodium_mg: number | null;
	saturated_fat_g: number | null;
	cholesterol_mg: number | null;
}

export interface NutrientSpec {
	kind: NutrientKind;
	column: keyof ExtendedNutrientRow;
	direction: NutrientDirection;
	unit: 'g' | 'mg';
	/// i18n key for the nutrient's display name, resolved at the render layer.
	labelKey: MessageKey;
}

/// Display order for the day's nutrient list (the two graded ceilings a runner
/// most needs first, then fibre, then the ungraded pair).
export const EXTENDED_NUTRIENTS: NutrientSpec[] = [
	{ kind: 'sodium', column: 'sodium_mg', direction: 'ceiling', unit: 'mg', labelKey: 'nutrition.sodium' },
	{ kind: 'fiber', column: 'fiber_g', direction: 'floor', unit: 'g', labelKey: 'nutrition.fiber' },
	{ kind: 'saturatedFat', column: 'saturated_fat_g', direction: 'ceiling', unit: 'g', labelKey: 'nutrition.saturatedFat' },
	{ kind: 'sugar', column: 'sugar_g', direction: 'none', unit: 'g', labelKey: 'nutrition.sugar' },
	{ kind: 'cholesterol', column: 'cholesterol_mg', direction: 'none', unit: 'mg', labelKey: 'nutrition.cholesterol' },
];

/// Grams of fibre per 1000 kcal of the base calorie goal.
export const FIBER_G_PER_1000_KCAL = 14;
/// Flat population sodium ceiling before any sweat allowance (mg).
export const SODIUM_BASELINE_MG = 2300;
/// Sodium the ceiling rises by per minute of logged exercise (mg).
export const SODIUM_MG_PER_EXERCISE_MIN = 6;
/// Share of total calories allowed from saturated fat.
export const SATURATED_FAT_KCAL_FRACTION = 0.1;

const KCAL_PER_G_FAT = 9;

export type NutrientTargets = Record<NutrientKind, number | null>;

/// Daily reference intakes for the five extended nutrients. `targets` may be
/// null (no body metrics) — fibre and saturated fat then have no basis to
/// scale from and return null, while sodium still resolves, because its
/// reference is a flat ceiling plus a sweat allowance and needs neither
/// bodyweight nor a calorie goal. That is the same reason `hydrationTargetMl`
/// always answers.
export function extendedNutrientTargets(
	targets: NutritionTargets | null,
	exerciseMinutes: number | null | undefined,
): NutrientTargets {
	const countedMinutes =
		exerciseMinutes != null && exerciseMinutes > 0
			? Math.min(exerciseMinutes, MAX_EXERCISE_MINUTES)
			: 0;
	const sodium = Math.round(SODIUM_BASELINE_MG + countedMinutes * SODIUM_MG_PER_EXERCISE_MIN);
	return {
		sodium,
		fiber:
			targets && targets.baseCalories > 0
				? Math.round((targets.baseCalories / 1000) * FIBER_G_PER_1000_KCAL)
				: null,
		saturatedFat:
			targets && targets.calories > 0
				? Math.round((SATURATED_FAT_KCAL_FRACTION * targets.calories) / KCAL_PER_G_FAT)
				: null,
		sugar: null,
		cholesterol: null,
	};
}

export interface NutrientBudget {
	kind: NutrientKind;
	direction: NutrientDirection;
	unit: 'g' | 'mg';
	labelKey: MessageKey;
	/// Sum over the entries that REPORTED this nutrient. Grams round to 0.1,
	/// milligrams to whole.
	consumed: number;
	target: number | null;
	/// Headroom under a ceiling / shortfall to a floor, never negative. Null
	/// with no target AND null whenever coverage is partial: the unreported
	/// entries could have consumed all of it.
	remaining: number | null;
	/// A ceiling nutrient measurably past its target. Monotone, so it holds
	/// under partial coverage.
	exceeded: boolean;
	/// A floor nutrient at or past its target. Monotone, same as above.
	reached: boolean;
	/// Entries that reported this nutrient, and the day's total entry count.
	reportedEntries: number;
	totalEntries: number;
	/// At least one entry did not report this nutrient, so `consumed` is a
	/// lower bound on the day rather than the day.
	partial: boolean;
}

function roundFor(unit: 'g' | 'mg', value: number): number {
	return unit === 'g' ? Math.round(value * 10) / 10 : Math.round(value);
}

/// One budget per extended nutrient that at least one entry reported, in
/// `EXTENDED_NUTRIENTS` order. A nutrient nothing reported is omitted rather
/// than shown as zero — an empty row is not a measurement, and the caller
/// self-hides the whole section on an empty result (anti-clutter,
/// multi_modal.md).
export function extendedNutrientBudgets(
	rows: ExtendedNutrientRow[],
	targets: NutrientTargets,
): NutrientBudget[] {
	const out: NutrientBudget[] = [];
	for (const spec of EXTENDED_NUTRIENTS) {
		let sum = 0;
		let reported = 0;
		for (const row of rows) {
			const raw = row[spec.column];
			if (raw == null || !Number.isFinite(raw)) continue;
			sum += raw;
			reported += 1;
		}
		if (reported === 0) continue;
		const consumed = roundFor(spec.unit, sum);
		const target = targets[spec.kind];
		const partial = reported < rows.length;
		const hasTarget = target != null && target > 0;
		out.push({
			kind: spec.kind,
			direction: spec.direction,
			unit: spec.unit,
			labelKey: spec.labelKey,
			consumed,
			target: hasTarget ? target : null,
			remaining:
				hasTarget && !partial ? Math.max(0, roundFor(spec.unit, target - consumed)) : null,
			exceeded: hasTarget && spec.direction === 'ceiling' && consumed > target,
			reached: hasTarget && spec.direction === 'floor' && consumed >= target,
			reportedEntries: reported,
			totalEntries: rows.length,
			partial,
		});
	}
	return out;
}
