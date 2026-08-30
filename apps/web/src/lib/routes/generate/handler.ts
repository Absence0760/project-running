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
 *      foot graph for a clean loop near target, carrying the road-design
 *      preference. This is the durable generator; it traces the neighbourhood
 *      loop geometry can't find.
 *   2. round_trip fallback — GraphHopper's `round_trip` (multi-distance race),
 *      under a `custom_model` where GraphHopper can express the preference, when
 *      graph-cycle is loop-poor or unreachable.
 * The v2 polygon generator is retired: graph-cycle beat it at every spike start.
 * A preference no longer diverts the whole request onto the fallback: it rides
 * the chain, and the served loop reports back which preference (if any) was
 * actually applied, so the client can be honest about an ask it couldn't meet.
 *
 * Fail-closed: no engine URL → 501 (operator config); an engine that's down →
 * 502; an engine that answered but found no loop worth serving near this start
 * → 422; bad input → 400. The 502/422 split matters beyond politeness: the
 * Lambda logs the alarm-driving `engine_unreachable` line on every 502, so a
 * loop-poor neighbourhood answering 502 pages the on-call over geography and
 * makes a real GraphHopper outage indistinguishable from it.
 *
 * Server-side generation is a Pro perk (decisions §204): after validation the
 * handler requires a user JWT and a true `is_pro()`, mirroring the
 * route_describe handler. The 501 is checked BEFORE the tier gate so an
 * unconfigured deploy (rock-bottom / Lean, engines deferred) answers "not
 * available" rather than "upgrade" — the client must never see an upsell for a
 * perk the deploy can't deliver. Free and unauthenticated callers fall back to
 * the in-browser OSRM heuristic, which stays the free tier.
 */

import { createClient } from '@supabase/supabase-js';

import { parseAuthHeader } from '../../coach/limits';
import {
	buildCustomModel,
	fetchRoundTrip,
	GraphHopperError,
	ROUTE_PREFERENCES,
	type Fetcher,
	type LoopCandidate,
	type RoutePreference,
} from './graphhopper';
import { fetchGraphCycle, GraphCycleError } from './graph_cycle';
import { pickBestLoop } from './select';
import { isValidTargetDistance } from '../route_loop';
import { checkRouteRateLimit } from '../rate_limit';
import { supabaseErrorFields } from '../../core/supabase_error';

export interface GenerateRequest {
	start: { lat: number; lng: number };
	targetDistanceM: number;
	/// How many round_trip seeds to race; clamped to [1, MAX_SEEDS].
	seeds?: number;
	/// Optional road-design preference, carried to both engines. Unset → today's
	/// behaviour. Any unrecognised value is dropped at parse time.
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
	publicSupabaseUrl: string;
	publicSupabaseAnonKey: string;
	/** Dev-only escape hatch — see the +server.ts / Lambda gates. */
	bypassPaywallEnabled: boolean;
}

/// Outcome of the caller gate. `'error'` covers every fail-closed branch
/// (missing Supabase config, is_pro RPC failure, rate-limit RPC failure) —
/// the caller answers 500 and the client falls back to the heuristic
/// rather than being granted the perk. `'limited'` is a Pro caller who is
/// over their per-user throttle (issue #339) → 429.
export type ProCheckVerdict = 'pro' | 'free' | 'unauthenticated' | 'limited' | 'error';

/// Per-user throttle on server-side generation (issue #339). This is the
/// heaviest paid path in the app: a single call races REQUEST_MULTIPLIERS ×
/// up to MAX_SEEDS = 32 upstream round_trip fetches against the billed
/// GraphHopper / self-hosted graph_cycle engines. The per-IP AWS WAF rule
/// (100/5min) can't stop a single JWT spreading calls across a small IP
/// pool, so we add a durable per-user ceiling. 60/hour is generous for
/// interactive route-building (a deliberate generate every minute,
/// sustained) while capping a scripted caller at ~60 × 32 ≈ 1920 upstream
/// fetches/hour instead of unbounded. Pro-only path, so no free/pro split.
export const GENERATE_RATE_BUCKET = 'generate-route';
export const GENERATE_RATE_MAX = 60;
export const GENERATE_RATE_WINDOW_S = 3600;

export interface GenerateDeps {
	fetcher?: Fetcher;
	/// Test seam for the tier gate (same pattern as `fetcher`). Defaults to a
	/// real Supabase auth.getUser + is_pro() round trip.
	proChecker?: (accessToken: string) => Promise<ProCheckVerdict>;
}

function supabaseProChecker(config: GenerateConfig) {
	return async (accessToken: string): Promise<ProCheckVerdict> => {
		if (!config.publicSupabaseUrl || !config.publicSupabaseAnonKey) {
			console.error('[generate] missing Supabase config — tier gate cannot run');
			return 'error';
		}
		const supabase = createClient(config.publicSupabaseUrl, config.publicSupabaseAnonKey, {
			global: { headers: { Authorization: `Bearer ${accessToken}` } },
		});
		const userRes = await supabase.auth.getUser(accessToken);
		if (!userRes.data.user) {
			// Mirror the coach handler: log the detail, return a generic
			// verdict so the GoTrue error can't be used as a token-shape oracle.
			console.error('[generate] auth failed', {
				tokenPrefix: accessToken.slice(0, 20) + '...',
				error: userRes.error?.message ?? 'no user returned',
			});
			return 'unauthenticated';
		}
		const proRes = await supabase.rpc('is_pro');
		if (proRes.error) {
			console.error('[generate] is_pro lookup failed', supabaseErrorFields(proRes.error));
			return 'error';
		}
		if (proRes.data !== true) return 'free';

		// Pro confirmed — enforce the per-user throttle on the SAME
		// JWT-bound client (one getUser, guard-satisfying user id). Only
		// Pro callers reach generation, so free callers are never charged
		// a rate-limit slot. Fail-closed: a throttle error denies the paid
		// fan-out (mapped to 'error' → 500) rather than granting it.
		const rl = await checkRouteRateLimit(
			supabase,
			userRes.data.user.id,
			GENERATE_RATE_BUCKET,
			GENERATE_RATE_MAX,
			GENERATE_RATE_WINDOW_S,
		);
		if (rl === 'limited') return 'limited';
		if (rl === 'error') return 'error';
		return 'pro';
	};
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
				/// The road-design preference the serving engine actually applied.
				/// Omitted when none was asked for AND when one was asked for but
				/// couldn't be honoured, so the client can say so rather than
				/// implying every ask lands.
				preferenceApplied?: RoutePreference;
			};
	  }
	| { status: 400 | 401 | 422 | 429 | 500 | 501 | 502; body: { error: string } }
	| { status: 403; body: { error: 'pro_required'; upgrade: true } };

/// The 200 body, derived from GenerateResult so the two engine paths that build
/// one can't drift from the contract they're both returning.
type GenerateBody = Extract<GenerateResult, { status: 200 }>['body'];

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
	if (
		typeof r.preference === 'string' &&
		(ROUTE_PREFERENCES as readonly string[]).includes(r.preference)
	) {
		out.preference = r.preference as RoutePreference;
	}
	return out;
}

export async function handleGenerate(
	authHeader: string | null,
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

	// Pro gate — checked only once an engine is configured (see the header
	// comment: 501 must win so a deploy without engines never upsells). The
	// bypass is honoured only when the wrapper computed it from the dev-only
	// env gates; auth is still required under bypass, mirroring route-describe.
	const accessToken = parseAuthHeader(authHeader);
	if (!accessToken) return { status: 401, body: { error: 'not authenticated' } };
	if (!config.bypassPaywallEnabled) {
		const verdict = await (deps.proChecker ?? supabaseProChecker(config))(accessToken);
		if (verdict === 'unauthenticated') return { status: 401, body: { error: 'not authenticated' } };
		// Fail-closed: an unanswerable tier / throttle check denies the perk
		// (the client falls back to the heuristic) — it never silently grants it.
		if (verdict === 'error') return { status: 500, body: { error: 'tier check failed' } };
		if (verdict === 'free') return { status: 403, body: { error: 'pro_required', upgrade: true } };
		// Per-user throttle tripped (issue #339): deny before racing 32
		// billed upstream fetches. The client falls back to its in-browser
		// heuristic on any non-200, same as the 500 branch above.
		if (verdict === 'limited') return { status: 429, body: { error: 'rate_limited' } };
	}

	const fetcher: Fetcher = deps.fetcher ?? ((u, i) => fetch(u, i));

	// Largest genuinely clean loop the graph-cycle search reported near the start.
	// Surfaced even on a loop-poor (no in-band loop) result so the round_trip
	// fallback below can offer the client an explicit "best loop near you is ~X km"
	// choice instead of a silent out-and-back + a generic shortfall banner.
	let largestCleanM: number | null = null;

	// Whether the graph-cycle call FAILED, as opposed to answering "loop-poor".
	// With no round_trip fallback configured the two ended at the same 502, so a
	// sidecar outage and a cul-de-sac neighbourhood were one signal.
	let graphCycleUnreachable = false;

	// graph-cycle FIRST: search the real foot graph, carrying the preference. A
	// real loop wins; null means loop-poor (or the sidecar is unreachable) and we
	// fall through to round_trip. A sidecar error is never fatal — graph-cycle is a
	// quality upgrade, not a hard dependency — so we swallow the throw and let
	// round_trip serve.
	if (config.graphCycleUrl) {
		const searchGraphCycle = (preference?: RoutePreference) =>
			fetchGraphCycle(
				{
					baseUrl: config.graphCycleUrl,
					start: req.start,
					targetDistanceM: req.targetDistanceM,
					apiKey: config.graphCycleApiKey,
					preference,
				},
				fetcher,
			);
		try {
			const result = await searchGraphCycle(req.preference).catch((e: unknown) => {
				// A sidecar that ANSWERED and refused is a version skew, not an
				// outage: its decoder rejects unknown fields, so one deployed
				// before this preference existed 400s the whole request. Retry
				// once without the preference — the same never-deny rule the
				// round_trip race below applies, and without it a preference is
				// the sole reason a buildable route is denied (a 502, which pages
				// the on-call, on a deploy carrying no round_trip fallback).
				if (
					req.preference &&
					e instanceof GraphCycleError &&
					e.status !== undefined &&
					e.status >= 400 &&
					e.status < 500
				) {
					return searchGraphCycle();
				}
				throw e;
			});
			largestCleanM = result.largestCleanM;
			if (result.loop) {
				const body: GenerateBody = {
					coordinates: result.loop.coordinates,
					distanceM: result.loop.distanceM,
				};
				// Only the sidecar's own verdict, and only where it agrees with the
				// ask: the sidecar retries unweighted when the weighted search comes
				// up empty, and it is a separately deployed service, so neither an
				// echo of req.preference nor a bare echo of its answer can be
				// trusted to describe the loop actually served.
				if (req.preference && result.preferenceApplied === req.preference) {
					body.preferenceApplied = req.preference;
				}
				return { status: 200, body };
			}
		} catch (e) {
			graphCycleUnreachable = true;
			// Unconfigured/unreachable sidecar → fall through to round_trip (or the
			// 502 below if no fallback engine is configured). Log so a prolonged
			// sidecar outage is visible rather than silently degrading every request
			// to the fallback — the request still ends 200, so nothing else would
			// surface it.
			console.warn(
				'[generate] graph_cycle sidecar error, falling back:',
				e instanceof Error ? e.message : String(e),
			);
		}
		if (!config.graphhopperUrl) {
			return graphCycleUnreachable
				? { status: 502, body: { error: 'route engine unavailable' } }
				: { status: 422, body: { error: 'no usable route' } };
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

	// Whether the race that just ran was preference-aware at all. `cul_de_sac` has
	// no custom model, so its race was already the plain one — which is what makes
	// both the claim below and the retry meaningless for it.
	const racedWithModel = req.preference !== undefined && buildCustomModel(req.preference) !== null;

	// What round_trip may claim it honoured: a preference GraphHopper could express
	// as a custom model, whose race is the one that produced these candidates. Read
	// before the retry below, which deliberately drops the preference — a loop found
	// without the model was never shaped by it.
	const roundTripPreference = racedWithModel && candidates.length > 0 ? req.preference : undefined;

	// Graceful fallback: a preference-aware (custom_model) race that produced
	// nothing — the engine rejected the model, or the down-weighting found no loop —
	// must never deny a route the plain generator could build. Retry once without
	// the preference. Layered resilience: the preference is an enhancement, the
	// route itself is the contract. Gated on the model because an unmodelled
	// preference already raced plain: retrying would re-send a byte-identical
	// request, doubling the upstream fan-out exactly when the engine is failing.
	if (racedWithModel && candidates.length === 0) {
		({ candidates, lastError } = await raceRoundTrip(
			req.start,
			req.targetDistanceM,
			seeds,
			config,
			fetcher,
		));
	}

	if (candidates.length === 0) {
		// Every seed failed. An unconfigured engine is an operator problem (501);
		// a `no_route` is the engine ANSWERING that it can't build a loop at this
		// start (422 — the runner's neighbourhood, and the commonest way a
		// loop-poor location used to page the on-call); anything else is the
		// engine being down (502).
		if (lastError instanceof GraphHopperError && lastError.kind === 'unconfigured') {
			return { status: 501, body: { error: 'route generation is not configured' } };
		}
		if (lastError instanceof GraphHopperError && lastError.kind === 'no_route') {
			return { status: 422, body: { error: 'no usable route' } };
		}
		return { status: 502, body: { error: 'route engine unavailable' } };
	}

	// Candidates came back, so the engine is healthy — none was shaped well
	// enough to serve. That is this start's street layout, not an outage.
	const best = pickBestLoop(candidates, req.targetDistanceM);
	if (!best) return { status: 422, body: { error: 'no usable route' } };

	// This loop is a round_trip fallback — graph-cycle found no clean in-band loop
	// near target. If the graph search nonetheless reported a larger genuinely
	// clean loop, surface it so the client can offer "best loop near you is ~X km".
	// Only attach when it's meaningfully (>5%) larger than what we're serving, so
	// we never offer a "better" loop that's the same size as the out-and-back.
	const body: GenerateBody = {
		coordinates: best.coordinates,
		distanceM: best.distanceM,
	};
	if (largestCleanM !== null && largestCleanM > best.distanceM * 1.05) {
		body.largestLoopM = largestCleanM;
	}
	if (roundTripPreference) body.preferenceApplied = roundTripPreference;
	return { status: 200, body };
}
