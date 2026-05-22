import { env } from '$env/dynamic/public';

import {
	geocodePlaceWithKey,
	searchPlacesWithKey,
} from './geocoding_math';

// Re-export the env-free result shapes + the dispatchers' testable
// counterparts so callers have one import surface. The thin wrappers
// below inject PUBLIC_MAPTILER_KEY so production sites don't have to
// repeat the env read.
export type { GeocodedPlace, PlaceSearchResult } from './geocoding_math';

const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';

/// Search free-text places, return up to [limit] hits suitable for a
/// search-box dropdown. Returns an empty array — never throws — when
/// the query is too short or all providers fail.
///
/// Thin env-binding wrapper around `searchPlacesWithKey`. See that
/// helper for provider priority + trade-offs.
export function searchPlaces(
	query: string,
	limit = 5,
	signal?: AbortSignal,
) {
	return searchPlacesWithKey(PUBLIC_MAPTILER_KEY, query, limit, signal);
}

/// Geocodes a free-text place query to a single best-fit centroid +
/// radius. Returns null when the query is too short, no provider
/// yields a hit, or the request fails. Callers should treat null as
/// "fall back to the text-only search path" — never as an error.
///
/// Thin env-binding wrapper around `geocodePlaceWithKey`.
export function geocodePlace(query: string, signal?: AbortSignal) {
	return geocodePlaceWithKey(PUBLIC_MAPTILER_KEY, query, signal);
}
