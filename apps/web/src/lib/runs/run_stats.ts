import type { TrackPoint } from '../types';

/**
 * Moving time — elapsed with stops excluded, derived from a GPS track.
 *
 * Mirrors `apps/mobile_android/lib/run_stats.dart:movingTimeOf`. Both
 * clients compute this on demand at display time rather than storing it,
 * so the metric stays consistent if the algorithm is tuned later.
 *
 * Walks consecutive waypoint pairs, computes `speed = distance / time`,
 * and counts only segments whose speed is at or above [minSpeedMps].
 * Default 0.5 m/s (~1.8 km/h) — slower than a slow walk but above the
 * noise floor when the runner is standing still.
 *
 * Returns seconds.
 */
export function movingTimeSeconds(
	track: TrackPoint[] | null | undefined,
	minSpeedMps = 0.5
): number {
	if (!track || track.length < 2) return 0;
	let movingMs = 0;
	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		if (!a.ts || !b.ts) continue;
		const dtMs = Date.parse(b.ts) - Date.parse(a.ts);
		if (!Number.isFinite(dtMs) || dtMs <= 0) continue;
		const distance = haversineMetres(a.lat, a.lng, b.lat, b.lng);
		const speed = distance / (dtMs / 1000);
		if (speed >= minSpeedMps) movingMs += dtMs;
	}
	return Math.round(movingMs / 1000);
}


export interface Split {
	km: number;
	pace_s: number;
	distance_m: number;
	elevation_m: number | null;
}

/**
 * The shortest tail `computeRealSplits` will emit as a split of its own, in
 * metres. Below it the split table drops the leftover rather than printing a
 * pace derived from a few seconds over a few metres.
 */
export const SPLIT_TAIL_MIN_M = 50;

/**
 * Compute per-unit splits from a GPS track. Requires timestamps on track
 * points; returns [] when fewer than two points carry timestamps. Mirrors
 * the Android `run_detail_screen.dart` split logic.
 *
 * `tickMetres` is the split boundary length — 1000 for km splits,
 * 1609.344 for mile splits, so a miles-preference user gets mile-long
 * splits instead of km ones (mobile already does this via `tickLength`).
 * `pace_s` stays canonical seconds-per-km regardless of tick length; the
 * caller converts to the display unit (`formatPaceNoSuffix`).
 *
 * Elevation per split is the net gain/loss (positive = gain) over that
 * segment. Null when the track has no elevation data.
 */
export function computeRealSplits(track: TrackPoint[], tickMetres = 1000): Split[] {
	if (track.length < 2) return [];
	const hasTs = track.some((p) => p.ts != null);
	if (!hasTs) return [];

	const hasEle = track.some((p) => p.ele != null);

	// Seed the first split's start time from the first point that actually
	// carries a parseable timestamp, not track[0]: a first GPS fix that lands
	// before the clock is stamped (ts missing on point 0, present after) would
	// otherwise seed NaN, fail the duration guard, and emit the first split at
	// pace 0:00 even though the run was timed from point 1 on. `hasTs`
	// guarantees at least one timed point exists.
	const firstTimed = track.find((p) => p.ts != null && Number.isFinite(Date.parse(p.ts)));
	const startMs = firstTimed ? Date.parse(firstTimed.ts as string) : NaN;

	let cumDist = 0;
	let splitStart = { dist: 0, timeMs: startMs, ele: track[0].ele ?? null };
	const splits: Split[] = [];

	// Close the current split at cumulative distance `endDist`, using the
	// (interpolated) crossing time + elevation, then re-seed the next split
	// from there. Pace is normalised by the split's actual distance, so a
	// split that isn't exactly `tickMetres` still reports a correct per-km pace.
	const emit = (endDist: number, endTimeMs: number, endEle: number | null) => {
		const durationS =
			Number.isFinite(endTimeMs) && Number.isFinite(splitStart.timeMs)
				? (endTimeMs - splitStart.timeMs) / 1000
				: 0;
		const splitDist = endDist - splitStart.dist;
		const paceS = durationS > 0 && splitDist > 0 ? Math.round(durationS / (splitDist / 1000)) : 0;
		const eleNet =
			hasEle && endEle != null && splitStart.ele != null ? Math.round(endEle - splitStart.ele) : null;
		splits.push({
			km: splits.length + 1,
			pace_s: paceS,
			distance_m: Math.round(splitDist),
			elevation_m: eleNet,
		});
		splitStart = { dist: endDist, timeMs: endTimeMs, ele: endEle };
	};

	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		const segStart = cumDist;
		const segDist = haversineMetres(a.lat, a.lng, b.lat, b.lng);
		cumDist += segDist;
		const aMs = a.ts ? Date.parse(a.ts) : NaN;
		const bMs = b.ts ? Date.parse(b.ts) : NaN;

		// A single segment can straddle several tick boundaries when there is a
		// long gap between two fixes (a tunnel, a canyon/forest signal loss, or
		// a downsampled Strava/Garmin import). Emit a split AT each boundary,
		// interpolating the crossing time + elevation by the distance fraction
		// along the segment — so the gap becomes one correctly-sized split per
		// tick instead of one oversized split followed by zero-distance slivers.
		let boundaryDist = (splits.length + 1) * tickMetres;
		while (segDist > 0 && cumDist >= boundaryDist) {
			const f = (boundaryDist - segStart) / segDist;
			const crossMs = Number.isFinite(aMs) && Number.isFinite(bMs) ? aMs + f * (bMs - aMs) : bMs;
			const crossEle =
				hasEle && a.ele != null && b.ele != null ? a.ele + f * (b.ele - a.ele) : (b.ele ?? null);
			emit(boundaryDist, crossMs, crossEle);
			boundaryDist = (splits.length + 1) * tickMetres;
		}
	}

	// The tail after the last whole tick, emitted only when it is long enough
	// to carry a pace worth reading. Under the floor the duration is a handful
	// of seconds over a handful of metres, and dividing them prints a pace off
	// by an order of magnitude beside every real split in the table.
	//
	// The consequence is deliberate and stated here because the numbers are
	// visible: a run of 5.04 km renders five splits summing to 5,000 m, so the
	// split table's own total is up to `SPLIT_TAIL_MIN_M` short of the run's
	// headline distance. A wrong pace on a named row is worse than a total
	// that is under one percent light on a 5 km.
	if (splits.length > 0 || cumDist > 0) {
		const lastPoint = track[track.length - 1];
		const endTimeMs = lastPoint.ts ? Date.parse(lastPoint.ts) : NaN;
		if (cumDist - splitStart.dist > SPLIT_TAIL_MIN_M) {
			emit(cumDist, endTimeMs, lastPoint.ele ?? null);
		}
	}

	return splits;
}

/**
 * Great-circle distance between two lat/lng points, in metres.
 */
/**
 * Great-circle metres between two points. Exported so the twin contract with
 * `run_stats.dart`'s `haversineMetres` can be pinned on both sides — it was
 * private, which is why a divergence in it went unnoticed.
 */
export function haversineMetres(
	lat1: number,
	lng1: number,
	lat2: number,
	lng2: number
): number {
	const r = 6371000;
	const dLat = ((lat2 - lat1) * Math.PI) / 180;
	const dLng = ((lng2 - lng1) * Math.PI) / 180;
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const a =
		sinLat * sinLat +
		Math.cos((lat1 * Math.PI) / 180) *
			Math.cos((lat2 * Math.PI) / 180) *
			sinLng *
			sinLng;
	// Clamp before the arc. Rounding can push `a` a hair above 1 for a
	// near-antipodal pair, and then `Math.sqrt(1 - a)` is NaN — which propagates
	// silently through every consumer (moving time, splits, segment distances)
	// rather than throwing. The Dart twin clamps identically; an earlier pass
	// fixed only that side on the false belief that this one already did, which
	// left the pair divergent with the NaN moved here. Measured on
	// (-87.5, 0, 87.5, 180): unclamped NaN, clamped 20015086.796.
	const clamped = a > 1 ? 1 : a < 0 ? 0 : a;
	return r * 2 * Math.asin(Math.sqrt(clamped));
}
