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

export interface GeocodedPlace {
	name: string;
	center: { lng: number; lat: number };
	radiusM: number;
	placeType: string | null;
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

/// Env-free counterpart to `geocodePlace` in `geocoding.ts`.
/// Takes the MapTiler key as a parameter so node:test can drive it
/// without setting up Vite + `$env/dynamic/public`. See
/// `geocoding.ts` for the production-shape wrapper.
export async function geocodePlaceWithKey(
	maptilerKey: string,
	query: string,
	signal?: AbortSignal,
): Promise<GeocodedPlace | null> {
	const trimmed = query.trim();
	if (trimmed.length < 2) return null;
	if (maptilerKey.length > 0) {
		return geocodeViaMapTiler(maptilerKey, trimmed, signal);
	}
	return geocodeViaNominatim(trimmed, signal);
}

async function geocodeViaMapTiler(
	key: string,
	trimmed: string,
	signal?: AbortSignal,
): Promise<GeocodedPlace | null> {
	const url = `https://api.maptiler.com/geocoding/${encodeURIComponent(trimmed)}.json?key=${key}&limit=1`;
	let res: Response;
	try {
		res = await fetch(url, { signal });
	} catch (_) {
		return null;
	}
	if (!res.ok) return null;
	const body = (await res.json()) as {
		features?: Array<{
			place_name?: string;
			text?: string;
			center?: [number, number];
			bbox?: [number, number, number, number];
			place_type?: string[];
		}>;
	};
	const top = body.features?.[0];
	if (!top?.center) return null;
	const center = { lng: top.center[0], lat: top.center[1] };
	const placeType = top.place_type?.[0] ?? null;
	const radiusM = top.bbox ? bboxRadius(top.bbox, center) : 5000;
	return {
		name: top.place_name ?? top.text ?? trimmed,
		center,
		radiusM,
		placeType,
	};
}

async function geocodeViaNominatim(
	trimmed: string,
	signal?: AbortSignal,
): Promise<GeocodedPlace | null> {
	const params = new URLSearchParams({
		q: trimmed,
		format: 'json',
		limit: '1',
		addressdetails: '0',
		email: 'protomaps-dev@localhost',
	});
	const url = `https://nominatim.openstreetmap.org/search?${params.toString()}`;
	let res: Response;
	try {
		res = await fetch(url, {
			signal,
			headers: typeof navigator !== 'undefined' && navigator.language
				? { 'Accept-Language': navigator.language }
				: undefined,
		});
	} catch (_) {
		return null;
	}
	if (!res.ok) return null;
	const body = (await res.json()) as Array<{
		display_name?: string;
		lat?: string;
		lon?: string;
		boundingbox?: [string, string, string, string];
		type?: string;
		class?: string;
	}>;
	const top = body[0];
	if (!top?.lat || !top.lon) return null;
	const lat = parseFloat(top.lat);
	const lng = parseFloat(top.lon);
	if (!isFinite(lat) || !isFinite(lng)) return null;
	const center = { lng, lat };
	let radiusM = 5000;
	if (top.boundingbox && top.boundingbox.length === 4) {
		const [s, n, w, e] = top.boundingbox.map(parseFloat);
		if (isFinite(s) && isFinite(n) && isFinite(w) && isFinite(e)) {
			radiusM = bboxRadius([w, s, e, n], center);
		}
	}
	return {
		name: top.display_name ?? trimmed,
		center,
		radiusM,
		placeType:
			top.class === 'boundary' && top.type === 'administrative'
				? 'region'
				: null,
	};
}

/// Nominatim's usage policy is strict — see
/// https://operations.osmfoundation.org/policies/nominatim/. The two
/// load-bearing requirements at dev volumes:
///
///   - Meaningful `User-Agent` header (no `Mozilla/5.0` blanket).
///     Browsers send one automatically, but it's the default browser
///     UA which Nominatim has been known to deny. Setting an explicit
///     `User-Agent` from JavaScript isn't possible (browsers forbid
///     it); the next-best signal Nominatim accepts is a descriptive
///     `Referer` header (which the browser sends automatically) plus
///     the `email` query parameter as a contact path.
///
///   - No bulk requests (~1 req/sec). The 300ms debounce on every
///     search call site is the back-pressure.
///
/// We include the `email` parameter — Nominatim treats it as the
/// usage-policy contact channel. Empty string is fine; the parameter
/// being present tells them "this is a real client that read the
/// policy" and they ban it less aggressively than UA-less traffic.
///
/// Production deployments at any scale should self-host or use a
/// paid alternative; this fallback is dev-only.
const NOMINATIM_BASE = 'https://nominatim.openstreetmap.org/search';

async function searchViaNominatim(
	query: string,
	limit: number,
	signal?: AbortSignal,
): Promise<PlaceSearchResult[]> {
	const params = new URLSearchParams({
		q: query,
		format: 'json',
		limit: String(limit),
		addressdetails: '0',
		// Tells Nominatim "I read the policy" — see comment above.
		email: 'protomaps-dev@localhost',
	});
	const url = `${NOMINATIM_BASE}?${params.toString()}`;
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
