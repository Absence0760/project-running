/**
 * Fetch elevation data for a list of coordinates using the Open-Meteo API.
 * Free, no API key required, rate-limited to reasonable usage.
 * Returns elevations in metres for each coordinate.
 */
export async function fetchElevations(
	coordinates: [number, number][]
): Promise<number[]> {
	if (coordinates.length === 0) return [];

	// Open-Meteo accepts up to ~100 points per request, batch if needed
	const batchSize = 100;
	const results: number[] = [];

	for (let i = 0; i < coordinates.length; i += batchSize) {
		const batch = coordinates.slice(i, i + batchSize);
		const lats = batch.map(([, lat]) => lat).join(',');
		const lngs = batch.map(([lng]) => lng).join(',');

		const url = `https://api.open-meteo.com/v1/elevation?latitude=${lats}&longitude=${lngs}`;
		const res = await fetch(url);

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
