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

/// Whether a provider's answer is a latitude at all.
///
/// The same contract `RouteParser._isUsableLat` applies to a coordinate out of
/// a file, and the one `geocoding.dart`'s `isUsableLatitude` applies on the
/// phone (decisions § 1011). A non-finite coordinate is not a place: it reaches
/// a MapLibre camera as a view that silently stops rendering and `JSON.
/// stringify` writes it as `null`, so a route saved around it carries a hole
/// rather than an error. And the range is not a heuristic — a latitude is +/-90
/// by definition, so a value outside it is a malformed answer, not a place.
///
/// BOTH providers need it. Nominatim serialises coordinates as STRINGS and
/// `parseFloat('NaN')` is NaN rather than a parse failure, so a null check does
/// not see it. MapTiler sends JSON numbers, which cannot spell NaN — but
/// `JSON.parse('1e400')` is `Infinity`, so a declared `[number, number]` does
/// not save that branch either: the type is a claim about the wire that the
/// wire never made.
export function isUsableLatitude(v: unknown): v is number {
	return typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= 90;
}

/// Longitude half of `isUsableLatitude`. Separate bound, same contract.
export function isUsableLongitude(v: unknown): v is number {
	return typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= 180;
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

/// Why the search dispatcher reports an outcome rather than a bare
/// list: a provider that is down, rate-limited, or unreachable used to
/// collapse into `[]`, which every call site renders identically to
/// "this place does not exist" — and because each dropdown only opens
/// on a non-empty result set, a failed search actually produced NO
/// feedback at all. A runner typing a real place name on a flaky
/// connection was told nothing. The honest states are three, so the
/// type carries three.
///
/// `aborted` exists so the fix does not trade silence for noise: the
/// call sites debounce and supersede in-flight lookups, and a
/// superseded keystroke must leave the dropdown exactly as it was
/// rather than flashing an error the user never caused.
export type PlaceSearchOutcome =
	| { status: 'ok'; results: PlaceSearchResult[] }
	| { status: 'unavailable' }
	| { status: 'aborted' };

/// A rejected `fetch` is either the caller superseding its own request
/// or the network genuinely failing, and only the second is the user's
/// problem. `signal.aborted` is checked alongside the `AbortError` name
/// because a mocked fetch in node:test rejects with a plain Error.
function abortedOutcome(e: unknown, signal?: AbortSignal): boolean {
	return signal?.aborted === true || (e as { name?: string } | null)?.name === 'AbortError';
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
): Promise<PlaceSearchOutcome> {
	const trimmed = query.trim();
	// Too short to search is not a failure — it is an empty result the
	// caller renders as nothing at all.
	if (trimmed.length < 2) return { status: 'ok', results: [] };
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
): Promise<PlaceSearchOutcome> {
	const url = `https://api.maptiler.com/geocoding/${encodeURIComponent(query)}.json?key=${key}&limit=${limit}`;
	let res: Response;
	try {
		res = await fetch(url, { signal });
	} catch (e) {
		return abortedOutcome(e, signal) ? { status: 'aborted' } : { status: 'unavailable' };
	}
	if (!res.ok) return { status: 'unavailable' };
	let body: {
		features?: Array<{
			place_name?: string;
			text?: string;
			center?: [number, number];
		}>;
	};
	try {
		body = await res.json();
	} catch (e) {
		// A 200 carrying a truncated or non-JSON body is still a failed
		// search, not an empty one.
		return abortedOutcome(e, signal) ? { status: 'aborted' } : { status: 'unavailable' };
	}
	const features = body.features ?? [];
	const out: PlaceSearchResult[] = [];
	for (const f of features) {
		const center = f.center;
		if (!Array.isArray(center)) continue;
		const [lng, lat] = center;
		if (!isUsableLongitude(lng) || !isUsableLatitude(lat)) continue;
		out.push({
			name: f.place_name ?? f.text ?? '',
			lng,
			lat,
		});
	}
	return { status: 'ok', results: out };
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
	let body: {
		features?: Array<{
			place_name?: string;
			text?: string;
			center?: [number, number];
			bbox?: [number, number, number, number];
			place_type?: string[];
		}>;
	};
	try {
		// A 200 carrying a truncated or non-JSON body is a failed geocode, and
		// this function's contract is to return null on one — not to throw out
		// of a call site whose only handling is the null branch.
		body = await res.json();
	} catch (_) {
		return null;
	}
	const top = body.features?.[0];
	const raw = top?.center;
	if (!Array.isArray(raw)) return null;
	const [lng, lat] = raw;
	if (!isUsableLongitude(lng) || !isUsableLatitude(lat)) return null;
	const center = { lng, lat };
	const placeType = top?.place_type?.[0] ?? null;
	// A bbox with one unusable corner yields a NaN radius, and NaN compares
	// false against every bound a caller might check it with — so the whole
	// bbox is either usable or it is the default, exactly as the Nominatim
	// branch already treats its own.
	const bbox = top?.bbox;
	const usableBbox =
		Array.isArray(bbox) &&
		bbox.length === 4 &&
		isUsableLongitude(bbox[0]) &&
		isUsableLatitude(bbox[1]) &&
		isUsableLongitude(bbox[2]) &&
		isUsableLatitude(bbox[3]);
	const radiusM = usableBbox ? bboxRadius(bbox, center) : 5000;
	return {
		name: top?.place_name ?? top?.text ?? trimmed,
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
		email: 'privacy@threkir.com',
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
	if (!isUsableLatitude(lat) || !isUsableLongitude(lng)) return null;
	const center = { lng, lat };
	let radiusM = 5000;
	if (top.boundingbox && top.boundingbox.length === 4) {
		const [s, n, w, e] = top.boundingbox.map(parseFloat);
		if (
			isUsableLatitude(s) &&
			isUsableLatitude(n) &&
			isUsableLongitude(w) &&
			isUsableLongitude(e)
		) {
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
/// usage-policy contact channel. The address must be reachable so
/// OSM can contact the operator about abuse / takedown — sending a
/// placeholder violates the usage policy. See
/// audit/third-party-data-flows (2026-05-25).
///
/// Production deployments at any scale should self-host or use a
/// paid alternative; this fallback is dev-only.
const NOMINATIM_BASE = 'https://nominatim.openstreetmap.org/search';

async function searchViaNominatim(
	query: string,
	limit: number,
	signal?: AbortSignal,
): Promise<PlaceSearchOutcome> {
	const params = new URLSearchParams({
		q: query,
		format: 'json',
		limit: String(limit),
		addressdetails: '0',
		// Tells Nominatim "I read the policy" — see comment above.
		email: 'privacy@threkir.com',
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
	} catch (e) {
		return abortedOutcome(e, signal) ? { status: 'aborted' } : { status: 'unavailable' };
	}
	// Nominatim answers an over-rate request with 429 — exactly the case
	// that must read as "search unavailable", never as "no such place".
	if (!res.ok) return { status: 'unavailable' };
	let body: Array<{
		display_name?: string;
		lat?: string;
		lon?: string;
	}>;
	try {
		body = await res.json();
	} catch (e) {
		return abortedOutcome(e, signal) ? { status: 'aborted' } : { status: 'unavailable' };
	}
	const out: PlaceSearchResult[] = [];
	for (const f of body) {
		const lat = f.lat ? parseFloat(f.lat) : NaN;
		const lng = f.lon ? parseFloat(f.lon) : NaN;
		if (!isUsableLatitude(lat) || !isUsableLongitude(lng)) continue;
		out.push({
			name: f.display_name ?? `${lat.toFixed(3)}, ${lng.toFixed(3)}`,
			lng,
			lat,
		});
	}
	return { status: 'ok', results: out };
}
