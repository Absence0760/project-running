/**
 * Pick the best-shaped loop among the round_trip candidates.
 *
 * Every seed already hits the target distance closely (that's what
 * `round_trip.distance` does), so distance alone barely discriminates — the
 * real choice is *shape*. A good loop encloses area; the failure mode we're
 * replacing (the old radial-heuristic spur that doubled back on itself) encloses
 * almost none. So among candidates near the target we maximise an isoperimetric
 * "area efficiency": enclosed area relative to the area a circle of the same
 * perimeter would enclose — ~1 for a clean round loop, →0 for an out-and-back
 * spur. Distance closeness is the tie-break.
 */

import type { LoopCandidate } from './graphhopper';

/// Tolerance band (fraction of target) within which we treat candidates as
/// "close enough on distance" and decide purely on shape. round_trip usually
/// lands every seed well inside this, so the band rarely excludes anything —
/// it only guards against a wildly off candidate winning on shape alone.
const DISTANCE_BAND = 0.25;

/// Signed-area magnitude of the closed polyline in m², via the shoelace
/// formula on a local equirectangular projection (metres around the first
/// vertex's latitude). Open polylines are treated as implicitly closed.
export function enclosedAreaM2(coords: ReadonlyArray<[number, number]>): number {
	if (coords.length < 4) return 0;
	const lat0 = coords[0][1];
	const mPerDegLat = 111320;
	const mPerDegLng = 111320 * Math.cos((lat0 * Math.PI) / 180);
	let area = 0;
	for (let i = 0; i < coords.length; i++) {
		const [lng1, lat1] = coords[i];
		const [lng2, lat2] = coords[(i + 1) % coords.length];
		const x1 = lng1 * mPerDegLng;
		const y1 = lat1 * mPerDegLat;
		const x2 = lng2 * mPerDegLng;
		const y2 = lat2 * mPerDegLat;
		area += x1 * y2 - x2 * y1;
	}
	return Math.abs(area) / 2;
}

/// Enclosed area / area-of-equal-perimeter-circle. A circle of circumference
/// C encloses C²/(4π). Returns ~1 for a round loop, →0 for a thin spur.
export function areaEfficiency(c: LoopCandidate): number {
	if (c.distanceM <= 0) return 0;
	const circleArea = (c.distanceM * c.distanceM) / (4 * Math.PI);
	if (circleArea <= 0) return 0;
	return enclosedAreaM2(c.coordinates) / circleArea;
}

export function pickBestLoop(
	candidates: ReadonlyArray<LoopCandidate>,
	targetDistanceM: number,
): LoopCandidate | null {
	const valid = candidates.filter((c) => c.coordinates.length >= 2 && c.distanceM > 0);
	if (valid.length === 0) return null;

	const within = valid.filter(
		(c) => Math.abs(c.distanceM - targetDistanceM) <= DISTANCE_BAND * targetDistanceM,
	);
	const pool = within.length > 0 ? within : valid;

	let best = pool[0];
	let bestEff = areaEfficiency(best);
	for (let i = 1; i < pool.length; i++) {
		const c = pool[i];
		const eff = areaEfficiency(c);
		const better =
			eff > bestEff + 1e-9 ||
			(Math.abs(eff - bestEff) <= 1e-9 &&
				Math.abs(c.distanceM - targetDistanceM) < Math.abs(best.distanceM - targetDistanceM));
		if (better) {
			best = c;
			bestEff = eff;
		}
	}
	return best;
}
