/**
 * Transport-agnostic core for the "Generate a route by distance" endpoint.
 *
 * Wrapped twice — once by the SvelteKit dev route
 * (`src/routes/api/routes/generate/+server.ts`) and once by the production AWS
 * Lambda (`apps/web/lambda/generate-route/src/index.ts`) — mirroring the coach
 * handler's two-wrapper shape (decisions §53). Validates the request, fans out
 * a few round_trip seeds, picks the best-shaped loop, and returns a finished
 * polyline the client renders directly (no further OSRM routing).
 *
 * Fail-closed: a missing engine URL → 501 (operator config), an engine that's
 * down or can't build a loop → 502, bad input → 400.
 */

import {
	fetchRoundTrip,
	GraphHopperError,
	type Fetcher,
	type LoopCandidate,
} from './graphhopper';
import { pickBestLoop } from './select';
import { generatePolygonLoop } from './loop_generate';
import { isValidTargetDistance } from '../route_loop';

export interface GenerateRequest {
	start: { lat: number; lng: number };
	targetDistanceM: number;
	/// How many round_trip seeds to race; clamped to [1, MAX_SEEDS].
	seeds?: number;
}

export interface GenerateConfig {
	graphhopperUrl: string | undefined;
	/// Shared secret forwarded to the engine as `X-Engine-Key` (see
	/// RoundTripRequest.apiKey). Undefined in dev when the guard is permissive.
	graphhopperApiKey?: string;
	/// Self-hosted OSRM base URL for the sampled via-point polygon generator
	/// (route_loop_generation.md). When set, the handler tries the polygon loop
	/// FIRST and only falls back to round_trip when it returns loop-poor. Unset →
	/// polygon path is skipped entirely (round_trip only).
	osrmUrl?: string;
}

export interface GenerateDeps {
	fetcher?: Fetcher;
}

export type GenerateResult =
	| { status: 200; body: { coordinates: [number, number][]; distanceM: number } }
	| { status: 400 | 501 | 502; body: { error: string } };

/// Seeds raced at EACH request multiplier (so total round_trip calls is
/// seeds × REQUEST_MULTIPLIERS). round_trip's actual distance varies wildly per
/// seed in sparse networks (a 5 km ask can return 4–14 km), so several seeds per
/// magnitude raises the odds of landing near target for selection to pick.
export const DEFAULT_SEEDS = 5;
export const MAX_SEEDS = 8;

/// Request-distance multipliers raced around the user's target. round_trip's
/// actual/requested ratio is location-specific — some networks overshoot the
/// requested distance, some undershoot — so a single request can't land near
/// target everywhere. Racing a spread and keeping the actual result closest to
/// target (./select) self-corrects both directions. Validated: a start that
/// returns 6.4 km at a 5 km request returns ~5.2 km at a 3.25 km (0.65×) request,
/// while a start ~30 m away needs 1.1× the other way.
export const REQUEST_MULTIPLIERS = [0.65, 0.8, 1.0, 1.2] as const;

function isValidCoord(p: { lat: number; lng: number }): boolean {
	return (
		Number.isFinite(p.lat) &&
		Number.isFinite(p.lng) &&
		Math.abs(p.lat) <= 90 &&
		Math.abs(p.lng) <= 180
	);
}

/// Parse + shape-check an untrusted body. Returns null on anything malformed;
/// the caller turns that into a 400. Does NOT range-check the values — that's
/// `isValidCoord` / `isValidTargetDistance` in `handleGenerate` so the failure
/// reasons stay distinct.
export function parseGenerateRequest(raw: unknown): GenerateRequest | null {
	if (!raw || typeof raw !== 'object') return null;
	const r = raw as Record<string, unknown>;
	const start = r.start as Record<string, unknown> | undefined;
	if (!start || typeof start !== 'object') return null;
	const lat = Number(start.lat);
	const lng = Number(start.lng);
	const targetDistanceM = Number(r.targetDistanceM);
	if (typeof start.lat !== 'number' || typeof start.lng !== 'number') return null;
	if (typeof r.targetDistanceM !== 'number') return null;
	const out: GenerateRequest = { start: { lat, lng }, targetDistanceM };
	if (r.seeds !== undefined) {
		if (typeof r.seeds !== 'number' || !Number.isFinite(r.seeds)) return null;
		out.seeds = r.seeds;
	}
	return out;
}

export async function handleGenerate(
	raw: unknown,
	config: GenerateConfig,
	deps: GenerateDeps = {},
): Promise<GenerateResult> {
	const req = parseGenerateRequest(raw);
	if (!req) return { status: 400, body: { error: 'invalid request body' } };
	if (!isValidCoord(req.start)) return { status: 400, body: { error: 'invalid start coordinate' } };
	if (!isValidTargetDistance(req.targetDistanceM)) {
		return { status: 400, body: { error: 'invalid targetDistanceM' } };
	}
	if (!config.graphhopperUrl && !config.osrmUrl) {
		return { status: 501, body: { error: 'route generation is not configured' } };
	}

	// Polygon-first: when OSRM is configured, try the sampled via-point loop
	// (route_loop_generation.md). A real result wins; null means loop-poor (or
	// OSRM unreachable) and we fall through to round_trip below.
	if (config.osrmUrl) {
		const fetcher: Fetcher = deps.fetcher ?? ((u, i) => fetch(u, i));
		const polygon = await generatePolygonLoop(req.start, req.targetDistanceM, fetcher, {
			osrmUrl: config.osrmUrl,
		});
		if (polygon) {
			return { status: 200, body: polygon };
		}
		// OSRM produced no loop AND GraphHopper isn't configured for the fallback:
		// this is a loop-poor location with no out-and-back engine to offer.
		if (!config.graphhopperUrl) {
			return { status: 502, body: { error: 'no usable route' } };
		}
	}

	const seeds = Math.max(1, Math.min(MAX_SEEDS, Math.round(req.seeds ?? DEFAULT_SEEDS)));
	let lastError: unknown;
	const results = await Promise.all(
		REQUEST_MULTIPLIERS.flatMap((mult) =>
			Array.from({ length: seeds }, (_, i) =>
				fetchRoundTrip(
					{
						baseUrl: config.graphhopperUrl,
						start: req.start,
						requestDistanceM: req.targetDistanceM * mult,
						seed: i,
						apiKey: config.graphhopperApiKey,
					},
					deps.fetcher,
				).catch((e) => {
					lastError = e;
					return null;
				}),
			),
		),
	);

	const candidates: LoopCandidate[] = results.filter((c): c is LoopCandidate => c !== null);
	if (candidates.length === 0) {
		// Every seed failed. An unconfigured engine is an operator problem
		// (501); anything else is the engine being down / unable to build a
		// loop at this location (502).
		if (lastError instanceof GraphHopperError && lastError.kind === 'unconfigured') {
			return { status: 501, body: { error: 'route generation is not configured' } };
		}
		return { status: 502, body: { error: 'route engine unavailable' } };
	}

	const best = pickBestLoop(candidates, req.targetDistanceM);
	if (!best) return { status: 502, body: { error: 'no usable route' } };
	return { status: 200, body: { coordinates: best.coordinates, distanceM: best.distanceM } };
}
