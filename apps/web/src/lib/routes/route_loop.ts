// Pure waypoint-generation helpers for the Route Builder's
// "Generate by distance" feature. Lifted out of RouteBuilder.svelte
// so the math (which has had two field-reported bugs around
// degenerate inputs) can be unit-tested without spinning up a map.

import type { TrackPoint } from '../types';
import { haversineM } from './routing_quality';

/// Two endpoints closer than this are treated as the same point —
/// the user wanted a loop and the slight delta is just map-click
/// precision. Below this distance the point-to-point math
/// degenerates (perpendicular offset ≈ 0 because dLat / dLng ≈ 0)
/// and the next iteration's scaleFactor explodes.
export const NEAR_POINT_M = 50;

/// Absolute scaleFactor bounds the bisection search will never
/// exceed. Caps the worst case at a poorly-sized loop, not a
/// route in the wrong country.
export const SCALE_FACTOR_BOUNDS = { min: 0.05, max: 2 };

/// Empirical starting scale for the default 4-waypoint (square)
/// layout. With four interior radial points the loop has 5 segments
/// (start→W1, W1→W2, W2→W3, W3→W4, W4→close=start) and a chord
/// total of 2R + 3R√2 ≈ 6.24R. Applying a typical road factor of
/// ~1.5x for long-leg paths, actualDistance ≈ 9.36R, so to hit a
/// target T we want R ≈ T/9.36, i.e. scale = R · 2π / T ≈ 0.67.
/// Rounded down to 0.65 to bias slightly small — bisection finds a
/// near-target fit faster when the first overshoot is mild.
///
/// Picking 4 waypoints over 6 (the original) intentionally moves the
/// scaffolding outward — wider-spread seeds give OSRM room to find
/// natural multi-leg paths instead of stitching together close
/// radial hops that backtrack on the same road.
export const DEFAULT_SCALE_FACTOR = 0.65;

/// Number of interior radial waypoints in the scaffolding pattern.
/// 4 (square) is the sweet spot — fewer than 3 collapses to a
/// degenerate triangle; more than ~6 packs waypoints close enough
/// that adjacent ones share the same street segment.
export const DEFAULT_NUM_POINTS = 4;

export interface LoopWaypointArgs {
	start: { lat: number; lng: number };
	/// Omitted, null, or within NEAR_POINT_M of start → closed loop.
	end?: { lat: number; lng: number } | null;
	targetDistanceM: number;
	scaleFactor?: number;
	numPoints?: number;
	/// Loop only: angle (radians) at which to seed the radial pattern.
	/// Threaded explicitly so unit tests get deterministic output —
	/// the live call passes Math.random() * 2π.
	radialSeedRad?: number;
}

/**
 * Generate the waypoint sequence for a Generate-by-distance request.
 *
 * Returns `[start, ...inner, closing]` — what the routing code feeds
 * into OSRM. The function does not call OSRM itself.
 *
 * Behaviour:
 *   - When `end` is omitted, null, or within `NEAR_POINT_M` of
 *     `start`, the output is a closed loop of `numPoints` radial
 *     waypoints around `start` at radius
 *     `(targetDistanceM * scaleFactor) / (2π)`, plus a closing
 *     waypoint at start.
 *   - Otherwise the output is a curved point-to-point with
 *     `numPoints` interior waypoints between start and end. The
 *     perpendicular offset is proportional to how much further the
 *     route needs to go than the straight-line distance.
 *
 * Returning the exact same `start` and `end` (or `{ ...start }` for
 * the loop case) at the endpoints is load-bearing — the routing
 * layer trusts that the first/last waypoint match the user's pins.
 */
export function generateLoopWaypoints(args: LoopWaypointArgs): TrackPoint[] {
	const {
		start,
		end,
		targetDistanceM,
		scaleFactor = DEFAULT_SCALE_FACTOR,
		numPoints = DEFAULT_NUM_POINTS,
		radialSeedRad = 0,
	} = args;

	const startEndDistM = end
		? haversineM({ lng: start.lng, lat: start.lat }, { lng: end.lng, lat: end.lat })
		: 0;
	const isLoop = !end || startEndDistM < NEAR_POINT_M;

	if (isLoop) {
		const radiusM = (targetDistanceM * scaleFactor) / (2 * Math.PI);
		const radiusDeg = radiusM / 111320;
		const cosLat = Math.cos((start.lat * Math.PI) / 180);

		const out: TrackPoint[] = [{ lat: start.lat, lng: start.lng }];
		for (let i = 1; i <= numPoints; i++) {
			const angle = radialSeedRad + (i / numPoints) * Math.PI * 2;
			out.push({
				lat: start.lat + Math.sin(angle) * radiusDeg,
				lng: start.lng + (Math.cos(angle) * radiusDeg) / cosLat,
			});
		}
		out.push({ lat: start.lat, lng: start.lng });
		return out;
	}

	// Point-to-point with a perpendicular curve sized to hit the
	// target distance. We know end != null here.
	const e = end as { lat: number; lng: number };
	const directDist = startEndDistM;
	const curveAmount = Math.max(
		0,
		(targetDistanceM * scaleFactor - directDist) / Math.max(directDist, 1),
	);
	const dLat = e.lat - start.lat;
	const dLng = e.lng - start.lng;
	const perpLat = -dLng * curveAmount * 0.4;
	const perpLng = dLat * curveAmount * 0.4;

	const out: TrackPoint[] = [{ lat: start.lat, lng: start.lng }];
	for (let i = 1; i <= numPoints; i++) {
		const t = i / (numPoints + 1);
		const curveFactor = Math.sin(t * Math.PI);
		out.push({
			lat: start.lat + dLat * t + perpLat * curveFactor,
			lng: start.lng + dLng * t + perpLng * curveFactor,
		});
	}
	out.push({ lat: e.lat, lng: e.lng });
	return out;
}

/// Acceptance band for the iteration loop — within this ratio range
/// of the target we stop adjusting.
export const ACCEPT_BAND = { min: 0.85, max: 1.15 };

export function isWithinAcceptBand(targetDistanceM: number, actualDistanceM: number): boolean {
	if (actualDistanceM <= 0) return false;
	const ratio = targetDistanceM / actualDistanceM;
	return ratio > ACCEPT_BAND.min && ratio < ACCEPT_BAND.max;
}

/// Upper bound for a sane Generate-by-distance target. 1,000 km is
/// well past the longest documented road run; anything beyond that
/// is almost certainly a unit-conversion bug (e.g. someone passed
/// km instead of metres). Reject at the API boundary instead of
/// burning a 3-attempt iteration on an unroutable input.
export const MAX_TARGET_DISTANCE_M = 1_000_000;

/// Guard for `targetDistanceM` callers pass into the generate-loop
/// API. Rejects NaN, Infinity, non-positive, and the absurd-large
/// case. The route builder slider already clamps the value, but the
/// public method must not trust its caller.
export function isValidTargetDistance(m: unknown): m is number {
	return (
		typeof m === 'number' &&
		Number.isFinite(m) &&
		m > 0 &&
		m <= MAX_TARGET_DISTANCE_M
	);
}

/// A `[lower, upper]` scaleFactor bracket the iteration narrows on
/// each attempt. Threaded through bisectScale so callers can keep the
/// bracket state explicit instead of relying on closure mutation.
export interface ScaleRange {
	lower: number;
	upper: number;
}

export function initScaleRange(): ScaleRange {
	return { lower: SCALE_FACTOR_BOUNDS.min, upper: SCALE_FACTOR_BOUNDS.max };
}

/// Bisect the scaleFactor toward a target distance. Robust when
/// OSRM's actual distance is a noisy / non-monotonic function of
/// scale — which is the typical case in twisty suburban grids,
/// where small radius changes can flip a segment between a direct
/// path and a multi-block detour.
///
/// If actual > target, the current scale is an upper bound — the
/// answer is somewhere below it. If actual < target, it's a lower
/// bound. Either way the next attempt picks the midpoint of the
/// narrowed bracket. With 4 attempts we narrow the [0.05, 2]
/// initial range to ~1/16 of its width — plenty to surround the
/// target.
export function bisectScale(
	range: ScaleRange,
	currentScale: number,
	targetDistanceM: number,
	actualDistanceM: number,
): { scale: number; range: ScaleRange } {
	let { lower, upper } = range;
	if (actualDistanceM > targetDistanceM) {
		upper = Math.min(upper, currentScale);
	} else {
		lower = Math.max(lower, currentScale);
	}
	let next = (lower + upper) / 2;
	next = Math.max(SCALE_FACTOR_BOUNDS.min, Math.min(SCALE_FACTOR_BOUNDS.max, next));
	return { scale: next, range: { lower, upper } };
}

/// Select the visible waypoints we want to keep AFTER a successful
/// generate. The 8 scaffolding waypoints generateLoopWaypoints
/// emitted at the start of the call are an implementation detail —
/// the user wanted a loop, not 8 pins. We collapse to 4 anchors:
///
///   - The user's `start` (always — keeps the visible green pin
///     exactly where the user placed it, not where OSRM snapped it).
///   - Two midpoints sampled from the snapped polyline at ~1/3 and
///     ~2/3 along. Sampling FROM the polyline guarantees they have
///     zero deviation, so the deviation/detour warnings don't fire.
///     For a polyline too short to support two distinct midpoints
///     we drop one or both.
///   - `close` (start for a loop, or `endAt` for point-to-point).
///
/// 4 is the minimum that preserves loop fidelity on a subsequent
/// Recalculate — a 3-anchor sample collapses a loop into an
/// out-and-back, and 2 anchors degenerate entirely (OSRM refuses to
/// route start → start).
export function selectLoopAnchors(
	polyline: ReadonlyArray<[number, number]>,
	start: { lat: number; lng: number },
	close: { lat: number; lng: number },
): { lat: number; lng: number }[] {
	const out: { lat: number; lng: number }[] = [{ lat: start.lat, lng: start.lng }];
	if (polyline.length >= 4) {
		const mid1Idx = Math.max(1, Math.round(polyline.length / 3));
		const mid2Idx = Math.min(polyline.length - 2, Math.round((2 * polyline.length) / 3));
		const [m1Lng, m1Lat] = polyline[mid1Idx];
		out.push({ lat: m1Lat, lng: m1Lng });
		if (mid2Idx > mid1Idx) {
			const [m2Lng, m2Lat] = polyline[mid2Idx];
			out.push({ lat: m2Lat, lng: m2Lng });
		}
	}
	out.push({ lat: close.lat, lng: close.lng });
	return out;
}
