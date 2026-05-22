// Pure math + env-free geocoding helpers. Split out from
// `geocoding.ts` (which binds to the SvelteKit `$env/dynamic/public`
// runtime) so node:test can import these without setting up Vite.
// `geocoding.ts` re-exports thin wrappers that inject the env-read
// key.

export interface PlaceSearchResult {
	name: string;
	lng: number;
	lat: number;
}

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

/// Provider-selecting search dispatcher. Pure in that it takes the
/// MapTiler key as a parameter rather than reading from `$env`; that
/// makes the network-mocked path testable from `node:test`.
///
/// When [maptilerKey] is non-empty (production / paid path), routes
/// through MapTiler. Otherwise falls back to Nominatim (OSM's free
/// public geocoder) so a Protomaps-only dev stack still has a
/// working search box. See `decisions.md § 68` for the design.
export async function searchPlacesWithKey(
	maptilerKey: string,
	query: string,
	limit = 5,
	signal?: AbortSignal,
): Promise<PlaceSearchResult[]> {
	const trimmed = query.trim();
	if (trimmed.length < 2) return [];
	if (maptilerKey.length > 0) {
		return searchViaMapTiler(maptilerKey, trimmed, limit, signal);
	}
	return searchViaNominatim(trimmed, limit, signal);
}

async function searchViaMapTiler(
	key: string,
	query: string,
	limit: number,
	signal?: AbortSignal,
): Promise<PlaceSearchResult[]> {
	const url = `https://api.maptiler.com/geocoding/${encodeURIComponent(query)}.json?key=${key}&limit=${limit}`;
	let res: Response;
	try {
		res = await fetch(url, { signal });
	} catch (_) {
		return [];
	}
	if (!res.ok) return [];
	const body = (await res.json()) as {
		features?: Array<{
			place_name?: string;
			text?: string;
			center?: [number, number];
		}>;
	};
	const features = body.features ?? [];
	const out: PlaceSearchResult[] = [];
	for (const f of features) {
		if (!f.center) continue;
		out.push({
			name: f.place_name ?? f.text ?? '',
			lng: f.center[0],
			lat: f.center[1],
		});
	}
	return out;
}

async function searchViaNominatim(
	query: string,
	limit: number,
	signal?: AbortSignal,
): Promise<PlaceSearchResult[]> {
	// Public Nominatim's usage policy requires a meaningful UA — see
	// https://operations.osmfoundation.org/policies/nominatim/.
	// Production deployments at any scale should self-host or use a
	// paid alternative; this fallback is for dev only.
	const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=${limit}&addressdetails=0`;
	let res: Response;
	try {
		res = await fetch(url, {
			signal,
			headers: typeof navigator !== 'undefined' && navigator.language
				? { 'Accept-Language': navigator.language }
				: undefined,
		});
	} catch (_) {
		return [];
	}
	if (!res.ok) return [];
	const body = (await res.json()) as Array<{
		display_name?: string;
		lat?: string;
		lon?: string;
	}>;
	const out: PlaceSearchResult[] = [];
	for (const f of body) {
		const lat = f.lat ? parseFloat(f.lat) : NaN;
		const lng = f.lon ? parseFloat(f.lon) : NaN;
		if (!isFinite(lat) || !isFinite(lng)) continue;
		out.push({
			name: f.display_name ?? `${lat.toFixed(3)}, ${lng.toFixed(3)}`,
			lng,
			lat,
		});
	}
	return out;
}
