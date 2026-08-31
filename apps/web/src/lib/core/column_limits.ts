/**
 * The bound a client puts on an input, for a column the database also bounds.
 *
 * `text_limits.ts` is the same idea one field at a time: a composer capped
 * ABOVE its column's CHECK hands the user a postgres 23514 they cannot act on.
 * This module widens that to the whole class — a numeric range as well as a
 * character cap — and to the caps a client applies that are deliberately
 * NARROWER than the column allows, which is the other half of the same
 * contract: it is legal, but only if it is written down once.
 *
 * Every key is `<table>.<column>`, which is also the locator: the guard in
 * `scripts/check_shared_constants.mjs` resolves that column's CHECK (and its
 * `numeric(p,s)` precision) by replaying every migration and proves this bound
 * sits INSIDE it, so nothing here is a transcription of a number the database
 * owns. decisions § 792.
 *
 * A value bound is inclusive at both ends and stated in the column's own
 * CANONICAL unit — kilograms for a weight, centimetres for a height. A field
 * that takes input in the reader's unit converts the bound for display; see
 * `format/weight.ts`'s `weightBoundsIn`.
 *
 * Mirrored in `apps/mobile_android/lib/column_limits.dart`.
 */

export type ColumnLimit =
	| { readonly kind: 'value'; readonly min: number; readonly max: number }
	| { readonly kind: 'length'; readonly max: number };

export const COLUMN_LIMITS = {
	// 20 kg is a plausible-human floor rather than the column's `> 0`: a body
	// weight is the input to a BMR, and a typo two orders of magnitude out
	// produces a calorie target instead of an error. 250 is the same judgement
	// at the other end, well inside the column's 500.
	'body_metrics.weight_kg': { kind: 'value', min: 20, max: 250 },
	// 50 cm is below every human who can hold a phone, and catches a height
	// typed in feet. The maximum is EQUAL to the column's own 300 — there is no
	// height between them to be stricter about.
	'user_profiles.height_cm': { kind: 'value', min: 50, max: 300 },
	// The race-director weigh-in, where the column's own 20..400 is already the
	// right range — a runner is weighed against their own start baseline, so
	// nothing narrower is defensible.
	'checkpoint_crossings.body_weight_kg': { kind: 'value', min: 20, max: 400 },
	// The column's floor is 1; it has no ceiling, but `numeric(5,1)` does, and
	// a recipe divided into 9,999 servings is a mistyped 9.
	'recipes.servings': { kind: 'value', min: 1, max: 99 },
	// Deliberately far below the column's 4096: a club post is a notice board,
	// not an essay. Four surfaces write this column and all four said 1200.
	'club_posts.body': { kind: 'length', max: 1200 },
	// Below the column's 2000, for the same reason.
	'events.description': { kind: 'length', max: 1000 },
	// Below the column's 120 — a plan name is a header, and 80 is what both
	// plan editors and the create wizard already offered.
	'training_plans.name': { kind: 'length', max: 80 },
	// EQUAL to the column's 32. A parkrun athlete id is `A` + digits and never
	// approaches either number, so there is no product reason to be stricter —
	// and being stricter is what silently truncated an id on the phone while
	// the same id typed fine on the web (decisions § 792).
	'user_profiles.parkrun_number': { kind: 'length', max: 32 }
} as const satisfies Record<string, ColumnLimit>;

export type ColumnLimitKey = keyof typeof COLUMN_LIMITS;

/**
 * What the COLUMN accepts, which is a different question from what a client
 * may send.
 *
 * `COLUMN_LIMITS` bounds an INPUT: it is the narrowest thing a composer should
 * offer, and being conservative there costs nothing. This map is the opposite
 * direction — the ceiling a defensive filter over a value read BACK out of the
 * database must use, so that a row the column legitimately holds is not
 * discarded as garbage. `nutrition_targets` is the case: it refuses a stored
 * profile whose weight or height is non-physical and returns null, which hides
 * the calorie rings. Written against the client input bound it would hide them
 * for a runner the body-metrics screen never let type that weight in the first
 * place; written as a literal it would go on hiding them after a CHECK was
 * widened, silently, on both platforms, with every mirror test passing.
 *
 * So the number is the column's, and the guard in
 * `scripts/check_shared_constants.mjs` resolves each column's CHECK by
 * replaying every migration and demands EQUALITY — not containment, which is
 * what it demands of `COLUMN_LIMITS`. A CHECK widened to 600 fails the PR that
 * widens it and names this line. decisions § 819.
 */
export const COLUMN_CHECK_MAX = {
	'body_metrics.weight_kg': 500,
	'user_profiles.height_cm': 300
} as const satisfies Record<string, number>;

export type ColumnCheckMaxKey = keyof typeof COLUMN_CHECK_MAX;

/** The largest value the column's own CHECK admits, in its canonical unit. */
export function columnCheckMax(key: ColumnCheckMaxKey): number {
	return COLUMN_CHECK_MAX[key];
}

/** The inclusive value range for a column, in the column's canonical unit. */
export function valueLimit(key: ColumnLimitKey): { min: number; max: number } {
	const limit: ColumnLimit = COLUMN_LIMITS[key];
	if (limit.kind !== 'value') throw new Error(`${key} is a length limit, not a value limit`);
	return { min: limit.min, max: limit.max };
}

/** The character cap for a column. */
export function lengthLimit(key: ColumnLimitKey): number {
	const limit: ColumnLimit = COLUMN_LIMITS[key];
	if (limit.kind !== 'length') throw new Error(`${key} is a value limit, not a length limit`);
	return limit.max;
}

/**
 * True when `value` is inside the column's client range. A non-finite value is
 * outside it — a caller that admitted `NaN` would send `null` or a 22P02, not a
 * measurement.
 */
export function withinValueLimit(key: ColumnLimitKey, value: number): boolean {
	const { min, max } = valueLimit(key);
	return Number.isFinite(value) && value >= min && value <= max;
}
