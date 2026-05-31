/**
 * Stack-safe min/max over a numeric array.
 *
 * `Math.min(...arr)` / `Math.max(...arr)` pass every element as a separate
 * argument, and V8 throws `RangeError: Maximum call stack size exceeded` once
 * the spread exceeds ~110k entries. Track-derived arrays are unbounded — a
 * 50-hour ultra recorded at 1 Hz is ~180k points — so any min/max over an
 * elevation series or a list of track coordinates must reduce, not spread.
 *
 * Returns `null` for an empty input so callers pick their own fallback rather
 * than inheriting `Infinity` / `-Infinity` from an empty reduce.
 */
export function minMax(values: readonly number[]): { min: number; max: number } | null {
	if (values.length === 0) return null;
	let min = values[0];
	let max = values[0];
	for (let i = 1; i < values.length; i++) {
		const v = values[i];
		if (v < min) min = v;
		if (v > max) max = v;
	}
	return { min, max };
}
