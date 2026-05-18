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
