/**
 * GraphHopper `round_trip` client for the server-side "Generate a route by
 * distance" loop generator.
 *
 * GraphHopper's `algorithm=round_trip` is purpose-built for this: given a
 * point, a target distance, and a seed, it returns a loop close to that
 * distance in a single engine call — no client-side radial scaffold + bisect
 * dance (the old in-browser `route_loop.ts` heuristic that overshot when the
 * road network was lopsided). Vary the seed to get differently-shaped loops;
 * `select.ts` picks the best-shaped one.
 *
 * The HTTP call is isolated behind an injectable `fetcher` (the seam, like
 * `routing.ts` / `food_search.ts`) so the parse + selection logic is
 * unit-testable without network. Self-hosted only — the engine URL is a
 * server-only env (`GRAPHHOPPER_URL`); the browser never calls GraphHopper
 * directly, so user start-coordinates never leave our infra (privacy parity
 * with the OSRM self-host, decisions §45).
 */

export type Fetcher = (url: string, init?: RequestInit) => Promise<Response>;

/// A single candidate loop returned by one round_trip seed.
export interface LoopCandidate {
	/// GeoJSON `[lng, lat]` order — matches OSRM + the route builder's
	/// `routeCoordinates`, so the client can render it without conversion.
	coordinates: [number, number][];
	/// Engine-reported path length in metres.
	distanceM: number;
}

/// Typed failure so wrappers can map "unconfigured" → 501 (operator must set
/// GRAPHHOPPER_URL) distinctly from "upstream"/"no_route" → 502 (engine down
/// or couldn't build a loop here).
export class GraphHopperError extends Error {
	constructor(
		readonly kind: 'unconfigured' | 'upstream' | 'no_route',
		message: string,
	) {
		super(message);
		this.name = 'GraphHopperError';
	}
}

/// Optional road-design preference biasing the loop toward quieter streets.
/// `'quiet'` down-weights motorway/trunk/primary (+ their `_link`s) and
/// up-weights residential/living_street via a GraphHopper `custom_model`. Any
/// other value (or none) → today's behaviour: a plain `round_trip` GET, no model.
/// This is the cheap avoid-highways / prefer-residential half of the route-design
/// preferences in graph_cycle_loop_generation.md § Extension.
export type RoutePreference = 'quiet';

/// GraphHopper Custom Model `priority` clause shape. Only the subset we emit.
interface PriorityClause {
	if?: string;
	else_if?: string;
	multiply_by: number;
}

interface CustomModel {
	priority: PriorityClause[];
}

/// Build the GraphHopper `custom_model` for a preference. Returns null for any
/// preference we don't model (caller then sends the plain GET round_trip). Pure +
/// exported so the priority rules are unit-tested without a network round-trip.
///
/// `road_class` is GraphHopper's encoded-value name; the multipliers are soft
/// weights (never 0) so the loop is biased onto residential streets but the graph
/// can't be disconnected into a no_route — over-filtering would defeat the
/// "a preference must never break generation" contract.
export function buildCustomModel(pref: RoutePreference | undefined): CustomModel | null {
	if (pref !== 'quiet') return null;
	return {
		priority: [
			{ if: 'road_class == MOTORWAY', multiply_by: 0.1 },
			{ else_if: 'road_class == TRUNK', multiply_by: 0.2 },
			{ else_if: 'road_class == PRIMARY', multiply_by: 0.4 },
			{ if: 'road_class == RESIDENTIAL', multiply_by: 1.4 },
			{ else_if: 'road_class == LIVING_STREET', multiply_by: 1.5 },
		],
	};
}

export interface RoundTripRequest {
	/// Raw `GRAPHHOPPER_URL` (may be undefined/empty → unconfigured error).
	baseUrl: string | undefined;
	/// Optional road-design preference (see RoutePreference). When set to a value
	/// we model, the request becomes a POST carrying a `custom_model` (CH is
	/// disabled engine-side for custom models); otherwise it's the plain GET.
	preference?: RoutePreference;
	start: { lat: number; lng: number };
	/// The distance to ASK the engine for (`round_trip.distance`) — NOT
	/// necessarily the user's target. The handler races a spread of these around
	/// the target (REQUEST_MULTIPLIERS) and keeps the actual result closest to it.
	requestDistanceM: number;
	/// `round_trip.seed` — same start + distance + seed is deterministic;
	/// different seeds radiate the loop in different directions.
	seed: number;
	/// Shared secret sent as `X-Engine-Key`. The self-hosted GraphHopper sits
	/// behind a public Fly endpoint (the AWS Lambda can't reach it over Fly's
	/// 6PN), so a header guard keeps anyone who learns the hostname from hitting
	/// it directly and bypassing the CloudFront WAF rate-limit. Omitted → no
	/// header (dev with the guard in permissive mode).
	apiKey?: string;
	timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 8000;

/// `round_trip.distance` is whatever the caller passes in `requestDistanceM`.
/// round_trip's actual/requested ratio swings wildly by location — a 5 km ask
/// returns ~4.3 km at one start and ~6.4 km at another ~30 m away — so no fixed
/// factor centres both. The handler races a SPREAD of request distances
/// (REQUEST_MULTIPLIERS × target) and keeps the actual result closest to target
/// (see handler.ts + ./select). An earlier flat ×1.18 inflation was removed for
/// the same reason: it helped undershooting networks but made overshooting ones
/// far worse. Re-measure if the profile or engine version changes.
export function buildRoundTripUrl(req: RoundTripRequest): string {
	const base = (req.baseUrl ?? '').replace(/\/+$/, '');
	const params = new URLSearchParams({
		profile: 'foot',
		point: `${req.start.lat},${req.start.lng}`,
		algorithm: 'round_trip',
		'round_trip.distance': String(Math.round(req.requestDistanceM)),
		'round_trip.seed': String(req.seed),
		points_encoded: 'false',
		instructions: 'false',
		elevation: 'false',
	});
	return `${base}/route?${params.toString()}`;
}

/// JSON POST body for a custom-model round_trip. GraphHopper only honours a
/// `custom_model` over POST with Contraction Hierarchies disabled (`ch.disable`),
/// so the preference path can't reuse the GET URL — it carries every round_trip
/// param as body fields instead. Pure + exported for unit testing.
export function buildRoundTripBody(req: RoundTripRequest, model: CustomModel): Record<string, unknown> {
	return {
		profile: 'foot',
		points: [[req.start.lng, req.start.lat]],
		'ch.disable': true,
		custom_model: model,
		algorithm: 'round_trip',
		'round_trip.distance': Math.round(req.requestDistanceM),
		'round_trip.seed': req.seed,
		points_encoded: false,
		instructions: false,
		elevation: false,
	};
}

/// Parse a GraphHopper route response into a candidate. Pure. Returns null
/// when the response carries no usable path (engine couldn't build a loop).
export function parseRoundTrip(json: unknown): LoopCandidate | null {
	const paths = (json as { paths?: unknown[] } | null)?.paths;
	if (!Array.isArray(paths) || paths.length === 0) return null;
	const p = paths[0] as Record<string, unknown>;
	const points = p.points as { coordinates?: unknown } | undefined;
	const raw = points?.coordinates;
	if (!Array.isArray(raw)) return null;
	const coordinates: [number, number][] = [];
	for (const c of raw) {
		if (!Array.isArray(c) || c.length < 2) continue;
		const lng = Number(c[0]);
		const lat = Number(c[1]);
		if (!Number.isFinite(lng) || !Number.isFinite(lat)) continue;
		coordinates.push([lng, lat]);
	}
	if (coordinates.length < 2) return null;
	const distanceM =
		typeof p.distance === 'number' && Number.isFinite(p.distance) ? p.distance : 0;
	return { coordinates, distanceM };
}

/// Fetch one round_trip loop. Throws `GraphHopperError` on unconfigured URL,
/// non-2xx upstream, or an empty path. Applies a request timeout via
/// `AbortController` so a hung engine can't stall the Lambda.
export async function fetchRoundTrip(
	req: RoundTripRequest,
	fetcher: Fetcher = (u, i) => fetch(u, i),
): Promise<LoopCandidate> {
	const base = (req.baseUrl ?? '').replace(/\/+$/, '');
	if (!base) {
		throw new GraphHopperError('unconfigured', 'GRAPHHOPPER_URL is not set');
	}
	// A modelled preference posts a custom_model body to `/route`; everything else
	// stays the plain GET so the default path is byte-for-byte today's request.
	const model = buildCustomModel(req.preference);
	const url = model ? `${base}/route` : buildRoundTripUrl(req);
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), req.timeoutMs ?? DEFAULT_TIMEOUT_MS);
	let res: Response;
	try {
		const init: RequestInit = { signal: controller.signal };
		const headers: Record<string, string> = {};
		if (req.apiKey) headers['X-Engine-Key'] = req.apiKey;
		if (model) {
			init.method = 'POST';
			headers['content-type'] = 'application/json';
			init.body = JSON.stringify(buildRoundTripBody(req, model));
		}
		if (Object.keys(headers).length > 0) init.headers = headers;
		res = await fetcher(url, init);
	} catch (e) {
		throw new GraphHopperError(
			'upstream',
			`GraphHopper request failed: ${e instanceof Error ? e.message : String(e)}`,
		);
	} finally {
		clearTimeout(timer);
	}
	if (!res.ok) {
		throw new GraphHopperError('upstream', `GraphHopper returned ${res.status}`);
	}
	let json: unknown;
	try {
		json = await res.json();
	} catch (e) {
		throw new GraphHopperError(
			'upstream',
			`GraphHopper returned non-JSON: ${e instanceof Error ? e.message : String(e)}`,
		);
	}
	const candidate = parseRoundTrip(json);
	if (!candidate) {
		throw new GraphHopperError('no_route', 'GraphHopper returned no usable path');
	}
	return candidate;
}
