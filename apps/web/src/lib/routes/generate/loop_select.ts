/**
 * Selection for the sampled via-point polygon loop generator (route loop
 * generation v2 — see docs/features/route_loop_generation.md).
 *
 * A polygon candidate is `start → v1 → … → vK → start` routed through the
 * engine. We sample K via-points on a ring around the start across a few
 * rotations + radii, then pick the best-shaped loop here. Reuses the
 * isoperimetric `areaEfficiency` from `./select` (enclosed area vs a circle of
 * equal perimeter: ~1 for a round loop, →0 for an out-and-back spur) as the
 * shape metric, plus the engine's per-via-point snap distance to reject a
 * via-point that landed on a far-off road.
 *
 * Returning null is a first-class signal, not an error: it means no candidate
 * cleared the spur/snap bar, i.e. this is a loop-poor location and the caller
 * should fall back to the round_trip out-and-back + the honest "no real loop
 * here" UX rather than render a degenerate polygon.
 */

import { areaEfficiency } from './select';

/// Benchmarked sampling + scoring parameters (the values the PoC across
/// dense/medium/sparse starts settled on — re-measure if the engine profile or
/// version changes). kValues are the via-point counts to try (triangle +
/// quadrilateral); radiusFractions are ring radii as a fraction of the target;
/// spurFloor is the minimum areaEfficiency a real loop must clear; maxSnapM is
/// the worst via-point snap distance tolerated; bandFraction is the ±distance
/// tolerance within which candidates are "close enough" to decide on shape.
export const LOOP_PARAMS = {
	kValues: [3, 4] as const,
	rotationCount: 12,
	radiusFractions: [0.12, 0.13, 0.14, 0.15, 0.16] as const,
	spurFloor: 0.12,
	maxSnapM: 250,
	bandFraction: 0.15,
} as const;

/// One via-point polygon loop. `maxSnapM` is the largest distance any of its
/// via-points snapped from where we placed it to the road the engine actually
/// used — a high value means the ring fell into a road-sparse gap and the loop
/// is distorted. Structurally a superset of `./select`'s LoopCandidate, so it
/// passes straight into `areaEfficiency`.
export interface PolygonCandidate {
	/// GeoJSON `[lng, lat]` order, matching the engine + route builder.
	coordinates: [number, number][];
	distanceM: number;
	maxSnapM: number;
}

export interface PickBestPolygonOpts {
	spurFloor: number;
	maxSnapM: number;
	bandFraction: number;
}

export function pickBestPolygonLoop(
	cands: PolygonCandidate[],
	targetM: number,
	opts: PickBestPolygonOpts,
): PolygonCandidate | null {
	const survivors = cands.filter(
		(c) =>
			c.coordinates.length >= 2 &&
			c.distanceM > 0 &&
			c.maxSnapM <= opts.maxSnapM &&
			areaEfficiency(c) >= opts.spurFloor,
	);
	if (survivors.length === 0) return null;

	const within = survivors.filter(
		(c) => Math.abs(c.distanceM - targetM) <= opts.bandFraction * targetM,
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
					Math.abs(c.distanceM - targetM) < Math.abs(best.distanceM - targetM));
			if (better) {
				best = c;
				bestEff = eff;
			}
		}
		return best;
	}

	// Nothing in-band → closest to target wins; roundness breaks ties.
	let best = survivors[0];
	let bestDelta = Math.abs(best.distanceM - targetM);
	for (let i = 1; i < survivors.length; i++) {
		const c = survivors[i];
		const delta = Math.abs(c.distanceM - targetM);
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
