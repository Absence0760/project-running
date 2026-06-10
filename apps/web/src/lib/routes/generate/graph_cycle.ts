/**
 * Client for the self-hosted graph_cycle map sidecar — the v3 graph-cycle loop
 * generator for "Generate a route by distance"
 * (docs/features/graph_cycle_loop_generation.md).
 *
 * The sidecar (apps/graph_cycle, a Go service) parses the same regional OSM PBF
 * the OSRM/GraphHopper stack uses into a foot graph and searches the REAL street
 * network for a clean loop near the target — tracing the neighbourhood loop that
 * geometry (round_trip, the retired polygon generator) can't find on irregular
 * grids. The handler tries it FIRST and only falls back to round_trip when it
 * returns no loop (loop-poor) or is unreachable.
 *
 * Same seam + privacy posture as graphhopper.ts: the HTTP call is isolated
 * behind an injectable `Fetcher`, the engine URL is a server-only env
 * (`GRAPH_CYCLE_URL`, never `PUBLIC_`) so the browser never calls the sidecar
 * directly and user start-coordinates stay on our infra, and the shared-secret
 * `X-Engine-Key` header is forwarded when configured (decisions §45 / §137).
 */

import type { Fetcher, LoopCandidate } from './graphhopper';

/// Typed transport failure so the handler can distinguish "URL not set" from
/// "sidecar down". Either way the handler falls back to round_trip — graph-cycle
/// is a quality upgrade, not a hard dependency — but the distinction keeps the
/// fallback decision explicit rather than swallowing every error as a non-result.
export class GraphCycleError extends Error {
	constructor(
		readonly kind: 'unconfigured' | 'upstream',
		message: string,
	) {
		super(message);
		this.name = 'GraphCycleError';
	}
}

export interface GraphCycleRequest {
	/// Raw `GRAPH_CYCLE_URL` (may be undefined/empty → unconfigured error).
	baseUrl: string | undefined;
	start: { lat: number; lng: number };
	/// The user's target loop length in metres. Unlike round_trip's
	/// `requestDistanceM`, this is the ACTUAL target — the sidecar samples its own
	/// spread of far-points internally and returns the loop closest to it.
	targetDistanceM: number;
	/// Shared secret sent as `X-Engine-Key`. The sidecar fails closed when its
	/// own key is set and the header is missing/wrong, so omit only in dev where
	/// the guard is permissive.
	apiKey?: string;
	timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 8000;

/// Build the sidecar `/cycle` URL. The request is a POST with a JSON body (see
/// `fetchGraphCycle`); this only assembles the path.
export function buildGraphCycleUrl(baseUrl: string): string {
	return `${baseUrl.replace(/\/+$/, '')}/cycle`;
}

/// Parse a sidecar `/cycle` response into a candidate loop. Pure. Returns null
/// when the sidecar reports `found: false` (a genuinely loop-poor start) or the
/// payload is malformed — both cases the handler turns into a round_trip
/// fallback. The wire shape matches LoopCandidate (`coordinates` [lng,lat],
/// `distanceM`) plus a `found` flag and an unused-here `largestClean`.
export function parseGraphCycle(json: unknown): LoopCandidate | null {
	const j = json as
		| { found?: unknown; coordinates?: unknown; distanceM?: unknown }
		| null;
	if (!j || j.found !== true || !Array.isArray(j.coordinates)) return null;
	const coordinates: [number, number][] = [];
	for (const c of j.coordinates) {
		if (!Array.isArray(c) || c.length < 2) continue;
		const lng = Number(c[0]);
		const lat = Number(c[1]);
		if (!Number.isFinite(lng) || !Number.isFinite(lat)) continue;
		coordinates.push([lng, lat]);
	}
	if (coordinates.length < 2) return null;
	const distanceM =
		typeof j.distanceM === 'number' && Number.isFinite(j.distanceM) ? j.distanceM : 0;
	if (distanceM <= 0) return null;
	return { coordinates, distanceM };
}

/// Fetch the best loop near `targetDistanceM` from the sidecar. Returns the loop
/// on success, or null when the sidecar reports loop-poor. Throws
/// `GraphCycleError` on an unconfigured URL or any transport failure (non-2xx,
/// network, timeout, bad JSON) so the handler can fall back to round_trip with
/// the reason intact. Applies a request timeout via `AbortController` so a hung
/// sidecar can't stall the Lambda.
export async function fetchGraphCycle(
	req: GraphCycleRequest,
	fetcher: Fetcher = (u, i) => fetch(u, i),
): Promise<LoopCandidate | null> {
	const base = (req.baseUrl ?? '').replace(/\/+$/, '');
	if (!base) {
		throw new GraphCycleError('unconfigured', 'GRAPH_CYCLE_URL is not set');
	}
	const url = buildGraphCycleUrl(base);
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), req.timeoutMs ?? DEFAULT_TIMEOUT_MS);
	let res: Response;
	try {
		const headers: Record<string, string> = { 'content-type': 'application/json' };
		if (req.apiKey) headers['X-Engine-Key'] = req.apiKey;
		res = await fetcher(url, {
			method: 'POST',
			headers,
			body: JSON.stringify({ start: req.start, targetDistanceM: req.targetDistanceM }),
			signal: controller.signal,
		});
	} catch (e) {
		throw new GraphCycleError(
			'upstream',
			`graph_cycle request failed: ${e instanceof Error ? e.message : String(e)}`,
		);
	} finally {
		clearTimeout(timer);
	}
	if (!res.ok) {
		throw new GraphCycleError('upstream', `graph_cycle returned ${res.status}`);
	}
	let json: unknown;
	try {
		json = await res.json();
	} catch (e) {
		throw new GraphCycleError(
			'upstream',
			`graph_cycle returned non-JSON: ${e instanceof Error ? e.message : String(e)}`,
		);
	}
	return parseGraphCycle(json);
}
