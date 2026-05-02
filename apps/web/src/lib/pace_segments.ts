// Pure pace-bucket / age-band helpers backing the NRC-style pace
// heatmap on the run map. TypeScript port of
// `apps/mobile_android/lib/widgets/pace_segments.dart` — keep them in
// lockstep so a run rendered on web and on mobile shows the same
// colours at the same points.

import type { TrackPoint } from './types';

export type ActivityKind = 'run' | 'walk' | 'cycle' | 'hike';

/// Slow → fast colour ramp, 6 buckets. Bucket count matches the
/// breakpoints array (5 breakpoints partition speed into 6 buckets).
export const PACE_RAMP: readonly string[] = [
	'#EF4444', // red — slowest
	'#F97316', // orange
	'#FBBF24', // amber
	'#A3E635', // lime
	'#10B981', // emerald
	'#22D3EE', // cyan — fastest
];

/// Three age bands (oldest → newest) applied as alpha on top of the
/// pace colour. The tail of the run fades out like a comet; the segment
/// nearest the runner is fully opaque.
export const AGE_ALPHAS: readonly number[] = [0.55, 0.8, 1.0];

/// Speed break-points (m/s), slow → fast. Four activities use pace
/// (min/km); cycling is displayed as speed but the buckets are
/// expressed in m/s so a single helper handles both. Values mirror
/// `_speedBreakpoints` in the Dart twin.
const SPEED_BREAKPOINTS: Record<ActivityKind, number[]> = {
	run: [2.2, 2.7, 3.2, 3.7, 4.4],
	walk: [1.0, 1.3, 1.6, 1.8, 2.2],
	cycle: [3.3, 5.0, 6.7, 8.3, 10.0],
	hike: [0.8, 1.1, 1.4, 1.7, 2.2],
};

/// Which pace bucket the given speed falls into. Bucket 0 is slowest,
/// `breakpoints.length` is fastest. Clamped at both ends.
export function paceBucketForSpeed(mps: number, activity: ActivityKind): number {
	const breaks = SPEED_BREAKPOINTS[activity];
	for (let i = 0; i < breaks.length; i++) {
		if (mps < breaks[i]) return i;
	}
	return breaks.length;
}

/// Which age band the segment at [segmentIndex] falls into, given
/// [segmentCount] segments. Index 0 = oldest, index 2 = newest. Short
/// tracks (≤ 1 segment) are treated as fully newest.
export function ageBandFor(segmentIndex: number, segmentCount: number): number {
	if (segmentCount <= 1) return 2;
	const f = segmentIndex / (segmentCount - 1);
	if (f < 1 / 3) return 0;
	if (f < 2 / 3) return 1;
	return 2;
}

function haversineMetres(a: TrackPoint, b: TrackPoint): number {
	const r = 6371000;
	const lat1 = (a.lat * Math.PI) / 180;
	const lat2 = (b.lat * Math.PI) / 180;
	const dLat = ((b.lat - a.lat) * Math.PI) / 180;
	const dLng = ((b.lng - a.lng) * Math.PI) / 180;
	const h =
		Math.sin(dLat / 2) * Math.sin(dLat / 2) +
		Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
	return 2 * r * Math.asin(Math.sqrt(h));
}

function segmentSpeedMps(a: TrackPoint, b: TrackPoint): number | null {
	if (!a.ts || !b.ts) return null;
	const dtSec = (Date.parse(b.ts) - Date.parse(a.ts)) / 1000;
	if (!Number.isFinite(dtSec) || dtSec <= 0) return null;
	const d = haversineMetres(a, b);
	if (d <= 0) return null;
	return d / dtSec;
}

export interface PaceSegment {
	/// Polyline coordinates as [lng, lat] pairs (GeoJSON order).
	coords: [number, number][];
	/// rgba(...) string ready to pass to MapLibre `'line-color'`.
	color: string;
}

/// Build the list of polyline segments that make up the pace-coloured,
/// age-faded track. Each segment is assigned a `(paceBucket, ageBand)`
/// and consecutive segments sharing both are coalesced into a single
/// polyline so the map doesn't have to draw one feature per GPS fix.
///
/// Returns an empty list for tracks with fewer than two points. When
/// timestamps are missing for some segments, those buckets fall back to
/// 0 (slowest), matching the Dart twin. The caller is responsible for
/// using [hasTrackTimestamps] to decide whether the heatmap is
/// meaningful, or falling through to the single-gradient render path.
export function buildPaceSegments(track: TrackPoint[], activity: ActivityKind): PaceSegment[] {
	if (track.length < 2) return [];
	const segCount = track.length - 1;
	const paceBucket = new Array<number>(segCount);
	for (let i = 0; i < segCount; i++) {
		const mps = segmentSpeedMps(track[i], track[i + 1]);
		paceBucket[i] = mps === null ? 0 : paceBucketForSpeed(mps, activity);
	}

	const ageBand = new Array<number>(segCount);
	for (let i = 0; i < segCount; i++) ageBand[i] = ageBandFor(i, segCount);

	const out: PaceSegment[] = [];
	let runStart = 0;
	const emit = (firstSeg: number, lastSegExclusive: number) => {
		const coords: [number, number][] = [];
		for (let j = firstSeg; j <= lastSegExclusive; j++) {
			coords.push([track[j].lng, track[j].lat]);
		}
		out.push({ coords, color: rgbaFor(paceBucket[firstSeg], ageBand[firstSeg]) });
	};

	for (let i = 1; i < segCount; i++) {
		if (paceBucket[i] !== paceBucket[i - 1] || ageBand[i] !== ageBand[i - 1]) {
			emit(runStart, i);
			runStart = i;
		}
	}
	emit(runStart, segCount);
	return out;
}

/// True iff at least one consecutive pair of waypoints in [track]
/// carries usable timestamps (so a meaningful pace can be computed).
/// Cheap precondition check the caller can use to gate the heatmap
/// render path.
export function hasTrackTimestamps(track: TrackPoint[]): boolean {
	for (let i = 1; i < track.length; i++) {
		if (track[i - 1].ts && track[i].ts) return true;
	}
	return false;
}

function rgbaFor(bucket: number, ageBand: number): string {
	const hex = PACE_RAMP[Math.max(0, Math.min(PACE_RAMP.length - 1, bucket))];
	const alpha = AGE_ALPHAS[Math.max(0, Math.min(AGE_ALPHAS.length - 1, ageBand))];
	const r = parseInt(hex.slice(1, 3), 16);
	const g = parseInt(hex.slice(3, 5), 16);
	const b = parseInt(hex.slice(5, 7), 16);
	return `rgba(${r},${g},${b},${alpha})`;
}
