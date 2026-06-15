/**
 * Snap a dropped point to a route's polyline.
 *
 * Course markers (aid stations, cutoffs, …) are anchored to the course, so
 * the marker editor lets the owner drop / drag a pin and "stick it to the
 * route line". This is the pure projection behind that: given a clicked
 * lng/lat and the route's polyline, return the nearest point ON the line —
 * the perpendicular foot on the closest segment, not merely the nearest
 * vertex — plus where along the route it lands.
 *
 * `position_m` for a saved marker is still derived authoritatively
 * server-side (ST_LineLocatePoint against routes.geom, migration
 * 20270129_001), so `alongM` here is a client-side preview only — it lets
 * the editor show an approximate distance while dragging without a round
 * trip. The snapped lng/lat is what makes the pin render exactly on the
 * line.
 *
 * Pure + unit-tested (route_snap.test.ts). Mobile mirror tracked in
 * followups.md (the Flutter marker panel taps to place but does not snap
 * or drag yet).
 */

export interface SnapResult {
	/** Snapped longitude — on the polyline. */
	lng: number;
	/** Snapped latitude — on the polyline. */
	lat: number;
	/** Index `i` of the segment `[coords[i], coords[i+1]]` the point fell on. */
	segmentIndex: number;
	/** Fraction in [0,1] along that segment to the foot of the projection. */
	t: number;
	/** Cumulative distance from the route start to the snapped point, metres. */
	alongM: number;
	/** Perpendicular distance from the input point to the line, metres. */
	offsetM: number;
}

const R = 6_371_000;
const toRad = (d: number) => (d * Math.PI) / 180;

function haversine(aLng: number, aLat: number, bLng: number, bLat: number): number {
	const dLat = toRad(bLat - aLat);
	const dLng = toRad(bLng - aLng);
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const h =
		sinLat * sinLat + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * sinLng * sinLng;
	return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/**
 * Project `point` onto the polyline `coords` ([lng, lat] pairs) and return
 * the nearest on-line point. Returns null when the polyline has fewer than
 * two points (nothing to snap to). Projection is done in a local
 * equirectangular frame around each segment — accurate to well within a
 * metre at the scale a marker is dropped, and dependency-free.
 */
export function snapToPolyline(
	point: { lng: number; lat: number },
	coords: [number, number][]
): SnapResult | null {
	if (!coords || coords.length < 2) return null;
	if (!Number.isFinite(point.lng) || !Number.isFinite(point.lat)) return null;

	let best: SnapResult | null = null;
	let bestOffset = Infinity;
	// Running cumulative distance to the START of the current segment.
	let cumulative = 0;

	for (let i = 0; i < coords.length - 1; i++) {
		const [aLng, aLat] = coords[i];
		const [bLng, bLat] = coords[i + 1];
		const segLen = haversine(aLng, aLat, bLng, bLat);

		// Local planar frame: metres east/north of segment start `a`,
		// with longitude scaled by cos(lat) so a degree of lng matches a
		// degree of lat in ground distance.
		const cosLat = Math.cos(toRad(aLat));
		const ax = 0;
		const ay = 0;
		const bx = toRad(bLng - aLng) * R * cosLat;
		const by = toRad(bLat - aLat) * R;
		const px = toRad(point.lng - aLng) * R * cosLat;
		const py = toRad(point.lat - aLat) * R;

		const dx = bx - ax;
		const dy = by - ay;
		const lenSq = dx * dx + dy * dy;
		// Degenerate (duplicate) vertices → treat as the start point.
		const t = lenSq > 0 ? Math.max(0, Math.min(1, (px * dx + py * dy) / lenSq)) : 0;

		const sLng = aLng + (bLng - aLng) * t;
		const sLat = aLat + (bLat - aLat) * t;
		const offset = haversine(point.lng, point.lat, sLng, sLat);

		if (offset < bestOffset) {
			bestOffset = offset;
			best = {
				lng: sLng,
				lat: sLat,
				segmentIndex: i,
				t,
				alongM: cumulative + segLen * t,
				offsetM: offset
			};
		}
		cumulative += segLen;
	}

	return best;
}
