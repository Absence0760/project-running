import type { TrackPoint } from '../types';
import { computeEffortFromTrack } from './segments';

/// Pick the saved route an imported (route-less) run clearly *followed*, so
/// its segment efforts can be auto-computed (strava persona #21).
///
/// computeSegmentEffortsForRun slices the run's track by each segment's
/// distance-along-the-route, which is only valid when the run ran the route
/// end-to-end from its start. So we only auto-compute when there is EXACTLY
/// ONE candidate that is an unambiguous end-to-end match:
///   - both endpoints project near the route ends (start+end offset small), and
///   - the run's length is within 20% of the route length.
/// Anything ambiguous (multiple strong matches, partial overlap, a run that
/// merely crosses the route) returns null — better no efforts than wrong ones.
/// Mirrors the heuristic documented on fetchRoutesIntersectingTrack in data.ts.
export interface AutoEffortCandidate {
	id: string;
	distanceM: number;
	startOffsetM: number;
	endOffsetM: number;
}

export function pickAutoEffortRoute(
	candidates: AutoEffortCandidate[],
	trackLengthM: number,
	toleranceM = 100,
): string | null {
	if (trackLengthM <= 0) return null;
	const strong = candidates.filter(
		(c) =>
			c.startOffsetM + c.endOffsetM < 2 * toleranceM &&
			c.distanceM > 0 &&
			Math.abs(c.distanceM - trackLengthM) / trackLengthM < 0.2,
	);
	return strong.length === 1 ? strong[0].id : null;
}

export interface SegmentForEffort {
	id: string;
	/// numeric column may arrive as a string over the wire.
	start_distance_m: number | string;
	end_distance_m: number | string;
}

export interface SegmentEffortInsert {
	segment_id: string;
	run_id: string;
	user_id: string;
	time_seconds: number;
	started_at: string;
}

/// Compute the segment-effort rows a run earned over a set of route
/// segments — the matchable subset (segments the track actually covered)
/// in one walk. The caller writes these in a single batched upsert rather
/// than one insert per segment (a 30-segment route used to fire 30 serial
/// round-trips on the run-detail view).
export function buildSegmentEffortRows(
	segments: SegmentForEffort[],
	track: TrackPoint[],
	ids: { run_id: string; user_id: string },
): SegmentEffortInsert[] {
	const rows: SegmentEffortInsert[] = [];
	for (const seg of segments) {
		const eff = computeEffortFromTrack(track, {
			start_distance_m: Number(seg.start_distance_m),
			end_distance_m: Number(seg.end_distance_m),
		});
		if (!eff) continue;
		rows.push({
			segment_id: seg.id,
			run_id: ids.run_id,
			user_id: ids.user_id,
			time_seconds: eff.time_seconds,
			started_at: eff.started_at,
		});
	}
	return rows;
}
