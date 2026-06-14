/**
 * Transport-agnostic core for the "Generate a route by distance" endpoint.
 *
 * Wrapped twice — once by the SvelteKit dev route
 * (`src/routes/api/routes/generate/+server.ts`) and once by the production AWS
 * Lambda (`apps/web/lambda/generate-route/src/index.ts`) — mirroring the coach
 * handler's two-wrapper shape (decisions §53). Validates the request, then runs
 * the generator chain and returns a finished polyline the client renders
 * directly (no further OSRM routing).
 *
 * Generator chain (docs/features/graph_cycle_loop_generation.md, v3):
 *   1. graph-cycle FIRST — the self-hosted graph_cycle sidecar searches the real
 *      foot graph for a clean loop near target. This is the durable generator;
 *      it traces the neighbourhood loop geometry can't find.
 *   2. round_trip fallback — GraphHopper's `round_trip` (multi-distance race)
 *      when graph-cycle is loop-poor or unreachable.
 * The v2 polygon generator is retired: graph-cycle beat it at every spike start.
 *
 * Fail-closed: no engine URL → 501 (operator config); an engine that's down or
 * can't build a loop → 502; bad input → 400.
 */

import {
	fetchRoundTrip,
	GraphHopperError,
	type Fetcher,
	type LoopCandidate,
	type RoutePreference,
} from './graphhopper';
import { fetchGraphCycle } from './graph_cycle';
import { pickBestLoop } from './select';
import { isValidTargetDistance } from '../route_loop';

export interface GenerateRequest {
	start: { lat: number; lng: number };
	targetDistanceM: number;
	/// How many round_trip seeds to race; clamped to [1, MAX_SEEDS].
	seeds?: number;
	/// Optional road-design preference. `'quiet'` biases the loop onto residential
	/// streets and away from motorway/trunk/primary via a GraphHopper custom model
	/// (the avoid-highways / prefer-residential half of route-design preferences).
	/// Unset → today's behaviour. Any unrecognised value is dropped at parse time.
	preference?: RoutePreference;
}

export interface GenerateConfig {
	/// graph_cycle sidecar base URL (server-only `GRAPH_CYCLE_URL`). When set,
	/// the handler searches the real foot graph FIRST and only falls back to
	/// round_trip when it returns loop-poor or is unreachable. Unset → graph-cycle
	/// is skipped entirely (round_trip only).
	graphCycleUrl?: string;
	/// Shared secret forwarded to the sidecar as `X-Engine-Key`. Undefined in dev
	/// when the guard is permissive.
	graphCycleApiKey?: string;
	graphhopperUrl: string | undefined;
	/// Shared secret forwarded to the engine as `X-Engine-Key` (see
	/// RoundTripRequest.apiKey). Undefined in dev when the guard is permissive.
	graphhopperApiKey?: string;
}

export interface GenerateDeps {
	fetcher?: Fetcher;
}

export type GenerateResult =
	| {
			status: 200;
			body: {
				coordinates: [number, number][];
				distanceM: number;
				/// Present only when the served loop is a round_trip fallback (the
				/// graph-cycle search was loop-poor near target) AND that search
				/// reported a larger genuinely clean loop achievable near the start.
				/// Lets the client offer the "best loop near you is ~X km" choice
				/// instead of a generic shortfall banner.
				largestLoopM?: number;
			};
	  }
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

interface RoundTripRace {
	candidates: LoopCandidate[];
	lastError: unknown;
}

/// Race the REQUEST_MULTIPLIERS × seeds round_trip spread, optionally carrying a
/// road-design preference (custom model). Every seed failure is caught and the
/// last error retained so the caller can distinguish unconfigured (501) from
/// engine-down (502). Extracted so the preference path can re-run it without the
/// preference as a graceful fallback (a preference must never break generation).
async function raceRoundTrip(
	start: { lat: number; lng: number },
	targetDistanceM: number,
	seeds: number,
	config: GenerateConfig,
	fetcher: Fetcher,
	preference?: RoutePreference,
): Promise<RoundTripRace> {
	let lastError: unknown;
	const results = await Promise.all(
		REQUEST_MULTIPLIERS.flatMap((mult) =>
			Array.from({ length: seeds }, (_, i) =>
				fetchRoundTrip(
					{
						baseUrl: config.graphhopperUrl,
						start,
						requestDistanceM: targetDistanceM * mult,
						seed: i,
						apiKey: config.graphhopperApiKey,
						preference,
					},
					fetcher,
				).catch((e) => {
					lastError = e;
					return null;
				}),
			),
		),
	);
	return {
		candidates: results.filter((c): c is LoopCandidate => c !== null),
		lastError,
	};
}

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
	// An unrecognised preference is silently dropped (treated as "no preference")
	// rather than 400'd: a stale/garbled knob must never block route generation.
	if (r.preference === 'quiet') out.preference = 'quiet';
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
	if (!config.graphCycleUrl && !config.graphhopperUrl) {
		return { status: 501, body: { error: 'route generation is not configured' } };
	}

	const fetcher: Fetcher = deps.fetcher ?? ((u, i) => fetch(u, i));

	// Largest genuinely clean loop the graph-cycle search reported near the start.
	// Surfaced even on a loop-poor (no in-band loop) result so the round_trip
	// fallback below can offer the client an explicit "best loop near you is ~X km"
	// choice instead of a silent out-and-back + a generic shortfall banner.
	let largestCleanM: number | null = null;

	// graph-cycle FIRST: search the real foot graph. A real loop wins; null means
	// loop-poor (or the sidecar is unreachable) and we fall through to round_trip.
	// A sidecar error is never fatal — graph-cycle is a quality upgrade, not a
	// hard dependency — so we swallow the throw and let round_trip serve.
	//
	// Skipped when a road-design preference is set: the graph-cycle sidecar doesn't
	// yet honour preferences (full edge-weighted search is the v3 § Extension work),
	// and it would otherwise return a clean-but-arterial loop that ignores the
	// "quiet roads" ask. The custom-model round_trip below carries the preference.
	if (config.graphCycleUrl && !req.preference) {
		try {
			const result = await fetchGraphCycle(
				{
					baseUrl: config.graphCycleUrl,
					start: req.start,
					targetDistanceM: req.targetDistanceM,
					apiKey: config.graphCycleApiKey,
				},
				fetcher,
			);
			largestCleanM = result.largestCleanM;
			if (result.loop) {
				return {
					status: 200,
					body: { coordinates: result.loop.coordinates, distanceM: result.loop.distanceM },
				};
			}
		} catch (e) {
			// Unconfigured/unreachable sidecar → fall through to round_trip (or 502
			// below if no fallback engine is configured). Log so a prolonged sidecar
			// outage is visible rather than silently degrading every request to the
			// fallback — the request still ends 200, so nothing else would surface it.
			console.warn(
				'[generate] graph_cycle sidecar error, falling back:',
				e instanceof Error ? e.message : String(e),
			);
		}
		// graph-cycle produced no loop AND GraphHopper isn't configured for the
		// fallback: a loop-poor location with no out-and-back engine to offer.
		if (!config.graphhopperUrl) {
			return { status: 502, body: { error: 'no usable route' } };
		}
	}

	const seeds = Math.max(1, Math.min(MAX_SEEDS, Math.round(req.seeds ?? DEFAULT_SEEDS)));
	let { candidates, lastError } = await raceRoundTrip(
		req.start,
		req.targetDistanceM,
		seeds,
		config,
		fetcher,
		req.preference,
	);

	// Graceful fallback: a preference-aware (custom_model) race that produced
	// nothing — the engine rejected the model, or the down-weighting found no loop —
	// must never deny a route the plain generator could build. Retry once without
	// the preference. Layered resilience: the preference is an enhancement, the
	// route itself is the contract.
	if (req.preference && candidates.length === 0) {
		({ candidates, lastError } = await raceRoundTrip(
			req.start,
			req.targetDistanceM,
			seeds,
			config,
			fetcher,
		));
	}

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

	// This loop is a round_trip fallback — graph-cycle found no clean in-band loop
	// near target. If the graph search nonetheless reported a larger genuinely
	// clean loop, surface it so the client can offer "best loop near you is ~X km".
	// Only attach when it's meaningfully (>5%) larger than what we're serving, so
	// we never offer a "better" loop that's the same size as the out-and-back.
	const body: { coordinates: [number, number][]; distanceM: number; largestLoopM?: number } = {
		coordinates: best.coordinates,
		distanceM: best.distanceM,
	};
	if (largestCleanM !== null && largestCleanM > best.distanceM * 1.05) {
		body.largestLoopM = largestCleanM;
	}
	return { status: 200, body };
}
