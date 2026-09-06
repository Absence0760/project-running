import type { TrackPoint } from '../types';
import { haversineMetres } from './run_stats';

/**
 * Grade-adjusted pace (GAP): the flat-ground pace that would cost the same
 * metabolic effort as the run actually recorded over hilly terrain. Raw
 * average pace lies on hills — a 6:00/km grind up a 10% wall reads slow and a
 * screaming descent reads fast — so trail and ultra runners want the
 * effort-equivalent number instead.
 *
 * Energy-cost model: Minetti et al. 2002, "Energy cost of walking and running
 * at extreme uphill and downhill slopes" (J Appl Physiol 93:1039). C(i) is the
 * metabolic cost of running at gradient i (rise/run, fractional); the GAP
 * factor is C(i)/C(0) — how much harder this grade is than flat. Equivalent
 * flat distance for a segment is its horizontal distance times that factor.
 *
 * Twin of `apps/mobile_android/lib/grade_adjusted_pace.dart` — keep the
 * algorithm, constants, edge cases, and test count in lockstep. Ported from
 * the on-watch Connect IQ field at
 * `apps/watch_garmin/source/GradeAdjustedPaceView.mc`; this is the web-first
 * surface that field's shipping was gated on (decisions §107).
 */

/** Flat-ground running cost C(0) from the polynomial below. */
export const MINETTI_FLAT_COST = 3.6;

/**
 * Minetti's fit is only valid between roughly -45% and +45% grade; clamp to
 * that so a momentary GPS-altitude spike can't manufacture an absurd factor.
 */
export const MAX_GRADE = 0.45;

/**
 * Minimum horizontal travel before a grade sample is trusted. Altitude is
 * jittery point-to-point, so grade is measured over a segment rather than over
 * a point pair.
 *
 * The window has a floor, and the 5 m it shipped with was below it:
 * `ELEVATION_GAIN_MIN_DELTA_M / MAX_GRADE` = 6.67 m. Under that, the smallest
 * altitude change this codebase is willing to call climb rather than noise is,
 * on its own, past the steepest grade Minetti's fit is defined at — 3 m over
 * 5 m is a 60% grade, which clamps and yields a factor of 5.396. A rise the
 * elevation-gain path discards outright therefore reported a pace 5.4x faster
 * than raw, and a single 1 m step did it at 2.50.
 *
 * Only the horizontal leg is gated, and a gate on the RISE cannot replace it:
 * the rise a real grade produces over the window scales with the window
 * exactly as the noise does, so a threshold large enough to suppress the noise
 * suppresses every real grade below `threshold / window` with it. Measured, a
 * 3 m rise gate at this window zeroes every real grade under 15% — on a clean,
 * noise-free 3.3% climb it read 19.5% slow — while the GPS-altitude noise it
 * aims at has a 3.8 m sigma and walks straight through it.
 *
 * 20 m is where the noise floor stops being able to more than double the
 * reported effort (3 m over 20 m is a 15% grade, factor 2.06), and it is the
 * largest window whose cost on real oscillating terrain stays under 3%.
 * Measured over an AR(1) altitude-error model on 30-minute runs (decisions
 * §992): a flat track under GPS-altitude error reported GAP 47.9% faster than
 * truth at 5 m against 26.8% at 20 m, and under barometric error 2.1% -> 0.5%
 * at running pace and 9.0% -> 2.1% at power-hike pace. The cost is 2.5% on the
 * most oscillatory profile measured, against 5.2% at 30 m and 13.1% at 50 m.
 *
 * Matches `GradeAdjustedPaceView.mc`, the Dart twin and the firmware port; the
 * four are held equal by `scripts/check_watch_wire_vectors.mjs`.
 *
 * The roadbook is a SECOND consumer, deliberately: `routes/roadbook.ts` and
 * its Dart and firmware ports allocate a goal time by grade-adjusted effort
 * over this same anchored window, so a change here moves the arrival times a
 * race crew holds drop bags against as well as the pace a runner is shown.
 * Two windows would grade one course two ways. The same guard's consumer block
 * fails the day a roadbook rail stops importing this.
 */
export const MIN_SEGMENT_M = 20.0;

/** Minetti 2002 5th-order fit: C(i) in J/kg/m, i fractional gradient. */
export function minettiCostAtGrade(i: number): number {
	const i2 = i * i;
	const i3 = i2 * i;
	const i4 = i3 * i;
	const i5 = i4 * i;
	return 155.4 * i5 - 30.4 * i4 - 43.3 * i3 + 46.3 * i2 + 19.5 * i + 3.6;
}

/**
 * Cost multiplier relative to flat ground at a given fractional grade, with
 * the grade clamped to Minetti's valid range. 1.0 on the flat, > 1 uphill,
 * < 1 on gentle descents (running downhill is cheap until ~-20%).
 */
export function gradeFactor(grade: number): number {
	let g = grade;
	if (g > MAX_GRADE) g = MAX_GRADE;
	if (g < -MAX_GRADE) g = -MAX_GRADE;
	return minettiCostAtGrade(g) / MINETTI_FLAT_COST;
}

/**
 * Overall grade-adjusted pace for a run, in seconds per kilometre. Returns
 * null when GAP can't be computed or carries no information:
 *  - fewer than two track points,
 *  - no timestamps (can't derive segment durations),
 *  - no elevation data at all (GAP would equal raw pace).
 *
 * Walks the track accumulating horizontal distance until a segment is at least
 * [MIN_SEGMENT_M] long, then applies that segment's grade factor to its
 * horizontal distance to get equivalent-flat distance. GAP = total time over
 * total equivalent-flat distance.
 */
export function gradeAdjustedPaceSecPerKm(track: TrackPoint[] | null | undefined): number | null {
	if (!track || track.length < 2) return null;

	let anchor = 0;
	let segHoriz = 0;
	let adjDistM = 0;
	let timeS = 0;
	let sawEle = false;

	for (let i = 1; i < track.length; i++) {
		segHoriz += haversineMetres(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
		if (segHoriz < MIN_SEGMENT_M) continue;

		const a = track[anchor];
		const b = track[i];
		const dtMs = a.ts && b.ts ? Date.parse(b.ts) - Date.parse(a.ts) : NaN;
		if (Number.isFinite(dtMs) && dtMs > 0) {
			let factor = 1;
			let measuredGrade = false;
			if (a.ele != null && b.ele != null) {
				measuredGrade = true;
				factor = gradeFactor((b.ele - a.ele) / segHoriz);
			}
			// A segment whose equivalent-flat distance is not a number is
			// unusable in exactly the way a segment with no timestamps is, and
			// is skipped the same way. It reaches here when a track point
			// carries a non-finite lat/lng (`segHoriz` goes NaN, and
			// `NaN < MIN_SEGMENT_M` is false so the walk never resets) or a
			// non-finite altitude. Poisoning `adjDistM` instead used to erase
			// the GAP of a three-hour ultra over one bad fix — and did it by
			// returning NaN out of a `number | null`, which the Dart twin's
			// `.round()` threw on, from inside a widget build (§ 1226).
			const adj = segHoriz * factor;
			if (Number.isFinite(adj)) {
				if (measuredGrade) sawEle = true;
				adjDistM += adj;
				timeS += dtMs / 1000;
			}
		}
		// Advance the anchor whether or not the segment was usable — a chunk
		// without timestamps shouldn't wedge the walk forever.
		anchor = i;
		segHoriz = 0;
	}

	if (!sawEle || !(adjDistM > 0) || !(timeS > 0)) return null;
	return Math.round(timeS / (adjDistM / 1000));
}
