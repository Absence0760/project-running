// Pure waypoint-generation helpers for the Route Builder's
// "Generate by distance" feature. Lifted out of RouteBuilder.svelte
// so the math (which has had two field-reported bugs around
// degenerate inputs) can be unit-tested without spinning up a map.

import type { TrackPoint } from './types';
import { haversineM } from './routing_quality';

/// Two endpoints closer than this are treated as the same point —
/// the user wanted a loop and the slight delta is just map-click
/// precision. Below this distance the point-to-point math
/// degenerates (perpendicular offset ≈ 0 because dLat / dLng ≈ 0)
/// and the next iteration's scaleFactor explodes.
export const NEAR_POINT_M = 50;

/// Per-iteration ratio clamp. After each routing attempt we adjust
/// scaleFactor by `targetDistance / actualDistance`. When the first
/// attempt clumped waypoints (e.g. start ≈ end, network failure), the
/// raw ratio can be in the hundreds, which then pushes the next
/// attempt's waypoints kilometres off-map. Clamping to ~3x change per
/// step keeps the search local.
export const RATIO_CLAMP = { min: 0.3, max: 3 };

/// Absolute scaleFactor bounds. Even with the per-step clamp, three
/// successive 3x adjustments would compound to 27x — still enough to
/// produce a route in the wrong country. Lock the cumulative range so
/// the worst case is a poorly-sized loop, not a hijacked route.
export const SCALE_FACTOR_BOUNDS = { min: 0.05, max: 2 };

/// Empirical starting scale: OSRM road-distance through curved
/// waypoints lands ≈ 0.30 of the geometric path the math would draw
/// if every coordinate were exactly reachable.
export const DEFAULT_SCALE_FACTOR = 0.3;

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
		numPoints = 6,
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

/**
 * Adjust scaleFactor for the next iteration of the
 * generate-loop / generate-route attempt. Clamps both the
 * per-step multiplier and the absolute output so a runaway ratio
 * from a degenerate first attempt can't push the next attempt's
 * waypoints off the planet.
 *
 * Returns the new scaleFactor.
 */
export function nextScaleFactor(
	scaleFactor: number,
	targetDistanceM: number,
	actualDistanceM: number,
): number {
	if (actualDistanceM <= 0 || !Number.isFinite(actualDistanceM)) {
		return Math.max(
			SCALE_FACTOR_BOUNDS.min,
			Math.min(SCALE_FACTOR_BOUNDS.max, scaleFactor * RATIO_CLAMP.max),
		);
	}
	const rawRatio = targetDistanceM / actualDistanceM;
	const clampedRatio = Math.max(RATIO_CLAMP.min, Math.min(RATIO_CLAMP.max, rawRatio));
	const next = scaleFactor * clampedRatio;
	return Math.max(SCALE_FACTOR_BOUNDS.min, Math.min(SCALE_FACTOR_BOUNDS.max, next));
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

/// Bisect the scaleFactor toward a target distance. Strictly
/// better than nextScaleFactor's multiplicative-ratio approach when
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
