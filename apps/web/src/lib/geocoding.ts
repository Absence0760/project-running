import { env } from '$env/dynamic/public';

const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';

import { bboxRadius } from './geocoding_math';

/// A geocoded place — the centroid the user's search resolved to, plus
/// a radius in metres derived from the place's bounding box. Used by
/// the clubs region-search flow to pass a `(lat, lng, radius_m)` into
/// `search_clubs` so a query like "Virginia" pulls clubs in Virginia
/// even when their `location_label` is "Richmond, VA" without the
/// state name spelled out. See [migration 20260905_001].
export interface GeocodedPlace {
	name: string;
	center: { lng: number; lat: number };
	radiusM: number;
	/// MapTiler's `place_type[0]` — `country`, `region`, `municipality`,
	/// `address`, `poi`, etc. Lets callers pick a different radius
	/// strategy (e.g. clamp to a smaller circle for `address` vs
	/// `region`) if MapTiler's bbox is implausibly wide.
	placeType: string | null;
}

// Re-export the env-free result shape + the dispatcher's testable
// counterpart so callers have one import surface. The thin wrapper
// below injects PUBLIC_MAPTILER_KEY so production sites don't have
// to repeat the env read.
export type { PlaceSearchResult } from './geocoding_math';
import { searchPlacesWithKey } from './geocoding_math';

/// Search free-text places, return up to [limit] hits suitable for a
/// search-box dropdown. Returns an empty array — never throws — when
/// the query is too short or all providers fail.
///
/// Thin env-binding wrapper around `searchPlacesWithKey` in
/// `geocoding_math.ts`. See that helper for provider priority +
/// trade-offs.
export function searchPlaces(
	query: string,
	limit = 5,
	signal?: AbortSignal,
) {
	return searchPlacesWithKey(PUBLIC_MAPTILER_KEY, query, limit, signal);
}

/// Geocodes a free-text place query via MapTiler. Returns null when
/// the query is too short, MapTiler returns no features, or the key
/// isn't configured. Callers should treat null as "fall back to the
/// text-only search path" — never as an error.
export async function geocodePlace(
	query: string,
	signal?: AbortSignal,
): Promise<GeocodedPlace | null> {
	const trimmed = query.trim();
	if (trimmed.length < 2) return null;
	if (!PUBLIC_MAPTILER_KEY) return null;

	const url = `https://api.maptiler.com/geocoding/${encodeURIComponent(trimmed)}.json?key=${PUBLIC_MAPTILER_KEY}&limit=1`;
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
	// MapTiler may return a feature without a bbox (rare — usually
	// address-level POIs). Fall back to a small radius so the search
	// still uses the centroid but doesn't sweep half a continent.
	const radiusM = top.bbox ? bboxRadius(top.bbox, center) : 5000;

	return {
		name: top.place_name ?? top.text ?? trimmed,
		center,
		radiusM,
		placeType,
	};
}
