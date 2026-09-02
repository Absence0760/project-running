// Calorie estimate for a recorded run.
//
// Persona-hunt Round 3 finding Woman #5. Pre-fix, the web run-detail
// page surfaced `kcal = weight_kg × distance_km` (the 1 kcal/kg/km
// running heuristic), and the mobile run-detail page surfaced
// `weight_kg × activity_kcal_per_kg_per_km × distance_km`. Both
// formulas under-account for the standard sport-science observation
// that female runners' absolute energy expenditure at the same MET
// intensity is ~5% lower than male's (the cross-formula calibration
// the persona finding asked us to document + apply).
//
// This module is the single source of truth for the estimate, used
// by both the web run-detail page and the mobile equivalent. TS<->Dart
// parity pair with `apps/mobile_android/lib/calories.dart` (and the
// iOS twin per the one-Dart-codebase rule).
//
// See `docs/architecture/decisions.md § 77` for the full formula choice + sources.

/// Optional gender hint for the calorie estimate. Matches the
/// `gender` column on `user_profiles`.
export type CalorieGender = 'male' | 'female' | 'prefer_not_to_say' | null;

/// Default body weight used when the runner hasn't set
/// `user_settings.prefs.body_weight_kg`. Median for an adult runner;
/// imperfect but produces a believable number so the calorie cell
/// always renders + the grid never has a hole.
export const DEFAULT_BODY_WEIGHT_KG = 70;

/// Per-activity energy cost (kcal per kg per km), mirroring the
/// existing `ActivityType.kcalPerKgPerKm` ladder on mobile. Web's
/// run-detail page previously hardcoded 1.0 (the run value); pulling
/// it through this helper lets a future activity-aware cell adopt the
/// same numbers without forking the formula.
export const ACTIVITY_KCAL_PER_KG_PER_KM: Record<string, number> = {
	run: 1.0,
	walk: 0.5,
	hike: 0.7,
	cycle: 0.4,
	// Running while pushing a stroller — a touch above open running. Before
	// this key existed, stroller runs fell back to walk (0.5) and undercounted
	// calories by ~50% (family-club persona #51).
	stroller: 1.1,
};

/// Female-specific calibration. ~5% reduction in absolute energy
/// expenditure at the same MET intensity, per the cross-formula
/// reconciliation between Daniels (running) + Compendium of Physical
/// Activities (MET-based) + the female-vs-male offsets each surfaces.
/// `male` / `null` / `prefer_not_to_say` use the unmodified curve.
///
/// Why uniform 0.95 rather than per-pace adjustment:
///  - The literature suggests 3-8% depending on speed + slope; a
///    uniform mid-range constant under-prescribes at extreme paces
///    but is the right shape for the data + complexity budget.
///  - Conservative direction (lower) is the right error mode — the
///    1 kcal/kg/km heuristic already over-estimates for short slow
///    efforts where the user typically wants a credible-ish number,
///    not a target.
const FEMALE_CALORIE_CALIBRATION = 0.95;

function genderMultiplier(gender: CalorieGender | undefined): number {
	return gender === 'female' ? FEMALE_CALORIE_CALIBRATION : 1.0;
}

export interface EstimateRunCaloriesInput {
	/// Total distance in metres.
	distanceM: number;
	/// Body weight in kg. Null / undefined → DEFAULT_BODY_WEIGHT_KG.
	weightKg?: number | null;
	/// Activity-specific kcal/kg/km coefficient. Null / undefined →
	/// run (1.0). Pass `ACTIVITY_KCAL_PER_KG_PER_KM[activityType]`
	/// at the call site.
	activityKcalPerKgPerKm?: number | null;
	/// Optional gender from `user_profiles.gender`. When `female` the
	/// estimate is reduced by 5%. See FEMALE_CALORIE_CALIBRATION above.
	gender?: CalorieGender;
}

/// Ceiling on an estimate either platform can carry the same way. Past 2^53-1
/// a JS number stops being an exact integer while Dart's `int` saturates at
/// 2^63-1, so the same absurd input yields two different figures -- and an
/// estimate that large is not one. Reported as no estimate, the same answer a
/// negative distance gets.
export const MAX_ESTIMABLE_KCAL = Number.MAX_SAFE_INTEGER;

/// Returns the estimated calorie burn for a run, rounded to the
/// nearest integer. Always non-negative.
export function estimateRunCalories(input: EstimateRunCaloriesInput): number {
	const distanceKm = Math.max(0, input.distanceM) / 1000;
	// Weight and coefficient are checked for FINITENESS, not just for sign. A
	// NaN fails the `> 0` test the way a zero does and so already fell back to
	// the default, but an Infinity passed it -- returning Infinity here while
	// the Dart twin threw, because `.round()` refuses a non-finite double, and
	// this is read from a getter during a widget build. An unusable weight is
	// no more usable than an absent one, so both take the documented default.
	const weight =
		input.weightKg != null && Number.isFinite(input.weightKg) && input.weightKg > 0
			? input.weightKg
			: DEFAULT_BODY_WEIGHT_KG;
	const activityCoef =
		input.activityKcalPerKgPerKm != null &&
		Number.isFinite(input.activityKcalPerKgPerKm) &&
		input.activityKcalPerKgPerKm > 0
			? input.activityKcalPerKgPerKm
			: ACTIVITY_KCAL_PER_KG_PER_KM.run;
	const g = genderMultiplier(input.gender);
	// One comparison does both jobs, which is why there is no separate
	// finiteness test here: a NaN and a +Infinity each FAIL `<=`, and the
	// remaining inputs cannot produce a negative product. That covers the
	// DISTANCE too -- a NaN survives `Math.max` where the Dart twin's `> 0`
	// test sends it to zero, but either way the product is unusable, so
	// grading the product is what makes the two agree rather than a per-input
	// check no input could reach past this one.
	const kcal = weight * activityCoef * distanceKm * g;
	return kcal <= MAX_ESTIMABLE_KCAL ? Math.round(kcal) : 0;
}
