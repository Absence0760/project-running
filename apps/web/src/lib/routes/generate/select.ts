/**
 * Pick the best loop among the round_trip candidates.
 *
 * round_trip's per-seed distance is erratic in sparse road networks, so we may
 * or may not have a candidate near the target. Two tiers:
 *
 *  - If any candidate lands within ±DISTANCE_BAND of the target, they're all
 *    "close enough" on distance, so we choose on *shape*: maximise an
 *    isoperimetric "area efficiency" (enclosed area vs the area a circle of the
 *    same perimeter would enclose — ~1 for a clean round loop, →0 for an
 *    out-and-back spur). Distance closeness breaks ties.
 *  - If NONE is in-band (a sparse start where every seed over/undershoots), the
 *    closest-to-target candidate wins — a 6.9 km loop beats a rounder 9.2 km one
 *    when 5 km was asked. Shape breaks ties.
 */

import type { LoopCandidate } from './graphhopper';

/// Tolerance band (fraction of target) within which candidates are "close
/// enough on distance" so we decide purely on shape. Set to match the ±15%
/// ACCEPT_BAND warning threshold in `route_loop.ts`: a candidate inside the band
/// won't trigger the route builder's over/undershoot warning, so among those we
/// pick the prettiest loop — and only when NONE is inside do we fall back to
/// closest-to-target, minimising the warning the user actually sees.
const DISTANCE_BAND = 0.15;

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

	// In-band: all close enough on distance → pick the roundest; closeness ties.
	if (within.length > 0) {
		let best = within[0];
		let bestEff = areaEfficiency(best);
		for (let i = 1; i < within.length; i++) {
			const c = within[i];
			const eff = areaEfficiency(c);
			const better =
				eff > bestEff + 1e-9 ||
				(Math.abs(eff - bestEff) <= 1e-9 &&
					Math.abs(c.distanceM - targetDistanceM) <
						Math.abs(best.distanceM - targetDistanceM));
			if (better) {
				best = c;
				bestEff = eff;
			}
		}
		return best;
	}

	// Nothing in-band → closest to target wins; roundness breaks ties.
	let best = valid[0];
	let bestDelta = Math.abs(best.distanceM - targetDistanceM);
	for (let i = 1; i < valid.length; i++) {
		const c = valid[i];
		const delta = Math.abs(c.distanceM - targetDistanceM);
		const better =
			delta < bestDelta - 1e-9 ||
			(Math.abs(delta - bestDelta) <= 1e-9 && areaEfficiency(c) > areaEfficiency(best));
		if (better) {
			best = c;
			bestDelta = delta;
		}
	}
	return best;
}
