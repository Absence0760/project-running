/**
 * Simplify a polyline using the Ramer–Douglas–Peucker algorithm. Returns
 * a subset of `points` that preserves the shape within `epsilonMetres`
 * of perpendicular distance from the straight-line segments. Used to
 * turn a noisy GPS track from a run into a cleaner saved route before
 * writing it as a `routes` row.
 *
 * Ported from `apps/mobile_android/lib/route_simplify.dart` — keep in
 * sync. 10 m epsilon is a good default for running; tuning it tighter
 * keeps more turns, looser collapses more jitter.
 */
export interface LatLng {
	lat: number;
	lng: number;
	ele?: number | null;
}

export function simplifyTrack(
	points: LatLng[],
	epsilonMetres = 10,
): LatLng[] {
	if (points.length < 3) return [...points];
	const keep = new Array<boolean>(points.length).fill(false);
	keep[0] = true;
	keep[points.length - 1] = true;
	dpStep(points, 0, points.length - 1, epsilonMetres, keep);
	return points.filter((_, i) => keep[i]);
}

function dpStep(
	points: LatLng[],
	first: number,
	last: number,
	eps: number,
	keep: boolean[],
): void {
	if (last <= first + 1) return;
	let maxDist = 0;
	let maxIndex = first;
	for (let i = first + 1; i < last; i++) {
		const d = perpDistanceMetres(points[i], points[first], points[last]);
		if (d > maxDist) {
			maxDist = d;
			maxIndex = i;
		}
	}
	if (maxDist > eps) {
		keep[maxIndex] = true;
		dpStep(points, first, maxIndex, eps, keep);
		dpStep(points, maxIndex, last, eps, keep);
	}
}

/**
 * Perpendicular distance from `p` to segment `a-b`, in metres.
 * Equirectangular projection centred on `a` — cheap and accurate enough
 * at the scale RDP cares about (10s of metres at worst).
 */
function perpDistanceMetres(p: LatLng, a: LatLng, b: LatLng): number {
	const r = 6_371_000;
	const latRad = (a.lat * Math.PI) / 180;
	const cosLat = Math.cos(latRad);
	const x = (w: LatLng) => ((w.lng * Math.PI) / 180) * cosLat * r;
	const y = (w: LatLng) => ((w.lat * Math.PI) / 180) * r;

	const ax = x(a);
	const ay = y(a);
	const bx = x(b);
	const by = y(b);
	const px = x(p);
	const py = y(p);

	const dx = bx - ax;
	const dy = by - ay;
	const lenSq = dx * dx + dy * dy;
	if (lenSq === 0) {
		const ex = px - ax;
		const ey = py - ay;
		return Math.sqrt(ex * ex + ey * ey);
	}
	const t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
	const tClamped = Math.max(0, Math.min(1, t));
	const projX = ax + tClamped * dx;
	const projY = ay + tClamped * dy;
	const fx = px - projX;
	const fy = py - projY;
	return Math.sqrt(fx * fx + fy * fy);
}

/**
 * Smallest elevation move that counts as real climb, in metres. Consumer GPS
 * altitude is noisy at the 1-3 m level sample to sample, and a raw 1 Hz sum
 * over a long run integrates that jitter into thousands of metres of vert that
 * never happened. The reference height only moves once a change clears this
 * band in either direction, so noise inside it contributes nothing while a
 * genuine climb is counted in full.
 */
export const ELEVATION_GAIN_MIN_DELTA_M = 3;

/**
 * Total positive elevation change across the polyline, in metres, over the
 * RAW track — never a simplified one. Twin of the Dart `computeElevationGain`
 * in `apps/mobile_android/lib/route_simplify.dart`; keep in lockstep.
 *
 * Two rules, both load-bearing:
 *
 * 1. A waypoint with no elevation is skipped and the last valid reading is
 *    carried across the gap, so an intermittent dropout (tree cover, a tunnel,
 *    satellite reacquisition on a long ultra) doesn't silently erase the climb
 *    that spans the missing samples.
 * 2. A change only counts once it clears [ELEVATION_GAIN_MIN_DELTA_M].
 *
 * Callers must pass the raw track. Running this over an RDP-simplified
 * polyline reads a hill as flat: RDP measures perpendicular distance in 2-D
 * only, so a straight road over a summit collapses to its endpoints and the
 * climb between them disappears.
 */
export function computeElevationGain(track: LatLng[]): number {
	let gain = 0;
	let ref: number | null = null;
	for (const p of track) {
		const ele = p.ele;
		if (ele == null) continue;
		if (ref == null) {
			ref = ele;
			continue;
		}
		const delta = ele - ref;
		if (delta >= ELEVATION_GAIN_MIN_DELTA_M) {
			gain += delta;
			ref = ele;
		} else if (delta <= -ELEVATION_GAIN_MIN_DELTA_M) {
			// A real descent — move the reference down so the next climb is
			// measured from the valley, not from the previous summit.
			ref = ele;
		}
	}
	return gain;
}

export interface RouteSummary {
	/** Simplified waypoints, ready to drop into `routes.waypoints`. */
	waypoints: LatLng[];
	/** Equirectangular distance summed over the simplified polyline. */
	distance_m: number;
	/** Positive elevation change over the RAW track — see computeElevationGain. */
	elevation_m: number;
}

/**
 * Turn a raw GPS track from a run into the three numbers a `routes`
 * row needs: simplified waypoints, distance, elevation gain.
 *
 * Equirectangular distance is close enough at running scales (sub-1 %
 * error vs haversine for sub-100 km separations) and matches the
 * Android save-as-route path. Used by `saveRunAsRoute` so the inline
 * arithmetic is testable in isolation.
 */
export function summarizeRouteFromTrack(
	track: LatLng[],
	epsilonMetres = 10,
): RouteSummary {
	const simplified = simplifyTrack(track, epsilonMetres);
	const waypoints = simplified.map((p) => ({
		lat: p.lat,
		lng: p.lng,
		...(p.ele != null ? { ele: p.ele } : {}),
	}));
	let distance = 0;
	for (let i = 1; i < simplified.length; i++) {
		const a = simplified[i - 1];
		const b = simplified[i];
		const dLat = ((b.lat - a.lat) * Math.PI) / 180;
		const dLng = ((b.lng - a.lng) * Math.PI) / 180;
		const midLat = (((a.lat + b.lat) / 2) * Math.PI) / 180;
		const x = dLng * Math.cos(midLat);
		const y = dLat;
		distance += Math.sqrt(x * x + y * y) * 6_371_000;
	}
	return {
		waypoints,
		distance_m: distance,
		// Gain comes off the RAW track. Measuring it over `simplified` read a
		// hill as flat — RDP works in 2-D, so a straight road over a summit
		// collapses to its endpoints and the climb between them vanished.
		elevation_m: computeElevationGain(track),
	};
}
