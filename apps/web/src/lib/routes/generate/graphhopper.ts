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

export interface RoundTripRequest {
	/// Raw `GRAPHHOPPER_URL` (may be undefined/empty → unconfigured error).
	baseUrl: string | undefined;
	start: { lat: number; lng: number };
	targetDistanceM: number;
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

/// GraphHopper's round_trip systematically returns loops SHORTER than the
/// requested `round_trip.distance` — it places via-points on a circle of the
/// requested radius and the road path between them cuts the chord. Measured
/// against the foot profile across 2-12 km and many seeds, returned/requested
/// clustered around a 0.84 median (a ~16% undershoot). So we ask the engine for
/// target × this factor; the returned distances then centre on the user's real
/// target. This nudges only the REQUEST — candidate.distanceM stays the actual
/// returned length and selection still compares against the un-inflated target,
/// so an over/undershooting seed is judged honestly and the ±15% warning band
/// fires on the real result. Tunable; re-measure if the profile or engine
/// version changes.
export const ROUND_TRIP_DISTANCE_INFLATION = 1.18;

export function buildRoundTripUrl(req: RoundTripRequest): string {
	const base = (req.baseUrl ?? '').replace(/\/+$/, '');
	const params = new URLSearchParams({
		profile: 'foot',
		point: `${req.start.lat},${req.start.lng}`,
		algorithm: 'round_trip',
		'round_trip.distance': String(Math.round(req.targetDistanceM * ROUND_TRIP_DISTANCE_INFLATION)),
		'round_trip.seed': String(req.seed),
		points_encoded: 'false',
		instructions: 'false',
		elevation: 'false',
	});
	return `${base}/route?${params.toString()}`;
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
	const url = buildRoundTripUrl(req);
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), req.timeoutMs ?? DEFAULT_TIMEOUT_MS);
	let res: Response;
	try {
		const init: RequestInit = { signal: controller.signal };
		if (req.apiKey) init.headers = { 'X-Engine-Key': req.apiKey };
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
