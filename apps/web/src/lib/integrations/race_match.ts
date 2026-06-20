// Pure race auto-match scoring. Mirror of mobile race_match.dart — keep in
// lockstep (algorithm, bands, thresholds, test counts). No I/O.
//
// The auto-match-on-record seam (race_calendar.md) offers, after a run is
// saved, to import the official race result when the recorded run looks like a
// listed race: same calendar day + start near the race location + distance in
// the race's band. This is an INFORM-tier suggestion — nothing writes without
// the user confirming.

export type RaceDistanceBand = '5k' | '10k' | 'half' | 'marathon' | 'ultra';

/// Confidence at or above which a candidate is worth offering.
export const RACE_MATCH_THRESHOLD = 0.5;

/// Start within this radius of the listing's location counts as "at the race".
export const RACE_MATCH_RADIUS_M = 5000;

/// Bucket a distance in metres into a race-distance band with tolerance, or
/// null when it is too short to be a recognised race distance. The bands match
/// the SQL search_race_listings p_distance windows.
export function raceDistanceBand(distanceM: number | null | undefined): RaceDistanceBand | null {
	if (distanceM == null || !Number.isFinite(distanceM) || distanceM < 4500) return null;
	if (distanceM <= 5500) return '5k';
	if (distanceM >= 9000 && distanceM <= 11000) return '10k';
	if (distanceM >= 20000 && distanceM <= 22000) return 'half';
	if (distanceM >= 41000 && distanceM <= 43000) return 'marathon';
	if (distanceM > 43000) return 'ultra';
	return null;
}

export interface RunMatchInput {
	/// Run start as an ISO timestamp or a Date — only the calendar day is used.
	runDate: string;
	/// Recorded GPS start point; null when the run has no track (indoor / manual).
	runStartLatLng: { lat: number; lng: number } | null;
	runDistanceM: number | null;
}

export interface ListingMatchInput {
	race_date: string; // ISO date (YYYY-MM-DD)
	distance_m: number | null;
	/// Metres from the run start to the listing location, when known (the RPC
	/// returns distance_m_away). Null when neither side has a geocoded point.
	distance_m_away?: number | null;
}

/// 0..1 confidence that `run` is the race in `listing`. Same-day is required
/// (a race is a fixed-date event) — a different day scores 0. The remaining
/// signal is split between proximity (start within the radius) and a matching
/// distance band; each contributes when its input is available, and the score
/// is normalised over the signals that COULD be evaluated so a run with no
/// track (proximity unknown) can still match on day + distance.
export function raceMatchScore(run: RunMatchInput, listing: ListingMatchInput): number {
	if (!sameCalendarDay(run.runDate, listing.race_date)) return 0;

	let score = 0;
	let weight = 0;

	// Same day is itself a strong-ish signal (races are date-anchored).
	score += 0.5;
	weight += 0.5;

	// Proximity: only when we have a measured distance_m_away.
	if (listing.distance_m_away != null && Number.isFinite(listing.distance_m_away)) {
		weight += 0.3;
		if (listing.distance_m_away <= RACE_MATCH_RADIUS_M) {
			// Linear falloff from 1 (at the point) to 0 (at the radius edge).
			score += 0.3 * (1 - listing.distance_m_away / RACE_MATCH_RADIUS_M);
		}
	}

	// Distance band: only when both sides have a recognised band.
	const runBand = raceDistanceBand(run.runDistanceM);
	const listingBand = raceDistanceBand(listing.distance_m);
	if (runBand != null && listingBand != null) {
		weight += 0.2;
		if (runBand === listingBand) score += 0.2;
	}

	return weight === 0 ? 0 : score / weight;
}

/// Whether a listing is a confident-enough candidate to offer.
export function isRaceMatchCandidate(run: RunMatchInput, listing: ListingMatchInput): boolean {
	return raceMatchScore(run, listing) >= RACE_MATCH_THRESHOLD;
}

/// Great-circle distance in metres between two lat/lng points (haversine).
/// Exposed so a caller can compute distance_m_away when the RPC didn't.
export function haversineMetres(
	a: { lat: number; lng: number },
	b: { lat: number; lng: number }
): number {
	const R = 6371000;
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(b.lat - a.lat);
	const dLng = toRad(b.lng - a.lng);
	const lat1 = toRad(a.lat);
	const lat2 = toRad(b.lat);
	const h =
		Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
	return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

function sameCalendarDay(a: string, b: string): boolean {
	return dayKey(a) === dayKey(b);
}

function dayKey(ts: string): string {
	// Tolerate both 'YYYY-MM-DD' and full ISO timestamps; compare the date part.
	const t = ts.trim();
	if (t.length >= 10) return t.slice(0, 10);
	return t;
}
