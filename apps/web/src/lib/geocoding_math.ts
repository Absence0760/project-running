// Pure math helpers for the clubs region-search geocoding flow.
// Split out from `geocoding.ts` (which fetches MapTiler with the
// PUBLIC_MAPTILER_KEY env var) so node:test can import these without
// the SvelteKit `$env/static/public` runtime.

export function haversineM(
	a: { lng: number; lat: number },
	b: { lng: number; lat: number },
): number {
	const R = 6371000;
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(b.lat - a.lat);
	const dLng = toRad(b.lng - a.lng);
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const h =
		sinLat * sinLat +
		Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
	return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

// Maximum distance in metres from a bbox centroid to one of its four
// corners — used as the search radius for region matches. For
// "Virginia" this is ~470 km; for "Richmond, VA" ~30 km; for a
// specific address it collapses to a few hundred metres.
export function bboxRadius(
	bbox: [number, number, number, number],
	center: { lng: number; lat: number },
): number {
	const [w, s, e, n] = bbox;
	const corners: [number, number][] = [
		[w, s],
		[w, n],
		[e, s],
		[e, n],
	];
	return Math.max(...corners.map(([lng, lat]) => haversineM(center, { lng, lat })));
}
