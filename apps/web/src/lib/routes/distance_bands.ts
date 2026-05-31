/**
 * Race-distance bands for route discovery.
 *
 * Runners think in race distances, not raw kilometres, so the discovery
 * map filters on these named windows. This module is the single source
 * of truth for the band ranges — the `discoverable_routes_in_bbox` RPC
 * is generic over whatever [lo, hi) windows it's handed (migration
 * `20261114_001`), so the numbers live here, in one place.
 *
 * Windows are deliberately tolerant (a "5K" route is rarely exactly
 * 5.00 km) and leave gaps between bands (a 15 km route is not a race
 * distance and matches no band). Bounds are in metres: `minM` inclusive,
 * `maxM` exclusive, `maxM === null` open-ended (ultra).
 */

export type DistanceBandKey = '5k' | '10k' | 'half' | 'marathon' | 'ultra';

export interface DistanceBand {
	key: DistanceBandKey;
	label: string;
	minM: number;
	maxM: number | null;
}

export const DISTANCE_BANDS: DistanceBand[] = [
	{ key: '5k', label: '5K', minM: 4000, maxM: 6000 },
	{ key: '10k', label: '10K', minM: 8000, maxM: 12000 },
	{ key: 'half', label: 'Half', minM: 19000, maxM: 23000 },
	{ key: 'marathon', label: 'Marathon', minM: 40000, maxM: 44500 },
	{ key: 'ultra', label: 'Ultra', minM: 44500, maxM: null },
];

/// The band a given route distance falls into, or null if it sits in a
/// gap between bands. Used to badge route rows in the list.
export function bandForDistance(distanceM: number): DistanceBand | null {
	for (const b of DISTANCE_BANDS) {
		if (distanceM >= b.minM && (b.maxM === null || distanceM < b.maxM)) return b;
	}
	return null;
}

/// Convert selected band keys into the parallel min/max arrays the RPC
/// expects. Returns nulls when nothing is selected so the RPC skips the
/// distance predicate entirely. Output order always follows
/// DISTANCE_BANDS, independent of the order keys were passed in.
export function bandsToRanges(keys: DistanceBandKey[]): {
	min: number[] | null;
	max: (number | null)[] | null;
} {
	if (keys.length === 0) return { min: null, max: null };
	const sel = DISTANCE_BANDS.filter((b) => keys.includes(b.key));
	if (sel.length === 0) return { min: null, max: null };
	return { min: sel.map((b) => b.minM), max: sel.map((b) => b.maxM) };
}
