/**
 * Segment-effort extraction (decisions §37).
 *
 * v1 segments are slices of a *saved route* — `(start_distance_m,
 * end_distance_m)`. To produce an effort time for a run that follows
 * the route, we walk the run's track once, accumulate cumulative
 * distance via haversine, and record the timestamps at the moments
 * cumulative distance crosses `start_distance_m` and `end_distance_m`.
 *
 * Pure module — no Supabase, no DOM. Stress-tested in segments.test.ts.
 */

import type { TrackPoint } from '../types';
import { unwrapLonDeg } from '../routes/geo';

export interface SegmentSlice {
	start_distance_m: number;
	end_distance_m: number;
}

export interface EffortResult {
	time_seconds: number;
	started_at: string; // ISO from the start crossing
}

/**
 * Computes the elapsed time over a (start, end) distance window of a
 * run track. Returns null when the track is too short to cover the
 * segment, has no timestamps, or is too sparsely sampled to produce
 * a meaningful effort (median sample distance > segment length / 5,
 * per §37 trade-off 2).
 */
export function computeEffortFromTrack(
	track: TrackPoint[],
	segment: SegmentSlice,
): EffortResult | null {
	return computeEffortsFromTrack(track, [segment])[0];
}

/**
 * Times a run track over many segment slices at once, returning one result
 * per input slice. Identical per-slice semantics to `computeEffortFromTrack`,
 * which delegates here.
 *
 * Everything expensive here is a property of the TRACK, not of the slice —
 * the cumulative-distance array and the median sample step the sparsity guard
 * compares against. Calling the single-slice form in a loop rebuilt and
 * re-sorted both per slice, so a run over a segmented route cost
 * O(segments x points log points): a 100k-point ultra over a 50-segment route
 * spent ~600 ms of blocked main thread on run-detail. Measured once here, the
 * per-slice work is two binary searches.
 *
 * Mirrors `computeEffortsFromTrack` in
 * `apps/mobile_android/lib/segments.dart`.
 */
export function computeEffortsFromTrack(
	track: TrackPoint[],
	segments: readonly SegmentSlice[],
): (EffortResult | null)[] {
	const out: (EffortResult | null)[] = new Array(segments.length).fill(null);
	if (track.length < 2 || segments.length === 0) return out;
	const index = distanceIndex(track);
	for (let i = 0; i < segments.length; i++) {
		out[i] = effortFromIndex(track, index, segments[i]);
	}
	return out;
}

interface TrackDistanceIndex {
	cum: Float64Array;
	/** Median non-zero sample step; null when the track never moved. */
	medianStep: number | null;
}

function distanceIndex(track: TrackPoint[]): TrackDistanceIndex {
	const cum = new Float64Array(track.length);
	const steps: number[] = [];
	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		const d = haversineMetres(a.lat, a.lng, b.lat, b.lng);
		cum[i] = cum[i - 1] + d;
		if (d > 0) steps.push(d);
	}
	if (steps.length === 0) return { cum, medianStep: null };
	steps.sort((a, b) => a - b);
	return { cum, medianStep: steps[Math.floor(steps.length / 2)] };
}

function effortFromIndex(
	track: TrackPoint[],
	index: TrackDistanceIndex,
	segment: SegmentSlice,
): EffortResult | null {
	const segLen = segment.end_distance_m - segment.start_distance_m;
	if (segLen <= 0) return null;

	const { cum, medianStep } = index;
	if (cum[cum.length - 1] < segment.end_distance_m) return null;
	if (medianStep == null) return null;

	// Sparsity guard: median sample step must be at least 5× smaller
	// than the segment so the start / end crossings are well-resolved.
	if (medianStep > segLen / 5) return null;

	const startTs = timestampAtDistance(track, cum, segment.start_distance_m);
	const endTs = timestampAtDistance(track, cum, segment.end_distance_m);
	if (startTs == null || endTs == null) return null;

	const elapsed = (endTs - startTs) / 1000;
	if (!(elapsed > 0)) return null;

	return {
		time_seconds: elapsed,
		started_at: new Date(startTs).toISOString(),
	};
}

/** A free-standing catalogue-segment geometry (the global/famous-segment
 *  layer — decisions §232). Unlike a route slice, it carries its own
 *  polyline, so matching keys off the run passing the segment's start
 *  then its end rather than a distance-along-a-route window. */
export interface GlobalSegmentGeometry {
	/** Ordered lat/lng points of the segment's own polyline. */
	points: { lat: number; lng: number }[];
	/** The catalogue's stored length in metres — the end-to-end guard. */
	distance_m: number;
}

/**
 * Scores a run track against a free-standing catalogue-segment geometry
 * and returns the effort time, or null if the run didn't run it.
 *
 * v1 is a CURATED end-to-end match, NOT arbitrary-geometry HMM matching
 * (deferred — see docs/features/segments.md): the run must approach the
 * segment's START within `toleranceM`, then reach its END within
 * `toleranceM` LATER in the track (a segment is directional), having
 * covered a distance within 25% of the segment's own length between the
 * two crossings — otherwise null, mirroring `pickAutoEffortRoute`'s
 * "better no effort than a wrong one" stance. The actual timing then runs
 * `computeEffortFromTrack`'s own logic over that distance window, so the
 * sparsity + timestamp-interpolation guards are shared, not re-derived.
 *
 * Mirrors `computeGlobalSegmentEffort` in
 * `apps/mobile_android/lib/segments.dart`.
 */
export function computeGlobalSegmentEffort(
	track: TrackPoint[],
	segment: GlobalSegmentGeometry,
	toleranceM = 35,
): EffortResult | null {
	return computeGlobalSegmentEfforts(track, [segment], toleranceM)[0];
}

/**
 * Scores a run track against a whole catalogue of segment geometries in one
 * sweep, returning one result per input segment (null where the run didn't
 * run it). Identical per-segment semantics to `computeGlobalSegmentEffort`,
 * which delegates here.
 *
 * The batch shape is what makes catalogue scoring affordable. Scored
 * one-at-a-time, every segment paid two full-track haversine passes before
 * the check that rejects it, so the run-detail sweep over the 500-segment
 * catalogue (`GLOBAL_SEGMENT_SCORING_LIMIT`) was O(segments x trackPoints) —
 * seconds of blocked main thread on a long track, essentially all of it spent
 * measuring distances to segments on other continents. Here the track's
 * extent is measured once and each segment is rejected against it in constant
 * time, so only the handful of geometries that could plausibly match walk the
 * track at all.
 *
 * Mirrors `computeGlobalSegmentEfforts` in
 * `apps/mobile_android/lib/segments.dart`.
 */
export function computeGlobalSegmentEfforts(
	track: TrackPoint[],
	segments: readonly GlobalSegmentGeometry[],
	toleranceM = 35,
): (EffortResult | null)[] {
	const out: (EffortResult | null)[] = new Array(segments.length).fill(null);
	if (track.length < 2 || segments.length === 0) return out;

	const bounds = trackBounds(track);
	// Only built once a segment survives the extent test — a sweep that
	// rejects every segment must not pay a haversine pass at all.
	let index: TrackDistanceIndex | null = null;

	for (let i = 0; i < segments.length; i++) {
		const segment = segments[i];
		const pts = segment.points;
		if (pts.length < 2 || segment.distance_m <= 0) continue;
		const start = pts[0];
		const end = pts[pts.length - 1];
		if (!boundsAdmit(bounds, start, toleranceM)) continue;
		if (!boundsAdmit(bounds, end, toleranceM)) continue;
		if (index === null) index = distanceIndex(track);
		out[i] = scoreAgainstTrack(track, index, segment, toleranceM);
	}
	return out;
}

function scoreAgainstTrack(
	track: TrackPoint[],
	index: TrackDistanceIndex,
	segment: GlobalSegmentGeometry,
	toleranceM: number,
): EffortResult | null {
	const cum = index.cum;
	const pts = segment.points;
	const start = pts[0];
	const end = pts[pts.length - 1];

	// Nearest run-track index to the segment start.
	let startIdx = -1;
	let startBest = Infinity;
	for (let i = 0; i < track.length; i++) {
		const d = haversineMetres(track[i].lat, track[i].lng, start.lat, start.lng);
		if (d < startBest) {
			startBest = d;
			startIdx = i;
		}
	}
	if (startIdx < 0 || startBest > toleranceM) return null;

	// Nearest run-track index to the segment end, AFTER the start crossing.
	let endIdx = -1;
	let endBest = Infinity;
	for (let i = startIdx + 1; i < track.length; i++) {
		const d = haversineMetres(track[i].lat, track[i].lng, end.lat, end.lng);
		if (d < endBest) {
			endBest = d;
			endIdx = i;
		}
	}
	if (endIdx < 0 || endBest > toleranceM) return null;

	const dStart = cum[startIdx];
	const dEnd = cum[endIdx];
	if (dEnd <= dStart) return null;

	// End-to-end guard: the covered distance must be ~the segment length,
	// so a straight-line shortcut between distant start/end points isn't
	// mistaken for running the segment.
	if (Math.abs(dEnd - dStart - segment.distance_m) / segment.distance_m > 0.25) return null;

	return effortFromIndex(track, index, {
		start_distance_m: dStart,
		end_distance_m: dEnd,
	});
}

/**
 * Latitude / longitude extent of a run track. Longitudes are unwrapped
 * around the first point (`geo.ts`), so a track straddling the antimeridian
 * stays one narrow interval instead of appearing to span the globe.
 */
interface TrackBounds {
	minLat: number;
	maxLat: number;
	refLon: number;
	minLon: number;
	maxLon: number;
}

/**
 * Metres per degree of latitude on the 6371 km sphere `haversineMetres`
 * uses is 111_195; the smaller figure here is deliberate, so every degree
 * window derived from a tolerance comes out slightly WIDER than the true
 * one. The extent test must never reject a segment the full scan would
 * have matched.
 */
const CONSERVATIVE_METRES_PER_DEG = 110_574;

function trackBounds(track: TrackPoint[]): TrackBounds {
	const refLon = track[0].lng;
	let minLat = track[0].lat;
	let maxLat = minLat;
	let minLon = refLon;
	let maxLon = refLon;
	for (let i = 1; i < track.length; i++) {
		const lat = track[i].lat;
		if (lat < minLat) minLat = lat;
		else if (lat > maxLat) maxLat = lat;
		const lon = unwrapLonDeg(refLon, track[i].lng);
		if (lon < minLon) minLon = lon;
		else if (lon > maxLon) maxLon = lon;
	}
	return { minLat, maxLat, refLon, minLon, maxLon };
}

/**
 * Whether any point of the track could lie within `toleranceM` of `point`.
 * Conservative by construction: `false` means every track point is provably
 * further away, `true` means "maybe, go and measure".
 *
 * Latitude is exact — spherical distance is never less than the meridian
 * separation. Longitude uses the tangent-meridian bound: everything within
 * an angular distance s of a point at latitude phi lies within
 * asin(sin s / cos phi) of its meridian, which for a 35 m tolerance is the
 * linear s / cos phi to well inside the margin the constant above carries.
 * Approaching the poles that window swells past a half-turn and the test
 * stops discriminating, so it admits rather than pretending to.
 */
function boundsAdmit(
	bounds: TrackBounds,
	point: { lat: number; lng: number },
	toleranceM: number,
): boolean {
	const padLat = toleranceM / CONSERVATIVE_METRES_PER_DEG;
	if (point.lat < bounds.minLat - padLat || point.lat > bounds.maxLat + padLat) return false;

	const cosLat = Math.cos((point.lat * Math.PI) / 180);
	if (cosLat <= 0) return true;
	const padLon = padLat / cosLat;
	if (padLon >= 180) return true;

	const lon = unwrapLonDeg(bounds.refLon, point.lng);
	return lon >= bounds.minLon - padLon && lon <= bounds.maxLon + padLon;
}

/**
 * Linearly interpolates the timestamp (ms epoch) at the moment the
 * cumulative distance crosses `target`. Returns null when no two
 * adjacent points carry timestamps to bracket the crossing.
 */
function timestampAtDistance(
	track: TrackPoint[],
	cum: Float64Array,
	target: number,
): number | null {
	// `cum` is non-decreasing, so the first index reaching `target` is a
	// binary search rather than a walk from the start of the track.
	let lo = 1;
	let hi = track.length - 1;
	let found = -1;
	while (lo <= hi) {
		const mid = (lo + hi) >> 1;
		if (cum[mid] < target) {
			lo = mid + 1;
		} else {
			found = mid;
			hi = mid - 1;
		}
	}
	if (found > 0) {
		const i = found;
		const prev = cum[i - 1];
		const here = cum[i];
		const a = track[i - 1];
		const b = track[i];
		if (!a.ts || !b.ts) return null;
		const tA = Date.parse(a.ts);
		const tB = Date.parse(b.ts);
		if (Number.isNaN(tA) || Number.isNaN(tB)) return null;
		const span = here - prev;
		const frac = span > 0 ? (target - prev) / span : 0;
		return tA + (tB - tA) * frac;
	}
	return null;
}

/**
 * Standard competition rank for an ascending-time leaderboard. Tied
 * times share the lower rank; the next distinct time skips to its
 * natural ordinal position. Example: times [10, 10, 15] → [1, 1, 3].
 *
 * Pure — used by the `fetchSegmentLeaderboardTiered` leaderboard fetcher.
 * Mirrors the `assignCompetitionRanks` helper in
 * `apps/mobile_android/lib/segments.dart`.
 *
 * Caller must pass items pre-sorted ascending by `time_seconds`.
 */
export function assignCompetitionRanks<T extends { time_seconds: number }>(
	rows: readonly T[],
): Array<{ row: T; rank: number }> {
	const out: Array<{ row: T; rank: number }> = [];
	let lastTime = Number.NaN;
	let lastRank = 0;
	for (let i = 0; i < rows.length; i++) {
		const r = rows[i];
		const rank = r.time_seconds === lastTime ? lastRank : i + 1;
		lastTime = r.time_seconds;
		lastRank = rank;
		out.push({ row: r, rank });
	}
	return out;
}

/**
 * Strava-style age band labels — 5-year bins starting at 18-19, then
 * 20-24 / 25-29 / ... up to '75+'. Matches Strava + Garmin Connect.
 * The migration's `segment_leaderboard_tiered` RPC accepts any of
 * these strings; pass `null` for "all ages".
 *
 * Lives in this pure module (not `data.ts`) so unit tests can pin
 * its shape without dragging in the SvelteKit `$env`-bound supabase
 * client.
 */
export const SEGMENT_AGE_BANDS = [
	'18-19',
	'20-24',
	'25-29',
	'30-34',
	'35-39',
	'40-44',
	'45-49',
	'50-54',
	'55-59',
	'60-64',
	'65-69',
	'70-74',
	'75+',
] as const;
export type SegmentAgeBand = (typeof SEGMENT_AGE_BANDS)[number];

export type SegmentGenderFilter = 'male' | 'female';

/**
 * Tooltip / aria-label for the KOM/QOM crown badge. Describes which
 * tier the rank-1 holder owns ("Fastest woman 35-39", "Fastest
 * overall", etc.) given the active filter. Mirrors
 * `apps/mobile_android/lib/segments.dart#crownLabel`.
 */
export function crownLabel(
	genderFilter: SegmentGenderFilter | null,
	ageFilter: SegmentAgeBand | null,
): string {
	const subject =
		genderFilter == null ? null : genderFilter === 'male' ? 'man' : 'woman';
	if (subject == null && ageFilter == null) return 'Fastest overall';
	if (subject != null && ageFilter == null) return `Fastest ${subject}`;
	if (subject == null && ageFilter != null) return `Fastest ${ageFilter}`;
	return `Fastest ${subject} ${ageFilter}`;
}

function haversineMetres(lat1: number, lng1: number, lat2: number, lng2: number): number {
	const r = 6371000;
	const dLat = ((lat2 - lat1) * Math.PI) / 180;
	const dLng = ((lng2 - lng1) * Math.PI) / 180;
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const a =
		sinLat * sinLat +
		Math.cos((lat1 * Math.PI) / 180) *
			Math.cos((lat2 * Math.PI) / 180) *
			sinLng *
			sinLng;
	return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)));
}
