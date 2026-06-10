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

/**
 * Total positive elevation gain in metres. Sums upward deltas between
 * consecutive track points, ignoring descents.
 *
 * Waypoints without an `ele` value are skipped.
 */
export function elevationGainMetres(track: TrackPoint[] | null | undefined): number {
	if (!track || track.length < 2) return 0;
	let gain = 0;
	for (let i = 1; i < track.length; i++) {
		const prev = track[i - 1].ele;
		const curr = track[i].ele;
		if (prev == null || curr == null) continue;
		if (curr > prev) gain += curr - prev;
	}
	return Math.round(gain);
}

export interface Split {
	km: number;
	pace_s: number;
	distance_m: number;
	elevation_m: number | null;
}

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

	// Accumulate cumulative distance and find the indices at each boundary.
	// Seed the first split's start time from the first point that actually
	// carries a parseable timestamp, not track[0]: a first GPS fix that lands
	// before the clock is stamped (ts missing on point 0, present after) would
	// otherwise seed NaN, fail the duration guard, and emit the first split at
	// pace 0:00 even though the run was timed from point 1 on. `hasTs`
	// guarantees at least one timed point exists.
	let cumDist = 0;
	const firstTimed = track.find((p) => p.ts != null && Number.isFinite(Date.parse(p.ts)));
	const startMs = firstTimed ? Date.parse(firstTimed.ts as string) : NaN;
	let splitStart = { idx: 0, dist: 0, timeMs: startMs, ele: track[0].ele };
	const splits: Split[] = [];

	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		cumDist += haversineMetres(a.lat, a.lng, b.lat, b.lng);
		const boundary = splits.length + 1;

		if (cumDist >= boundary * tickMetres) {
			const endTimeMs = b.ts ? Date.parse(b.ts) : NaN;
			const durationS = Number.isFinite(endTimeMs) ? (endTimeMs - splitStart.timeMs) / 1000 : 0;
			const splitDist = cumDist - splitStart.dist;
			const paceS = durationS > 0 && splitDist > 0 ? Math.round(durationS / (splitDist / 1000)) : 0;
			const eleNet = hasEle && b.ele != null && splitStart.ele != null
				? Math.round(b.ele - splitStart.ele)
				: null;

			splits.push({
				km: boundary,
				pace_s: paceS,
				distance_m: Math.round(splitDist),
				elevation_m: eleNet,
			});

			splitStart = { idx: i, dist: cumDist, timeMs: endTimeMs, ele: b.ele };
		}
	}

	// Final partial split if there are remaining metres.
	if (splits.length > 0 || cumDist > 0) {
		const lastPoint = track[track.length - 1];
		const endTimeMs = lastPoint.ts ? Date.parse(lastPoint.ts) : NaN;
		const durationS = Number.isFinite(endTimeMs) ? (endTimeMs - splitStart.timeMs) / 1000 : 0;
		const remainingDist = cumDist - splitStart.dist;
		if (remainingDist > 50) {
			const paceS = durationS > 0 && remainingDist > 0 ? Math.round(durationS / (remainingDist / 1000)) : 0;
			const eleNet = hasEle && lastPoint.ele != null && splitStart.ele != null
				? Math.round(lastPoint.ele - splitStart.ele)
				: null;
			splits.push({
				km: splits.length + 1,
				pace_s: paceS,
				distance_m: Math.round(remainingDist),
				elevation_m: eleNet,
			});
		}
	}

	return splits;
}

/**
 * Great-circle distance between two lat/lng points, in metres.
 */
function haversineMetres(
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
	return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
