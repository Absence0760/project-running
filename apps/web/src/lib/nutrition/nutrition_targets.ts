/**
 * Nutrition targets — daily calorie + macro goals from body metrics.
 *
 * Pure functions, no Supabase / auth. TS↔Dart parity pair with
 * `apps/mobile_android/lib/nutrition_targets.dart` — keep the algorithm,
 * constants, edge cases, and test counts in lockstep.
 *
 * The numbers are well-known sports-nutrition heuristics, not proprietary
 * research, and are deliberately conservative — a default the user can
 * override in Settings, not a prescription:
 *
 * - **BMR (Mifflin-St Jeor):** the modern standard resting-metabolic-rate
 *   estimate. `10·kg + 6.25·cm − 5·age + sexOffset`, where the sex offset
 *   is +5 (male) / −161 (female) / −78 (the male/female average) when sex
 *   is non-binary, withheld, or unknown — so a target still computes
 *   without forcing a binary answer.
 * - **TDEE:** BMR × an activity factor (sedentary…very active). A goal
 *   delta (−500 lose / 0 maintain / +300 gain kcal) is applied after.
 * - **Macros:** protein at 1.8 g/kg bodyweight (endurance-athlete range
 *   1.6–2.0), fat at 30% of calories, carbohydrate filling the remainder —
 *   the running-friendly default. Carbs floor at 0 if protein+fat already
 *   exhaust the budget.
 *
 * `computeNutritionTargets` returns **null** when any required metric is
 * missing or non-physical, so the UI hides the rings rather than render a
 * zeroed/garbage target (anti-clutter checklist, multi_modal.md).
 */

export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'active' | 'very_active';
export type WeightGoal = 'lose' | 'maintain' | 'gain';

export interface ActivityLevelOption {
	key: ActivityLevel;
	label: string;
	factor: number;
}

/// Activity multipliers applied to BMR. Order is the display order in
/// Settings (least → most active).
export const ACTIVITY_LEVELS: ActivityLevelOption[] = [
	{ key: 'sedentary', label: 'Sedentary (little exercise)', factor: 1.2 },
	{ key: 'light', label: 'Light (1–3 days/week)', factor: 1.375 },
	{ key: 'moderate', label: 'Moderate (3–5 days/week)', factor: 1.55 },
	{ key: 'active', label: 'Active (6–7 days/week)', factor: 1.725 },
	{ key: 'very_active', label: 'Very active (training twice a day)', factor: 1.9 },
];

/// Daily calorie delta applied after TDEE for the user's weight goal.
export const GOAL_KCAL_DELTA: Record<WeightGoal, number> = {
	lose: -500,
	maintain: 0,
	gain: 300,
};

/// Grams of protein per kg of bodyweight (endurance-athlete default).
export const PROTEIN_G_PER_KG = 1.8;
/// Share of total calories from fat.
export const FAT_KCAL_FRACTION = 0.3;
/// Lowest calorie target we will ever recommend — a safety floor, not a
/// medical clamp. Below this the default is suspect; the user can still
/// override.
export const MIN_CALORIE_TARGET = 1200;

const KCAL_PER_G_PROTEIN = 4;
const KCAL_PER_G_CARB = 4;
const KCAL_PER_G_FAT = 9;

export interface NutritionTargets {
	calories: number;
	proteinG: number;
	carbsG: number;
	fatG: number;
}

export interface BodyMetricsInput {
	weightKg: number | null;
	heightCm: number | null;
	ageYears: number | null;
	sex: string | null;
	activityLevel: ActivityLevel;
	goal: WeightGoal;
}

function sexOffset(sex: string | null | undefined): number {
	if (sex === 'male') return 5;
	if (sex === 'female') return -161;
	return -78;
}

function factorFor(level: ActivityLevel): number {
	const opt = ACTIVITY_LEVELS.find((a) => a.key === level);
	return opt ? opt.factor : 1.55;
}

/// Mifflin-St Jeor resting metabolic rate (kcal/day).
export function mifflinStJeorBmr(
	weightKg: number,
	heightCm: number,
	ageYears: number,
	sex: string | null,
): number {
	return 10 * weightKg + 6.25 * heightCm - 5 * ageYears + sexOffset(sex);
}

/// Whole-year age from an ISO `YYYY-MM-DD` date of birth, evaluated at
/// `nowMs`. Returns null on a missing / malformed date or an out-of-range
/// result. Parsed by calendar components (no timezone dependence) so the
/// Dart twin matches exactly.
export function ageFromDob(dobIso: string | null | undefined, nowMs: number): number | null {
	if (!dobIso) return null;
	const parts = dobIso.slice(0, 10).split('-');
	if (parts.length < 3) return null;
	const by = Number(parts[0]);
	const bm = Number(parts[1]);
	const bd = Number(parts[2]);
	if (!by || !bm || !bd) return null;
	const now = new Date(nowMs);
	const ny = now.getUTCFullYear();
	const nm = now.getUTCMonth() + 1;
	const nd = now.getUTCDate();
	let age = ny - by;
	if (nm < bm || (nm === bm && nd < bd)) age -= 1;
	if (age < 0 || age > 120) return null;
	return age;
}

/// Daily calorie + macro targets, or null when a required metric is
/// missing or non-physical (so the caller can hide the surface).
export function computeNutritionTargets(input: BodyMetricsInput): NutritionTargets | null {
	const { weightKg, heightCm, ageYears, sex, activityLevel, goal } = input;
	if (weightKg == null || heightCm == null || ageYears == null) return null;
	if (weightKg <= 0 || heightCm <= 0 || ageYears <= 0) return null;
	if (weightKg > 500 || heightCm > 300 || ageYears > 120) return null;

	const bmr = mifflinStJeorBmr(weightKg, heightCm, ageYears, sex);
	const tdee = bmr * factorFor(activityLevel) + GOAL_KCAL_DELTA[goal];
	const calories = Math.max(MIN_CALORIE_TARGET, Math.round(tdee / 10) * 10);

	const proteinG = Math.round(PROTEIN_G_PER_KG * weightKg);
	const fatG = Math.round((FAT_KCAL_FRACTION * calories) / KCAL_PER_G_FAT);
	const carbsKcal = Math.max(
		0,
		calories - proteinG * KCAL_PER_G_PROTEIN - fatG * KCAL_PER_G_FAT,
	);
	const carbsG = Math.round(carbsKcal / KCAL_PER_G_CARB);

	return { calories, proteinG, carbsG, fatG };
}
