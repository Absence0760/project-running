/**
 * Numeric bounds on user-entered columns, stated once per client and enforced
 * by a matching CHECK constraint in the database.
 *
 * The sibling of `text_limits.ts` for the numeric half of the same defect. A
 * field capped below the constraint is merely conservative; one capped above
 * it — or not capped at all — hands the runner a postgres 23514 naming a
 * constraint, which is not a sentence anybody can act on. That is what
 * `body_metrics.weight_kg` did: `<input type="number" min="0">` with no `max`
 * against `check (weight_kg > 0 and weight_kg <= 500)`, so 600 kg (or 1200 lb,
 * which is 544 kg) round-tripped to a raw error, and `min="0"` admitted
 * exactly the one value the `> 0` half rejects. decisions.md § 792.
 *
 * Every entry is the constraint's own effective INCLUSIVE range, not a
 * paraphrase of it: an exclusive `> 0` becomes the smallest value the column's
 * `numeric(p, s)` scale can hold above zero, because that is the bound a form
 * can actually state. `scripts/check_shared_constants.mjs` reads the CHECK out
 * of the migrations and compares, so neither number here is a transcription
 * anyone has to keep true by hand.
 *
 * A field may enforce something NARROWER — `format/weight.ts`'s 20–250 kg
 * plausible-human-body-weight range is inside `bodyMetricsWeightKg` and is
 * what the demographics form actually shows. The registry is the ceiling that
 * narrowing may never exceed.
 *
 * Mirrored in `apps/mobile_android/lib/numeric_limits.dart`.
 */
export type NumericLimit = {
	readonly min: number;
	readonly max: number;
};

export const NUMERIC_LIMITS = {
	bodyMetricsWeightKg: { min: 0.01, max: 500 },
	profileHeightCm: { min: 0.1, max: 300 },
	checkpointBodyWeightKg: { min: 20, max: 400 },
	gymSetRpe: { min: 0, max: 10 },
	routineTargetRpe: { min: 0, max: 10 },
	routineRestS: { min: 0, max: 3600 }
} as const satisfies Record<string, NumericLimit>;

/** The `<table>.<column>` each bound is enforced on, so the guard can find its CHECK. */
export const NUMERIC_LIMIT_COLUMNS: Record<keyof typeof NUMERIC_LIMITS, string> = {
	bodyMetricsWeightKg: 'body_metrics.weight_kg',
	profileHeightCm: 'user_profiles.height_cm',
	checkpointBodyWeightKg: 'checkpoint_crossings.body_weight_kg',
	gymSetRpe: 'gym_sets.rpe',
	routineTargetRpe: 'gym_routine_sets.target_rpe',
	routineRestS: 'gym_routine_sets.rest_s'
};

export type NumericLimitVerdict = 'ok' | 'below' | 'above' | 'invalid';

/**
 * Grade a value already converted to the column's CANONICAL unit. Callers that
 * take a typed value in a display unit must convert first: refusing 1200 lb
 * because it is above a bound of 500 would be refusing the wrong number.
 */
export function checkNumericLimit(limit: NumericLimit, value: number): NumericLimitVerdict {
	if (!Number.isFinite(value)) return 'invalid';
	if (value < limit.min) return 'below';
	if (value > limit.max) return 'above';
	return 'ok';
}

/**
 * The bound restated in the unit the field is TYPED in, rounded INWARD to one
 * decimal place.
 *
 * Inward, because the number this returns is shown to the runner — as the
 * input's `min`/`max` and in the refusal — and a bound the runner cannot
 * satisfy by typing it is a loop they cannot escape. The cost is that the
 * pounds form cannot express the last 0.03 lb below a 500 kg ceiling, which
 * excludes no weight any human has.
 */
export function numericBoundsIn(
	limit: NumericLimit,
	toDisplay: (canonical: number) => number = (v) => v
): NumericLimit {
	return {
		min: Math.ceil(toDisplay(limit.min) * 10) / 10,
		max: Math.floor(toDisplay(limit.max) * 10) / 10
	};
}
