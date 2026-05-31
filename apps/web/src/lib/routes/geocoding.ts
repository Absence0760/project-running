import { dev } from '$app/environment';
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

// audit/third-party-data-flows (2026-05-25): a missing
// PUBLIC_MAPTILER_KEY in production silently falls through to
// Nominatim (OSM Foundation, no DPA, dev-only). Warn loudly once on
// first call so the misconfig surfaces in Sentry / browser logs
// rather than slipping past unnoticed. We don't throw — search must
// stay functional for the user — but the operator sees a clear
// signal. Dev builds skip the warn so a Protomaps-only local stack
// stays quiet.
let warnedAboutNominatimFallback = false;
function warnIfFallbackInProd(): void {
	if (warnedAboutNominatimFallback) return;
	if (dev) return;
	if (PUBLIC_MAPTILER_KEY.length > 0) return;
	warnedAboutNominatimFallback = true;
	console.warn(
		'[geocoding] PUBLIC_MAPTILER_KEY is empty in a production build — ' +
			'place search will fall back to Nominatim (OSM Foundation). ' +
			'Nominatim has no DPA on the free tier; production traffic ' +
			'must use a contracted provider. See audit/third-party-data-flows ' +
			'(2026-05-25) and infra/sops-init for the secret rotation flow.',
	);
}

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
	warnIfFallbackInProd();
	return searchPlacesWithKey(PUBLIC_MAPTILER_KEY, query, limit, signal);
}

/// Geocodes a free-text place query to a single best-fit centroid +
/// radius. Returns null when the query is too short, no provider
/// yields a hit, or the request fails. Callers should treat null as
/// "fall back to the text-only search path" — never as an error.
///
/// Thin env-binding wrapper around `geocodePlaceWithKey`.
export function geocodePlace(query: string, signal?: AbortSignal) {
	warnIfFallbackInProd();
	return geocodePlaceWithKey(PUBLIC_MAPTILER_KEY, query, signal);
}
