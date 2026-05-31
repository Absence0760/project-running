// Privacy zones — geofences clipped from the start and end of any
// track rendered on a public surface. Decisions §33 covers the why
// and the known v1 gaps (notably routes.start_point, which is set
// server-side by trigger and is unaware of the owner's zones).
//
// Pure functions. Unit-testable. No Svelte / Supabase dependencies.

export interface PrivacyZone {
	lat: number;
	lng: number;
	radius_m: number;
}

export interface LatLng {
	lat: number;
	lng: number;
}

export const PRIVACY_ZONES_KEY = 'privacy_zones';

/// Returns true when `point` is within any of `zones` by haversine
/// distance. Empty zone list -> always false.
export function isInAnyZone(point: LatLng, zones: PrivacyZone[]): boolean {
	for (const z of zones) {
		if (haversineMetres(point.lat, point.lng, z.lat, z.lng) <= z.radius_m) return true;
	}
	return false;
}

/// Walk forward from index 0 and drop points in any zone; walk
/// backward from the end with the same predicate; keep the
/// contiguous middle. We deliberately don't slice out *interior*
/// in-zone segments (e.g. a loop that returns home mid-run and
/// leaves again) because (a) the leak we're protecting is "where
/// you live," not "where you've ever been," and (b) gapping the
/// polyline mid-track looks broken.
///
/// When the result would be empty (every point is in a zone), we
/// return an empty array — callers should render no polyline at all
/// rather than a single point that gives the location away.
export function clipPointsToZones<T extends LatLng>(points: T[], zones: PrivacyZone[]): T[] {
	if (zones.length === 0 || points.length === 0) return points;

	let start = 0;
	while (start < points.length && isInAnyZone(points[start], zones)) start++;
	if (start >= points.length) return [];

	let end = points.length - 1;
	while (end > start && isInAnyZone(points[end], zones)) end--;

	return points.slice(start, end + 1);
}

/// Great-circle distance between two lat/lng points, in metres.
function haversineMetres(lat1: number, lng1: number, lat2: number, lng2: number): number {
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
