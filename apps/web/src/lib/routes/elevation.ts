// The localStorage key `consent.svelte.ts` persists the cookie-banner
// choice under. Duplicated here (not imported) because `consent.svelte.ts`
// uses Svelte runes ($state) and so can't be loaded by the tsx unit runner
// that exercises this module.
const CONSENT_STORAGE_KEY = 'cookie_consent';

/**
 * True only when the visitor has accepted the cookie banner. Open-Meteo
 * receives every coordinate we look up — a route often starts at the
 * user's home — plus the requester's IP, so it is a third-party
 * personal-data hop that ePrivacy Art 5(3) / GDPR require consent for
 * before it fires (audit/third-party-data-flows, audit/cookie-consent).
 *
 * Reads the SAME localStorage signal the map components' `hasAcceptedConsent`
 * reads, so the elevation lookup and the MapTiler basemap gate honour one
 * banner choice. Fail-closed: no browser / no accepted record → no lookup.
 */
function elevationConsentGiven(): boolean {
	if (typeof localStorage === 'undefined') return false;
	try {
		const raw = localStorage.getItem(CONSENT_STORAGE_KEY);
		if (!raw) return false;
		const parsed = JSON.parse(raw) as { choice?: string };
		return parsed?.choice === 'accepted';
	} catch {
		return false;
	}
}

/**
 * Fetch elevation data for a list of coordinates using the Open-Meteo API.
 * Free, no API key required, rate-limited to reasonable usage.
 * Returns elevations in metres for each coordinate.
 *
 * Gated on consent (see `elevationConsentGiven`): without it we skip the
 * network entirely and return zeros, so the route still saves — just
 * without an elevation profile — and no coordinates/IP leave the browser.
 */
export async function fetchElevations(
	coordinates: [number, number][]
): Promise<number[]> {
	if (coordinates.length === 0) return [];

	// Fail-closed third-party gate. Return the same all-zero shape the
	// outage fallback below uses so every caller degrades identically.
	if (!elevationConsentGiven()) {
		return coordinates.map(() => 0);
	}

	// Open-Meteo accepts up to ~100 points per request, batch if needed
	const batchSize = 100;
	const results: number[] = [];

	for (let i = 0; i < coordinates.length; i += batchSize) {
		const batch = coordinates.slice(i, i + batchSize);
		const lats = batch.map(([, lat]) => lat).join(',');
		const lngs = batch.map(([lng]) => lng).join(',');

		const url = `https://api.open-meteo.com/v1/elevation?latitude=${lats}&longitude=${lngs}`;
		// 8s per-batch ceiling. RouteBuilder calls this inside its
		// generate-loop iteration — without a client-side timeout an
		// Open-Meteo outage pins the whole iteration's promise and the
		// "Calculating route…" spinner can't recover. Zeros-on-failure
		// is preferable to a hung UI; the route still saves, the user
		// just doesn't get an elevation profile.
		let res: Response;
		try {
			res = await fetch(url, { signal: AbortSignal.timeout(8000) });
		} catch {
			results.push(...batch.map(() => 0));
			continue;
		}

		if (!res.ok) {
			// Fall back to zeros if elevation service is unavailable
			results.push(...batch.map(() => 0));
			continue;
		}

		const data: { elevation: number[] } = await res.json();
		results.push(...data.elevation);
	}

	return results;
}

/**
 * Calculate total elevation gain from an array of elevation values.
 */
export function calculateElevationGain(elevations: number[]): number {
	let gain = 0;
	for (let i = 1; i < elevations.length; i++) {
		const diff = elevations[i] - elevations[i - 1];
		if (diff > 0) gain += diff;
	}
	return Math.round(gain);
}

/**
 * Sample coordinates at regular intervals for elevation lookup.
 * No need to look up elevation for every single GPS point.
 */
export function sampleCoordinates(
	coordinates: [number, number][],
	maxPoints: number = 100
): { sampled: [number, number][]; indices: number[] } {
	if (coordinates.length <= maxPoints) {
		return {
			sampled: coordinates,
			indices: coordinates.map((_, i) => i)
		};
	}

	const step = (coordinates.length - 1) / (maxPoints - 1);
	const sampled: [number, number][] = [];
	const indices: number[] = [];

	for (let i = 0; i < maxPoints; i++) {
		const idx = Math.round(i * step);
		sampled.push(coordinates[idx]);
		indices.push(idx);
	}

	return { sampled, indices };
}
