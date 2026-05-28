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
