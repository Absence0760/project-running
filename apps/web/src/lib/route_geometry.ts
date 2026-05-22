/**
 * Pure geometry helpers for displaying a planned polyline. TS twin
 * of `apps/mobile_android/lib/route_geometry.dart` — kept in lockstep
 * so the route-detail scrubber renders identical positions on both
 * platforms. Add to the parity-pair list in CLAUDE.md if you grow
 * this module.
 */
export interface RouteWaypoint {
	lat: number;
	lng: number;
	elevation_m?: number | null;
}

/**
 * Interpolate the position along `waypoints` at the given normalized
 * `fraction` (0.0 = start, 1.0 = end). Returns null when the polyline
 * is too short to interpolate (`< 2` waypoints).
 *
 * Distance-weighted — a long segment between two waypoints takes
 * proportionally more of the scrubber's range than a short segment,
 * so dragging at constant speed feels like dragging the runner at a
 * constant pace along the route.
 *
 * Used by the route-detail page's scrubber slider: the slider emits
 * a 0..1 value as the user drags from start to finish, this helper
 * produces the lat/lng to render the "runner" pulse on the map.
 */
export function interpolateAlongRoute(
	waypoints: RouteWaypoint[],
	fraction: number,
): RouteWaypoint | null {
	if (waypoints.length < 2) return null;
	const f = Math.min(1, Math.max(0, fraction));
	const totalLen = cumulativeLengthM(waypoints);
	if (totalLen <= 0) {
		// Degenerate — all coincident. Snap to start.
		return waypoints[0];
	}
	const target = totalLen * f;
	let seen = 0;
	for (let i = 1; i < waypoints.length; i++) {
		const a = waypoints[i - 1];
		const b = waypoints[i];
		const segLen = haversineM(a.lat, a.lng, b.lat, b.lng);
		if (segLen <= 0) continue;
		const segEnd = seen + segLen;
		if (target <= segEnd || i === waypoints.length - 1) {
			const localT = Math.min(1, Math.max(0, (target - seen) / segLen));
			return {
				lat: a.lat + (b.lat - a.lat) * localT,
				lng: a.lng + (b.lng - a.lng) * localT,
				elevation_m: lerpNullable(
					a.elevation_m ?? null,
					b.elevation_m ?? null,
					localT,
				),
			};
		}
		seen = segEnd;
	}
	return waypoints[waypoints.length - 1];
}

/**
 * Total polyline length in metres via cumulative haversine. Cheap
 * O(n) — matches the recorder + run-stats helpers elsewhere in the
 * app.
 */
export function polylineLengthMetres(waypoints: RouteWaypoint[]): number {
	return cumulativeLengthM(waypoints);
}

function cumulativeLengthM(waypoints: RouteWaypoint[]): number {
	let total = 0;
	for (let i = 1; i < waypoints.length; i++) {
		const a = waypoints[i - 1];
		const b = waypoints[i];
		total += haversineM(a.lat, a.lng, b.lat, b.lng);
	}
	return total;
}

function haversineM(
	lat1: number,
	lng1: number,
	lat2: number,
	lng2: number,
): number {
	const r = 6_371_000;
	const deg = Math.PI / 180;
	const dLat = (lat2 - lat1) * deg;
	const dLng = (lng2 - lng1) * deg;
	const a =
		Math.sin(dLat / 2) * Math.sin(dLat / 2) +
		Math.cos(lat1 * deg) *
			Math.cos(lat2 * deg) *
			Math.sin(dLng / 2) *
			Math.sin(dLng / 2);
	return r * 2 * Math.asin(Math.min(1, Math.sqrt(a)));
}

function lerpNullable(
	a: number | null,
	b: number | null,
	t: number,
): number | null {
	if (a === null && b === null) return null;
	if (a === null) return b;
	if (b === null) return a;
	return a + (b - a) * t;
}
