// Quality metrics for an OSRM-snapped route relative to the user's
// dropped waypoints. The route builder's goal is "snap to walkable
// paths near my clicks" — not "find the shortest path between
// arbitrary points on Earth". A snap is bad when:
//
//   * The OSRM polyline passes nowhere near a waypoint (the user
//     clicked on a path the graph doesn't know about, so OSRM
//     reached for the nearest mapped road regardless of distance).
//   * A segment's snapped distance is many times the straight-line
//     distance between its endpoints (the OSRM graph has no direct
//     edge, so the route takes a wild detour).
//
// We surface both as warnings in the route-builder UI. The thresholds
// here are intentionally loose — fixing every short detour creates
// false-positive fatigue. See `validateRouteQuality` for the
// load-bearing numbers.

import type { TrackPoint } from './types';

/// One OSRM-routed segment between two consecutive waypoints. The
/// polyline is `[[lng, lat], ...]` (OSRM's GeoJSON convention) and
/// `distanceM` is the OSRM-reported `routes[0].distance` in metres.
export interface RoutedSegment {
	from: TrackPoint;
	to: TrackPoint;
	polyline: [number, number][];
	distanceM: number;
}

export interface QualityReport {
	/// Worst perpendicular distance (m) from a waypoint to the
	/// merged polyline. A value > ~50m typically means the user
	/// clicked somewhere the OSRM graph doesn't reach and the
	/// snap is misleading.
	maxWaypointDeviationM: number;
	/// Index of the waypoint with the worst deviation (1-based for
	/// human messages: "waypoint 3 is 240m from the route").
	worstDeviationWaypointIndex: number;
	/// Worst segment-level detour: OSRM distance / haversine distance.
	/// Pure straight line = 1.0; a path winding around a lake = ~1.5;
	/// >= 2.5 typically indicates the OSRM graph routed via a much
	/// longer alternative.
	worstSegmentDetourRatio: number;
	/// 1-based segment index of the worst detour ("segment 3 is a 4x
	/// detour"). 0 when no segments are present.
	worstDetourSegmentIndex: number;
}

const EARTH_RADIUS_M = 6371000;

function toRad(d: number): number {
	return (d * Math.PI) / 180;
}

export function haversineM(
	a: { lng: number; lat: number },
	b: { lng: number; lat: number },
): number {
	const dLat = toRad(b.lat - a.lat);
	const dLng = toRad(b.lng - a.lng);
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const h =
		sinLat * sinLat +
		Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
	return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/// Perpendicular distance from `p` to the closest point on segment
/// `(a, b)`. Treats lat/lng as a local Cartesian plane scaled by
/// cos(midLat) — accurate to ~0.1% for distances under a few km,
/// which is the regime we care about (waypoints that snapped well
/// have deviations of 0-30m; we want to distinguish 30m from 200m,
/// not 30.0 from 30.05).
export function pointToSegmentDistanceM(
	p: { lng: number; lat: number },
	a: { lng: number; lat: number },
	b: { lng: number; lat: number },
): number {
	const midLat = (a.lat + b.lat) / 2;
	const cosLat = Math.cos(toRad(midLat));
	// Convert to local metres relative to `a`. 1 degree latitude
	// ≈ 111_320 m; 1 degree longitude ≈ 111_320 * cos(lat) m.
	const ax = 0;
	const ay = 0;
	const bx = (b.lng - a.lng) * 111320 * cosLat;
	const by = (b.lat - a.lat) * 111320;
	const px = (p.lng - a.lng) * 111320 * cosLat;
	const py = (p.lat - a.lat) * 111320;

	const dx = bx - ax;
	const dy = by - ay;
	const lenSq = dx * dx + dy * dy;
	let t = lenSq === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
	t = Math.max(0, Math.min(1, t));
	const qx = ax + t * dx;
	const qy = ay + t * dy;
	const ddx = px - qx;
	const ddy = py - qy;
	return Math.sqrt(ddx * ddx + ddy * ddy);
}

/// Closest distance from `p` to the polyline. Walks every edge —
/// O(N) per call, which is fine since the polyline never exceeds a
/// few thousand points and we run this for at most ~10 waypoints.
export function closestPointDistanceM(
	p: { lng: number; lat: number },
	polyline: [number, number][],
): number {
	if (polyline.length === 0) return Infinity;
	if (polyline.length === 1) {
		return haversineM(p, { lng: polyline[0][0], lat: polyline[0][1] });
	}
	let best = Infinity;
	for (let i = 1; i < polyline.length; i++) {
		const a = { lng: polyline[i - 1][0], lat: polyline[i - 1][1] };
		const b = { lng: polyline[i][0], lat: polyline[i][1] };
		const d = pointToSegmentDistanceM(p, a, b);
		if (d < best) best = d;
	}
	return best;
}

/// Compute deviation + detour stats for a fully-routed sequence.
///
///   * `segments[i]` corresponds to the user's `i`-th and `(i+1)`-th
///     waypoints; its `polyline` is the OSRM-returned sub-path
///     between them, and `distanceM` is OSRM's reported length.
///   * The waypoint set is implied by `segments[i].from` for each
///     segment plus the last segment's `to`.
///
/// Returns `{ maxWaypointDeviationM: 0, ... }` for an empty input
/// so callers can apply thresholds without branching on length.
export function validateRouteQuality(segments: RoutedSegment[]): QualityReport {
	if (segments.length === 0) {
		return {
			maxWaypointDeviationM: 0,
			worstDeviationWaypointIndex: 0,
			worstSegmentDetourRatio: 1,
			worstDetourSegmentIndex: 0,
		};
	}

	const waypoints: TrackPoint[] = [segments[0].from, ...segments.map((s) => s.to)];
	// Merge all segment polylines for the deviation pass. Each
	// segment's polyline is independent; concatenating them with a
	// duplicate join point doesn't change the perpendicular-distance
	// answer because the duplicate is on the same line.
	const merged: [number, number][] = [];
	for (const s of segments) merged.push(...s.polyline);

	let maxDev = 0;
	let worstDevIdx = 0;
	waypoints.forEach((w, i) => {
		const d = closestPointDistanceM(w, merged);
		if (d > maxDev) {
			maxDev = d;
			// Human-friendly 1-based index for messages.
			worstDevIdx = i + 1;
		}
	});

	let maxDetour = 1;
	let worstDetourIdx = 0;
	segments.forEach((s, i) => {
		const straightLine = haversineM(s.from, s.to);
		if (straightLine < 1) return; // ignore zero-length segments
		const ratio = s.distanceM / straightLine;
		if (ratio > maxDetour) {
			maxDetour = ratio;
			worstDetourIdx = i + 1;
		}
	});

	return {
		maxWaypointDeviationM: maxDev,
		worstDeviationWaypointIndex: worstDevIdx,
		worstSegmentDetourRatio: maxDetour,
		worstDetourSegmentIndex: worstDetourIdx,
	};
}

/// Thresholds applied by the route builder to decide whether to
/// surface a warning. Exported so unit tests don't drift.
export const QUALITY_THRESHOLDS = {
	/// Waypoint snap deviation above this (m) fires the deviation
	/// warning. Chosen as 2x the OSRM snap radius default below so a
	/// small overshoot stays quiet, but a real wander surfaces.
	deviationWarnM: 60,
	/// Segment detour ratio above this fires the detour warning.
	/// Real-world reroutes around closed gates / waterways routinely
	/// hit 1.8-2.2x, so we stay above that band.
	detourWarnRatio: 2.5,
};

/// Per-waypoint OSRM snap radius (metres). OSRM's `radiuses=` query
/// caps how far it will reach to find a road when matching each
/// coordinate. Default in OSRM is "unlimited" — that's how a click
/// near a stream ends up snapping to a road 800m away. 100m is loose
/// enough that a runner clicking near a known path still snaps, but
/// rejects the absurd cases.
export const OSRM_SNAP_RADIUS_M = 100;

/// Compose a human-readable warning when the quality report exceeds
/// either threshold. Returns null when the route passes both. Tests
/// pin the wording so callers know what to assert.
export function qualityWarning(q: QualityReport): string | null {
	const devBad = q.maxWaypointDeviationM > QUALITY_THRESHOLDS.deviationWarnM;
	const detourBad = q.worstSegmentDetourRatio > QUALITY_THRESHOLDS.detourWarnRatio;
	if (!devBad && !detourBad) return null;

	const parts: string[] = [];
	if (devBad) {
		parts.push(
			`Waypoint ${q.worstDeviationWaypointIndex} is ${Math.round(q.maxWaypointDeviationM)}m off the snapped path — drop it closer to a real path or road.`,
		);
	}
	if (detourBad) {
		parts.push(
			`Segment ${q.worstDetourSegmentIndex} is a ${q.worstSegmentDetourRatio.toFixed(1)}x detour — the routing engine couldn't find a direct path. Add an intermediate waypoint to guide it.`,
		);
	}
	return parts.join(' ');
}
