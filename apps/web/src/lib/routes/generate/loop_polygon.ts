/**
 * Pure geometry for the sampled via-point loop generator
 * (route_loop_generation.md). Places K via-points on a ring around the start
 * to force a compact loop, and enumerates the (K × rotation × radius) sampling
 * grid the routing engine probes. No network, no engine coupling — the actual
 * OSRM/GraphHopper calls and `areaEfficiency` scoring live elsewhere; this
 * module only decides WHERE to put points and WHICH placements to try.
 *
 * Deterministic: same inputs → same outputs, so the search is reproducible and
 * cacheable (route_loop_generation.md § Determinism).
 */

/// Benchmarked search parameters (route_loop_generation.md § Search). The PoC
/// peaked at different rotations per start, so rotations are SAMPLED, never
/// fixed; radii are sampled as fractions of the target distance.
export interface PlacementParams {
	/// Number of via-points per ring — the polygon order. K=3 (triangle) is the
	/// primary shape; K=4 blows up more often but still wins some starts.
	kValues: number[];
	/// How many evenly-spaced ring rotations to sample (0°, 360/n°, …).
	rotationCount: number;
	/// Ring radii to try, as fractions of the target distance.
	radiusFractions: number[];
	/// Minimum areaEfficiency for a candidate to count as a real loop (vs an
	/// out-and-back spur). Consumed by the selection layer, not by this module.
	spurFloor: number;
	/// Drop a candidate whose via-point snapped further than this from its
	/// requested position (metres). Consumed by the selection layer.
	maxSnapM: number;
	/// Distance tolerance (fraction of target) for "close enough" selection.
	/// Consumed by the selection layer.
	bandFraction: number;
}

export const DEFAULT_PLACEMENT_PARAMS: PlacementParams = {
	kValues: [3, 4],
	rotationCount: 12,
	radiusFractions: [0.12, 0.13, 0.14, 0.15, 0.16],
	spurFloor: 0.12,
	maxSnapM: 250,
	bandFraction: 0.15,
};

const M_PER_DEG_LAT = 111320;

/// Place `k` via-points evenly on a ring of `radiusM` around `start`, with the
/// first point at `rotationDeg` (clockwise from due north). Uses an
/// equirectangular offset with a cos(lat) longitude correction so the ring is
/// circular in metres at any latitude.
export function viaPoints(
	start: { lat: number; lng: number },
	radiusM: number,
	k: number,
	rotationDeg: number,
): { lat: number; lng: number }[] {
	const mPerDegLng = M_PER_DEG_LAT * Math.cos((start.lat * Math.PI) / 180);
	const out: { lat: number; lng: number }[] = [];
	for (let i = 0; i < k; i++) {
		const bearingDeg = rotationDeg + (360 * i) / k;
		const bearingRad = (bearingDeg * Math.PI) / 180;
		// Bearing is clockwise from north: north (0°) is +lat, east (90°) is
		// +lng. North component → sin offset on latitude, east component → cos
		// of the co-bearing; expressed directly as cos(bearing) for the
		// north/lat axis and sin(bearing) for the east/lng axis.
		const dNorthM = radiusM * Math.cos(bearingRad);
		const dEastM = radiusM * Math.sin(bearingRad);
		out.push({
			lat: start.lat + dNorthM / M_PER_DEG_LAT,
			lng: start.lng + dEastM / mPerDegLng,
		});
	}
	return out;
}

/// Enumerate the full (K × rotation × radiusFraction) sampling grid for a
/// target distance. Rotations are evenly spaced over [0°, 360°). Order is
/// deterministic: k (outer) → rotation → radiusFraction (inner).
export function candidatePlacements(
	targetM: number,
	params: PlacementParams,
): { k: number; rotationDeg: number; radiusM: number }[] {
	const out: { k: number; rotationDeg: number; radiusM: number }[] = [];
	for (const k of params.kValues) {
		for (let r = 0; r < params.rotationCount; r++) {
			const rotationDeg = (360 * r) / params.rotationCount;
			for (const fraction of params.radiusFractions) {
				out.push({ k, rotationDeg, radiusM: targetM * fraction });
			}
		}
	}
	return out;
}
