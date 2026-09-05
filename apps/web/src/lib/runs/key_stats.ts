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
