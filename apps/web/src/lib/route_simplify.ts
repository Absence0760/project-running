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
 * Total positive elevation change across the polyline, in metres.
 * Waypoints without elevation readings are skipped. Mirrors the Dart
 * `computeElevationGain` in `route_simplify.dart`.
 */
export function computeElevationGain(track: LatLng[]): number {
	let gain = 0;
	for (let i = 1; i < track.length; i++) {
		const prev = track[i - 1].ele;
		const curr = track[i].ele;
		if (prev != null && curr != null && curr > prev) {
			gain += curr - prev;
		}
	}
	return gain;
}
