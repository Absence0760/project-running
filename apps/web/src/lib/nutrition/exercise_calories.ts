/**
 * Exercise-calorie estimator — energy burned by a run or a gym session, for
 * the dynamic-TDEE "base + exercise" nutrition goal (decisions §63 amendment,
 * multi_modal.md § Nutrition).
 *
 * Pure functions, no Supabase / auth. TS↔Dart parity pair with
 * `apps/mobile_android/lib/exercise_calories.dart` — keep the algorithm,
 * constants, edge cases, and test counts in lockstep.
 *
 * Heuristics, deliberately simple + conservative — a default that nudges the
 * day's goal, not a lab measurement:
 *
 * - **Running:** gross energy ≈ 1.036 kcal per kg of bodyweight per km — the
 *   widely-cited, roughly pace-independent flat cost of running. Needs
 *   distance + bodyweight; returns 0 when either is missing.
 * - **Gym:** MET model. Resistance training ≈ 5.0 MET ("vigorous effort",
 *   Compendium of Physical Activities). kcal = MET · kg · hours. Needs
 *   session duration + bodyweight.
 *
 * Gross (not net of resting metabolism) by design: the daily base TDEE is a
 * conservative *non-exercise* baseline, so adding gross workout energy keeps a
 * hard training day from being under-fuelled. All functions return whole kcal
 * (or an unrounded per-activity figure that the day aggregate rounds once).
 */

/// Gross running energy cost, kcal per kg of bodyweight per km.
export const KCAL_PER_KG_PER_KM = 1.036;
/// MET for resistance training (Compendium "vigorous effort").
export const GYM_MET = 5.0;

/// Calories burned by one run. 0 when distance or bodyweight is missing /
/// non-physical (can't estimate without both).
export function runCalories(
	distanceM: number | null | undefined,
	weightKg: number | null | undefined,
): number {
	if (weightKg == null || weightKg <= 0) return 0;
	if (distanceM == null || distanceM <= 0) return 0;
	return KCAL_PER_KG_PER_KM * weightKg * (distanceM / 1000);
}

/// Calories burned by one gym session. 0 when duration or bodyweight is
/// missing / non-physical.
export function gymCalories(
	durationS: number | null | undefined,
	weightKg: number | null | undefined,
): number {
	if (weightKg == null || weightKg <= 0) return 0;
	if (durationS == null || durationS <= 0) return 0;
	return GYM_MET * weightKg * (durationS / 3600);
}

export interface DayActivityInput {
	runs: { distanceM: number | null }[];
	gymSessions: { durationS: number | null }[];
	weightKg: number | null;
}

/// Total whole-kcal burned across a day's runs + gym sessions. Returns 0 when
/// bodyweight is unknown (can't estimate) or nothing qualifies. Rounded once,
/// at the end, so the displayed total matches the sum of its parts.
export function exerciseCaloriesForDay(input: DayActivityInput): number {
	const { weightKg } = input;
	if (weightKg == null || weightKg <= 0) return 0;
	let total = 0;
	for (const r of input.runs) total += runCalories(r.distanceM, weightKg);
	for (const g of input.gymSessions) total += gymCalories(g.durationS, weightKg);
	return Math.round(total);
}
