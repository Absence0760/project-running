import type { TrackPoint } from '../types';

/**
 * Datum gating for the run-detail key-stats grid.
 *
 * Every cell in that grid states a measurement, so a cell whose datum is
 * missing has to be ABSENT rather than zero. A run with no track, a track
 * that never recorded altitude, and a genuinely flat run are three different
 * facts; rendering `0 m` for all three reports the first two as the third.
 * Same for a `metadata.steps` of 0, which used to render as a step count of
 * zero and then divide into a cadence of `0 spm` (decisions § 1164).
 *
 * These answer only "is there a datum here" — the arithmetic stays with the
 * rules that own it (`computeElevationGain` for the climb). They mirror the
 * gates `run_detail_screen.dart` applies to the same cells (`_hasElevation`,
 * `_steps > 0`, `_cadence > 0`); mobile holds them as inline getters on the
 * screen, so this is not a registered TS<->Dart parity pair.
 */

/**
 * Under this much moving time a step count divides into a cadence figure too
 * noisy to state. 30 s, the floor mobile's `_cadence` uses.
 */
export const MIN_CADENCE_MOVING_S = 30;

/**
 * The track a climb may be measured over, or null when none of its points
 * carried an altitude.
 *
 * `computeElevationGain` sums to 0 over a track with no `ele` exactly as it
 * does over a flat one, so the discriminator has to be the samples, not the
 * answer. Returns the track itself so the caller can feed the rule directly
 * without re-testing for null.
 */
export function elevationSourceTrack(
	track: TrackPoint[] | null | undefined,
): TrackPoint[] | null {
	if (!track) return null;
	return track.some((p) => p.ele != null) ? track : null;
}

/**
 * The fewest altitude samples a profile can be drawn from. Two: one sample is
 * a point, and the chart would render it as a flat line spanning the whole run
 * at that altitude -- the same false claim about a flat course the all-zero
 * array used to make, only at 1800 m instead of 0.
 */
export const MIN_ELEVATION_SAMPLES = 2;

/**
 * The altitude series the elevation profile is drawn from -- one value per
 * track point, gaps filled by interpolation -- or null when the track carries
 * too few samples to draw one.
 *
 * The array has to stay 1:1 with the track: the chart reports a hovered INDEX
 * and the page maps it straight back to a lat/lng for the linked map cursor,
 * so a compacted series would paint the marker somewhere the runner never was.
 * That is why the gaps are filled rather than dropped. Filling them at sea
 * level, which is what `p.ele ?? 0` did, drew an alpine run at 1800-2400 m as
 * a set of vertical cliffs to 0 m with a y-axis stretched from zero -- and one
 * point carrying an altitude was enough to mount the chart (decisions § 1224).
 *
 * Interpolation is linear in INDEX, not in distance, because the chart's own
 * x-axis is the index: the filled values are exactly the straight line it
 * would have drawn between the two real samples had the gap not been there.
 * Leading and trailing gaps carry the nearest known sample, the same
 * carry-across `computeElevationGain` applies to the identical dropout, so the
 * chart and the climb figure beside it agree about what a gap means.
 */
export function elevationSeries(
	track: TrackPoint[] | null | undefined,
): number[] | null {
	if (!track || track.length < 2) return null;
	const known: number[] = [];
	for (let i = 0; i < track.length; i++) {
		const ele = track[i].ele;
		if (typeof ele === 'number' && Number.isFinite(ele)) known.push(i);
	}
	if (known.length < MIN_ELEVATION_SAMPLES) return null;

	const out = new Array<number>(track.length);
	const eleAt = (i: number) => track[i].ele as number;
	for (let k = 0; k < known.length; k++) {
		out[known[k]] = eleAt(known[k]);
	}
	for (let i = 0; i < known[0]; i++) out[i] = eleAt(known[0]);
	const last = known[known.length - 1];
	for (let i = last + 1; i < track.length; i++) out[i] = eleAt(last);
	for (let k = 1; k < known.length; k++) {
		const a = known[k - 1];
		const b = known[k];
		const span = b - a;
		if (span < 2) continue;
		const rise = eleAt(b) - eleAt(a);
		for (let i = a + 1; i < b; i++) {
			out[i] = eleAt(a) + (rise * (i - a)) / span;
		}
	}
	return out;
}

/**
 * A step count off the schemaless `metadata` bag, or null when the value is
 * not a count of steps taken.
 *
 * `metadata` has no schema and imports write it, so the type is checked here
 * rather than assumed. A fractional value is truncated the way mobile's
 * `_steps` truncates it, and anything that does not survive as at least one
 * step is no reading at all.
 */
export function stepCount(value: unknown): number | null {
	if (typeof value !== 'number' || !Number.isFinite(value)) return null;
	const steps = Math.trunc(value);
	return steps > 0 ? steps : null;
}

/**
 * Average cadence in steps per minute, or null when it cannot be stated.
 *
 * Prefers a directly-reported `metadata.cadence_spm` (the Garmin FIT importer
 * writes it and has no pedometer count — persona #17); otherwise derives it
 * from steps over moving time. A reported value that rounds away to zero does
 * NOT fall through to the derivation — mobile returns it and hides the tile,
 * and a sensor claiming under half a step per minute is not evidence about
 * the pedometer's count.
 */
export function cadenceSpm(
	stored: unknown,
	steps: number | null,
	movingSeconds: number,
): number | null {
	if (typeof stored === 'number' && Number.isFinite(stored) && stored > 0) {
		const reported = Math.round(stored);
		return reported > 0 ? reported : null;
	}
	if (steps == null || !Number.isFinite(movingSeconds)) return null;
	if (movingSeconds < MIN_CADENCE_MOVING_S) return null;
	const derived = Math.round(steps / (movingSeconds / 60));
	return derived > 0 ? derived : null;
}

/**
 * The run row's own total ascent in metres, or null when the row carries none.
 *
 * `20270302_001` promoted total ascent to `runs.elevation_gain_m` and left
 * `metadata.elevation_m` in place for the rows written before it; the column is
 * canonical and the key is what older rows carry, so both are read here and in
 * one order. This is a claim ABOUT THE ROW — it is not `computeElevationGain`
 * over a track, and a caller that has a track with altitudes should prefer that
 * measurement, which is the one the elevation profile on the same page is drawn
 * from.
 *
 * Null, not 0, when neither is a usable number: a run nothing measured the
 * ascent of and a genuinely flat one are different facts (§ 1164), and the
 * challenge aggregate that sums this column coalesces its own nulls.
 */
export function storedElevationGainM(run: {
	elevation_gain_m?: number | null;
	metadata?: unknown;
}): number | null {
	const gain = run.elevation_gain_m;
	if (typeof gain === 'number' && Number.isFinite(gain)) return gain;
	const meta = run.metadata as { elevation_m?: unknown } | null | undefined;
	const legacy = meta?.elevation_m;
	return typeof legacy === 'number' && Number.isFinite(legacy) ? legacy : null;
}
