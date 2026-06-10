import { pointToSegmentDistanceM } from './routing_quality';

/**
 * The index at which to insert a clicked point into a waypoint sequence
 * so the new pin lands on the segment the click is actually nearest to.
 * Returns `waypoints.length` (i.e. append) when there are fewer than two
 * waypoints to form a segment.
 *
 * Uses true point-to-segment distance — NOT distance to each segment's
 * midpoint, which the route-builder used to do. The midpoint heuristic
 * mis-picks whenever the click sits near the FAR end of a long segment:
 * a shorter neighbouring segment's midpoint can be closer to the click
 * than the long segment's midpoint, so the new waypoint was inserted
 * into the wrong segment. Measuring the perpendicular distance to the
 * segment itself fixes that — a click lying on a segment scores 0 there
 * regardless of how far it is from that segment's midpoint.
 *
 * Web-only (the mobile route builder has no click-to-insert), so no Dart
 * twin to keep in lockstep.
 */
export function nearestInsertIndex(
	waypoints: { lat: number; lng: number }[],
	point: { lat: number; lng: number },
): number {
	if (waypoints.length < 2) return waypoints.length;

	let bestIdx = waypoints.length;
	let bestDist = Infinity;
	for (let i = 0; i < waypoints.length - 1; i++) {
		const d = pointToSegmentDistanceM(point, waypoints[i], waypoints[i + 1]);
		if (d < bestDist) {
			bestDist = d;
			bestIdx = i + 1;
		}
	}
	return bestIdx;
}
