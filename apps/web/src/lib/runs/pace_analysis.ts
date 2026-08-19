import type { TrackPoint } from '../types';
import { lonDeltaDeg, wrapLonDeg } from '../routes/geo';
import { gradeAdjustedPaceSecPerKm } from './grade_adjusted_pace';
import { haversineMetres, type Split } from './run_stats';

/**
 * Pacing analysis for a recorded run — the interpretation layer over the
 * splits table. Two questions the raw split list never answers:
 *
 *  1. Did the second half go faster than the first (a negative split), slower
 *     (a fade), or the same?
 *  2. Was that a pacing story or a terrain story? A split that climbs 80 m
 *     reads as a blow-up in raw pace even when the effort never wavered, so
 *     every figure here is also offered grade-adjusted (Minetti, via
 *     `gradeAdjustedPaceSecPerKm`) whenever the track carries elevation.
 *
 * Halves are cut by DISTANCE, not by time — "negative split" is a statement
 * about the second half of the course, and cutting by time would put the
 * halfway mark short of it on any run that faded. Durations are elapsed
 * within the half, matching how the splits table times its own boundaries.
 *
 * Twin of `apps/mobile_android/lib/pace_analysis.dart` — keep the algorithm,
 * constants, edge cases, and test count in lockstep. `gradeAdjustedSplitPaces`
 * takes the splits themselves here and reads `distance_m` off each; mobile's
 * `RunSplit` carries only a tick and a duration, so the Dart side takes the
 * lengths directly.
 */

export type PacingVerdict = 'negative' | 'even' | 'positive';

/**
 * Relative band around the first half's pace inside which the two halves are
 * called even. 2 % of pace — 6 s/km at a 5:00/km first half — which is the
 * conventional "evenly paced" tolerance and comfortably above GPS noise over
 * a half-run's worth of samples.
 */
export const EVEN_BAND_PCT = 0.02;

export interface HalfPace {
	distanceM: number;
	durationS: number;
	paceSecPerKm: number;
}

export interface PacingHalves {
	first: HalfPace;
	second: HalfPace;
	/** Second half minus first, seconds per km. Negative = sped up. */
	deltaSecPerKm: number;
	verdict: PacingVerdict;
}

export interface GradeAdjustedHalves {
	firstSecPerKm: number;
	secondSecPerKm: number;
	deltaSecPerKm: number;
	verdict: PacingVerdict;
}

export interface PacingAnalysis {
	raw: PacingHalves;
	/** Null when either half carries no elevation, so GAP would be raw pace. */
	gradeAdjusted: GradeAdjustedHalves | null;
}

/**
 * First-half vs second-half pacing for a run's GPS track. Null when the track
 * is too short, carries no distance, or either half has no usable pair of
 * timestamps to derive a duration from.
 */
export function analysePacing(track: TrackPoint[] | null | undefined): PacingAnalysis | null {
	if (!track || track.length < 2) return null;

	let total = 0;
	for (let i = 1; i < track.length; i++) {
		total += haversineMetres(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
	}
	if (total <= 0) return null;

	const [firstSlice, secondSlice] = sliceTrackAtDistances(track, [total / 2]);
	const first = halfPace(firstSlice);
	const second = halfPace(secondSlice);
	if (!first || !second) return null;

	const gapFirst = gradeAdjustedPaceSecPerKm(firstSlice);
	const gapSecond = gradeAdjustedPaceSecPerKm(secondSlice);

	return {
		raw: {
			first,
			second,
			deltaSecPerKm: second.paceSecPerKm - first.paceSecPerKm,
			verdict: verdictFor(first.paceSecPerKm, second.paceSecPerKm),
		},
		gradeAdjusted:
			gapFirst != null && gapSecond != null
				? {
						firstSecPerKm: gapFirst,
						secondSecPerKm: gapSecond,
						deltaSecPerKm: gapSecond - gapFirst,
						verdict: verdictFor(gapFirst, gapSecond),
					}
				: null,
	};
}

/**
 * Grade-adjusted pace, in seconds per km, for each split in `splits` — one
 * entry per split, aligned index-for-index so the splits table can render it
 * as a column beside the raw pace. Null for a split whose slice of the track
 * carries no elevation or no usable timing.
 *
 * Boundaries are the running sum of the splits' own `distance_m`, so the
 * slices land on exactly the boundaries the table already displays rather
 * than on a second, independently-walked set that could drift by a point.
 */
export function gradeAdjustedSplitPaces(
	track: TrackPoint[] | null | undefined,
	splits: Split[]
): (number | null)[] {
	if (splits.length === 0) return [];
	if (!track || track.length < 2) return splits.map(() => null);

	const boundaries: number[] = [];
	let cum = 0;
	for (const s of splits) {
		cum += s.distance_m;
		boundaries.push(cum);
	}
	const slices = sliceTrackAtDistances(track, boundaries);
	return splits.map((_, i) => gradeAdjustedPaceSecPerKm(slices[i]));
}

function verdictFor(firstSecPerKm: number, secondSecPerKm: number): PacingVerdict {
	const band = firstSecPerKm * EVEN_BAND_PCT;
	const delta = secondSecPerKm - firstSecPerKm;
	if (delta < -band) return 'negative';
	if (delta > band) return 'positive';
	return 'even';
}

function halfPace(slice: TrackPoint[]): HalfPace | null {
	if (slice.length < 2) return null;
	let distanceM = 0;
	for (let i = 1; i < slice.length; i++) {
		distanceM += haversineMetres(slice[i - 1].lat, slice[i - 1].lng, slice[i].lat, slice[i].lng);
	}
	if (distanceM <= 0) return null;

	const times: number[] = [];
	for (const p of slice) {
		const ms = p.ts ? Date.parse(p.ts) : NaN;
		if (Number.isFinite(ms)) times.push(ms);
	}
	if (times.length < 2) return null;
	const durationS = (times[times.length - 1] - times[0]) / 1000;
	if (durationS <= 0) return null;

	return {
		distanceM,
		durationS,
		paceSecPerKm: Math.round(durationS / (distanceM / 1000)),
	};
}

/**
 * Cut a track into `boundariesM.length + 1` contiguous slices at the given
 * cumulative horizontal distances, inserting an interpolated point at each
 * cut that both adjacent slices share — so no metre and no second of the run
 * falls between two slices. Always returns exactly that many slices; a
 * boundary past the end of the track yields an empty trailing slice.
 */
function sliceTrackAtDistances(track: TrackPoint[], boundariesM: number[]): TrackPoint[][] {
	const slices: TrackPoint[][] = [];
	if (track.length < 2) {
		slices.push(track.slice());
		while (slices.length <= boundariesM.length) slices.push([]);
		return slices;
	}

	let cur: TrackPoint[] = [track[0]];
	let cum = 0;
	let bi = 0;
	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		const segStart = cum;
		const segDist = haversineMetres(a.lat, a.lng, b.lat, b.lng);
		cum += segDist;
		while (bi < boundariesM.length && segDist > 0 && cum >= boundariesM[bi]) {
			const f = (boundariesM[bi] - segStart) / segDist;
			const cut = f <= 0 ? a : f >= 1 ? b : interpolatePoint(a, b, f);
			if (cur[cur.length - 1] !== cut) cur.push(cut);
			slices.push(cur);
			cur = [cut];
			bi++;
		}
		if (cur[cur.length - 1] !== b) cur.push(b);
	}
	slices.push(cur);
	while (slices.length <= boundariesM.length) slices.push([]);
	return slices;
}

function interpolatePoint(a: TrackPoint, b: TrackPoint, f: number): TrackPoint {
	// Longitude through `lonDeltaDeg`: a plain subtraction is a whole turn out
	// across the antimeridian, which would place the cut point on the far side
	// of the planet and hand both halves a nonsense distance.
	const p: TrackPoint = {
		lat: a.lat + (b.lat - a.lat) * f,
		lng: wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * f),
	};
	if (a.ele != null && b.ele != null) p.ele = a.ele + (b.ele - a.ele) * f;
	const aMs = a.ts ? Date.parse(a.ts) : NaN;
	const bMs = b.ts ? Date.parse(b.ts) : NaN;
	if (Number.isFinite(aMs) && Number.isFinite(bMs)) {
		p.ts = new Date(aMs + (bMs - aMs) * f).toISOString();
	}
	return p;
}
