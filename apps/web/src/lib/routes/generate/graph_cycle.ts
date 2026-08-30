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
 * `X-Engine-Key` header is forwarded when configured (decisions §45 / §575).
 */

import { ROUTE_PREFERENCES, type Fetcher, type LoopCandidate, type RoutePreference } from './graphhopper';

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
	/// Optional road-design preference, sent verbatim on the request body. The
	/// sidecar weights its own search edges with it and reports back what it
	/// actually managed to apply; an unrecognised value there means no preference,
	/// never a refusal.
	preference?: RoutePreference;
	/// Shared secret sent as `X-Engine-Key`. The sidecar fails closed when its
	/// own key is set and the header is missing/wrong, so omit only in dev where
	/// the guard is permissive.
	apiKey?: string;
	timeoutMs?: number;
}

/// Richer result than a bare loop: the sidecar reports the largest CLEAN loop it
/// found even when no in-band loop near target exists (loop-poor), so a caller
/// can offer "the best loop near you is ~X km" instead of a generic shortfall.
/// `loop` is the in-band loop (null when loop-poor); `largestCleanM` is the
/// largest achievable clean-loop length (null when even that is absent — a
/// genuinely loop-poor start, or `loop` itself is already the largest).
/// `preferenceApplied` is what the sidecar says it actually honoured on the
/// served loop — null both when none was asked for and when one was asked for
/// but its own unweighted retry is what found the loop, so a caller can be honest
/// about an ask it couldn't meet.
export interface GraphCycleResult {
	loop: LoopCandidate | null;
	largestCleanM: number | null;
	preferenceApplied: RoutePreference | null;
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
/// `distanceM`) plus a `found` flag and a separately-parsed `largestClean` (see
/// `parseLargestCleanM`). A measured `preferenceShare` rides onto the returned
/// candidate so the selector can weigh it (see `preferenceFactor` in ./select).
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
	const loop: LoopCandidate = { coordinates, distanceM };
	// A share measures the applied weighting, so it only rides the candidate when
	// the sidecar says the weighting reached this loop — otherwise it would feed
	// the selection score a number about a preference nobody applied.
	if (parsePreferenceApplied(json) !== null) {
		const share = parsePreferenceShare(json);
		if (share !== null) loop.preferenceShare = share;
	}
	return loop;
}

/// Parse the preference the sidecar says it applied to the served loop. Pure.
/// Fail-closed: absent, null, or outside the shared vocabulary all read as "not
/// applied" — a surface must never tell the runner an ask was honoured on the
/// strength of a field it couldn't understand.
export function parsePreferenceApplied(json: unknown): RoutePreference | null {
	const v = (json as { preferenceApplied?: unknown } | null)?.preferenceApplied;
	return typeof v === 'string' && (ROUTE_PREFERENCES as readonly string[]).includes(v)
		? (v as RoutePreference)
		: null;
}

/// Parse the share (0..1) of the served loop's length on preferred edges. Pure.
/// Anything non-numeric or outside the unit interval yields null rather than a
/// clamp: the value feeds a selection score, and a fabricated one would move the
/// choice as confidently as a measured one.
export function parsePreferenceShare(json: unknown): number | null {
	const v = (json as { preferenceShare?: unknown } | null)?.preferenceShare;
	return typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= 1 ? v : null;
}

/// Parse the sidecar's `largestClean` distance. Pure. The sidecar reports
/// `largestClean: { distanceM, ... } | null` in BOTH the found and loop-poor
/// cases — the largest genuinely clean loop near the start regardless of target.
/// Returns its length in metres, or null when absent/malformed. Used to power the
/// loop-poor "best loop near you is ~X km" choice.
export function parseLargestCleanM(json: unknown): number | null {
	const j = json as { largestClean?: { distanceM?: unknown } | null } | null;
	const d = j?.largestClean?.distanceM;
	return typeof d === 'number' && Number.isFinite(d) && d > 0 ? d : null;
}

/// Fetch the best loop near `targetDistanceM` from the sidecar plus the largest
/// achievable clean loop. `loop` is the in-band loop, or null when the sidecar
/// reports loop-poor; `largestCleanM` is the largest clean-loop length the search
/// found (present even when loop-poor) so the caller can offer it explicitly;
/// `preferenceApplied` is what the sidecar honoured, so the caller can tell the
/// runner when an ask went unmet rather than implying every ask lands.
/// Throws `GraphCycleError` on an unconfigured URL or any transport failure
/// (non-2xx, network, timeout, bad JSON) so the handler can fall back to
/// round_trip with the reason intact. Applies a request timeout via
/// `AbortController` so a hung sidecar can't stall the Lambda.
export async function fetchGraphCycle(
	req: GraphCycleRequest,
	fetcher: Fetcher = (u, i) => fetch(u, i),
): Promise<GraphCycleResult> {
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
		const payload: Record<string, unknown> = {
			start: req.start,
			targetDistanceM: req.targetDistanceM,
		};
		if (req.preference) payload.preference = req.preference;
		res = await fetcher(url, {
			method: 'POST',
			headers,
			body: JSON.stringify(payload),
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
	return {
		loop: parseGraphCycle(json),
		largestCleanM: parseLargestCleanM(json),
		preferenceApplied: parsePreferenceApplied(json),
	};
}
