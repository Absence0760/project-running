import { bandForDistance } from './distance_bands';
import type { RouteSurface } from '../types';

/**
 * Templated route describer — turns a route's stored stats into a short,
 * human-readable description without calling any model. This is the
 * always-works L1 baseline for the "Describe this route" affordance: it
 * runs offline, costs nothing, and is the fallback the LLM-enhancement
 * path (a Pro perk) degrades to whenever the model call fails, refuses,
 * the user isn't Pro, or the endpoint is unconfigured.
 *
 * The helper is deliberately unit-agnostic and locale-agnostic: it emits
 * a structured `RouteDescriptionParts` (named facts) rather than a baked
 * English sentence, so the render layer can format distance in km/mi per
 * the viewer's preference and translate each clause into any of the six
 * web locales. `assembleEnglish` is the canonical English assembler used
 * by the LLM prompt (which wants plain prose to enhance) and by tests;
 * the route-detail UI builds the localised sentence from the parts.
 *
 * Twin of `apps/mobile_android/lib/route_description.dart` — keep the
 * classification thresholds, clause set, ordering, edge cases, and test
 * count in lockstep.
 */

export type RouteShape = 'loop' | 'out_and_back' | 'point_to_point';

/** Elevation character bucketed from total gain over distance (m/km). */
export type ElevationProfile = 'flat' | 'rolling' | 'hilly' | 'mountainous';

export interface RouteDescriptionInput {
	name: string;
	distanceM: number;
	elevationM: number | null;
	surface: RouteSurface | null;
	/** First and last waypoint, when known, to infer loop vs point-to-point. */
	start?: { lat: number; lng: number };
	end?: { lat: number; lng: number };
}

export interface RouteDescriptionParts {
	/** Named race-distance band ('5k', '10k', …) or null if between bands. */
	band: string | null;
	distanceM: number;
	surface: RouteSurface | null;
	elevationM: number;
	elevation: ElevationProfile;
	/** Gain per kilometre, rounded — drives the elevation bucket + UI detail. */
	gainPerKm: number;
	shape: RouteShape;
}

/**
 * Two endpoints within this distance are treated as the same point — the
 * route returns to where it started, so it's a loop (or an out-and-back,
 * which also closes on itself). Matches the route-loop builder's
 * `NEAR_POINT_M` so "Generate by distance" loops describe as loops.
 */
export const LOOP_CLOSE_M = 75;

/** m/km thresholds for the elevation buckets. Inclusive lower bound. */
export const ELEVATION_THRESHOLDS = {
	rolling: 10,
	hilly: 30,
	mountainous: 70,
} as const;

/**
 * Great-circle distance in metres. Local copy (not imported from
 * routing_quality) so this module stays dependency-light and the Dart
 * twin can mirror it 1:1 without dragging the routing helpers across.
 */
function haversineM(
	a: { lat: number; lng: number },
	b: { lat: number; lng: number },
): number {
	const R = 6371000;
	const dLat = ((b.lat - a.lat) * Math.PI) / 180;
	const dLng = ((b.lng - a.lng) * Math.PI) / 180;
	const lat1 = (a.lat * Math.PI) / 180;
	const lat2 = (b.lat * Math.PI) / 180;
	const h =
		Math.sin(dLat / 2) ** 2 +
		Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
	return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Bucket total gain (m) over distance into a coarse elevation character. */
export function elevationProfile(
	distanceM: number,
	elevationM: number,
): { profile: ElevationProfile; gainPerKm: number } {
	if (distanceM <= 0 || elevationM <= 0) {
		return { profile: 'flat', gainPerKm: 0 };
	}
	const gainPerKm = Math.round((elevationM / distanceM) * 1000);
	let profile: ElevationProfile = 'flat';
	if (gainPerKm >= ELEVATION_THRESHOLDS.mountainous) profile = 'mountainous';
	else if (gainPerKm >= ELEVATION_THRESHOLDS.hilly) profile = 'hilly';
	else if (gainPerKm >= ELEVATION_THRESHOLDS.rolling) profile = 'rolling';
	return { profile, gainPerKm };
}

/**
 * Infer route shape from endpoints. Without endpoints we can't tell, so
 * default to `point_to_point` (the most conservative claim — it never
 * asserts a loop that isn't there). When start ≈ end the route closes on
 * itself; we report `loop` (an out-and-back also closes, but the stored
 * waypoints can't distinguish the two without walking the trace, and
 * "loop" reads naturally for both — the LLM path can refine it).
 */
export function routeShape(input: RouteDescriptionInput): RouteShape {
	if (!input.start || !input.end) return 'point_to_point';
	return haversineM(input.start, input.end) <= LOOP_CLOSE_M
		? 'loop'
		: 'point_to_point';
}

/** Compute the structured facts the UI + LLM prompt build on. */
export function describeRoute(
	input: RouteDescriptionInput,
): RouteDescriptionParts {
	const distanceM = Number.isFinite(input.distanceM)
		? Math.max(0, input.distanceM)
		: 0;
	const elevationM =
		input.elevationM != null && Number.isFinite(input.elevationM)
			? Math.max(0, input.elevationM)
			: 0;
	const { profile, gainPerKm } = elevationProfile(distanceM, elevationM);
	const band = bandForDistance(distanceM);
	return {
		band: band ? band.key : null,
		distanceM,
		surface: input.surface ?? null,
		elevationM,
		elevation: profile,
		gainPerKm,
		shape: routeShape(input),
	};
}

const SHAPE_WORD: Record<RouteShape, string> = {
	loop: 'loop',
	out_and_back: 'out-and-back',
	point_to_point: 'point-to-point',
};

const SURFACE_WORD: Record<RouteSurface, string> = {
	road: 'road',
	trail: 'trail',
	mixed: 'mixed-surface',
};

const ELEVATION_WORD: Record<ElevationProfile, string> = {
	flat: 'flat',
	rolling: 'gently rolling',
	hilly: 'hilly',
	mountainous: 'mountainous',
};

/**
 * Canonical English assembler. Used to seed the LLM prompt (plain prose
 * the model enhances) and as the literal fallback string in tests and on
 * the server's degraded path. The route-detail UI does NOT call this —
 * it builds a localised, unit-aware sentence from `RouteDescriptionParts`
 * so non-English viewers and mi-preference viewers get correct output.
 * Distance is rendered in km here because this string is English-only by
 * contract; the localised UI path handles mi.
 */
export function assembleEnglish(
	parts: RouteDescriptionParts,
	name: string,
): string {
	const km = (parts.distanceM / 1000).toFixed(parts.distanceM >= 1000 ? 1 : 2);
	const shape = SHAPE_WORD[parts.shape];
	const surface = parts.surface ? `${SURFACE_WORD[parts.surface]} ` : '';
	const clauses: string[] = [];
	clauses.push(`${name} is a ${km} km ${surface}${shape} route`);
	if (parts.elevationM > 0) {
		clauses.push(
			`with ${Math.round(parts.elevationM)} m of climbing (${ELEVATION_WORD[parts.elevation]}, about ${parts.gainPerKm} m per km)`,
		);
	} else {
		clauses.push('with little to no elevation change');
	}
	return clauses.join(' ') + '.';
}
