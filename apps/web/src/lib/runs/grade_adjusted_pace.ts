import type { TrackPoint } from '../types';

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
 * Minimum horizontal travel before a grade sample is trusted. GPS altitude is
 * jittery point-to-point, so grade is measured over a segment, mirroring the
 * watch field. 5 m matches `GradeAdjustedPaceView.mc`.
 */
export const MIN_SEGMENT_M = 5.0;

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
			if (a.ele != null && b.ele != null) {
				sawEle = true;
				factor = gradeFactor((b.ele - a.ele) / segHoriz);
			}
			adjDistM += segHoriz * factor;
			timeS += dtMs / 1000;
		}
		// Advance the anchor whether or not the segment was usable — a chunk
		// without timestamps shouldn't wedge the walk forever.
		anchor = i;
		segHoriz = 0;
	}

	if (!sawEle || adjDistM <= 0 || timeS <= 0) return null;
	return Math.round(timeS / (adjDistM / 1000));
}

/** Great-circle distance between two lat/lng points, in metres. */
function haversineMetres(lat1: number, lng1: number, lat2: number, lng2: number): number {
	const r = 6371000;
	const dLat = ((lat2 - lat1) * Math.PI) / 180;
	const dLng = ((lng2 - lng1) * Math.PI) / 180;
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const a =
		sinLat * sinLat +
		Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * sinLng * sinLng;
	return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
