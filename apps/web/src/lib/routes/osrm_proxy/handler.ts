/**
 * Transport-agnostic core for the OSRM waypoint-routing proxy.
 *
 * Wrapped twice — once by the SvelteKit dev route
 * (`src/routes/api/routes/osrm/[...path]/+server.ts`) and once by the
 * production AWS Lambda (`apps/web/lambda/osrm-proxy/src/index.ts`) —
 * mirroring the generate-route handler's two-wrapper shape (decisions §53).
 *
 * Why this exists: the route builder's manual-waypoint snapping/routing used
 * to call the OSRM host directly from the browser over a `PUBLIC_` env, so a
 * user's exact pin coordinates (routinely their home) left the client with no
 * server boundary in between — the exact exposure the GraphHopper hop was
 * built to prevent on the generate path. `OSRM_URL` is server-only; the
 * browser only ever sees `/api/routes/osrm/*` (decisions §242, issue #198).
 *
 * The proxy mirrors OSRM's own GET path shape
 * (`/{nearest|route}/v1/{foot|car}/{lng,lat;...}?…`) so the client's response
 * parsing — and the Playwright mocks that match `/route/v1/foot/` by path —
 * carry over unchanged. Nothing is forwarded verbatim: the upstream URL is
 * rebuilt from validated parts (service/profile/coordinates enumerated and
 * range-checked, query params allowlisted), so the Lambda can never be used
 * as an open relay to arbitrary hosts or OSRM services.
 *
 * Fail-closed: no `OSRM_URL` → 501 (the demo fallback is dev-wrapper-only via
 * `allowDemoFallback`; the Lambda hard-codes it false so production can never
 * leak coordinates to the uncontracted community endpoint — the same posture
 * as `assertOsrmConfiguredForProd` had client-side, now enforced where the
 * config lives). Callers must be signed in: an anonymous proxy in front of
 * the self-hosted engine would be a free relay for anyone on the internet.
 */

import { createClient } from '@supabase/supabase-js';

import { parseAuthHeader } from '../../coach/limits';
import { checkRouteRateLimit } from '../rate_limit';

export const OSRM_DEMO_URL = 'https://router.project-osrm.org';

/// Per-user throttle on the OSRM waypoint proxy (issue #339). The proxy
/// is signed-in-only by design (an anonymous relay in front of the
/// self-hosted engine would be a free relay for anyone on the internet —
/// see the header comment), so this is a per-user ceiling, not the
/// anon+authenticated split clip-public-track uses. The builder fires one
/// proxied call per waypoint segment, so the ceiling has to absorb a heavy
/// interactive session while still bounding a single JWT the per-IP WAF
/// (600/5min) can't stop across an IP pool. 1200/hour ≈ 20 calls/min
/// sustained — comfortably above real builder traffic, a hard cap on a
/// scripted relay.
export const OSRM_RATE_BUCKET = 'osrm-proxy';
export const OSRM_RATE_MAX = 1200;
export const OSRM_RATE_WINDOW_S = 3600;

/// Ceilings on a single proxied call. The builder routes segments pairwise
/// and its multi-waypoint full-route call carries one coordinate per pin —
/// 60 is far past any real builder session while still bounding the upstream
/// URL we construct.
export const MAX_ROUTE_COORDS = 60;
export const MAX_SNAP_RADIUS_M = 10_000;

const UPSTREAM_TIMEOUT_MS = 10_000;

export type Fetcher = (url: string, init?: RequestInit) => Promise<Response>;

/// Outcome of the caller gate. `'error'` covers the fail-closed branches
/// (missing Supabase config, GoTrue unreachable, rate-limit RPC failure) —
/// the caller answers 500, never silently waves the request through.
/// `'limited'` is a signed-in caller over their per-user throttle (issue
/// #339) → 429.
export type AuthVerdict = 'ok' | 'unauthenticated' | 'limited' | 'error';

export interface OsrmProxyConfig {
	/// Server-only OSRM base URL (`OSRM_URL`). Unset → 501 unless
	/// `allowDemoFallback` (dev wrapper only) is true.
	osrmUrl: string | undefined;
	/// True ONLY in the dev SvelteKit wrapper (and only outside production
	/// mode): an unset `OSRM_URL` falls back to the public community demo for
	/// local convenience. The Lambda passes false, always.
	allowDemoFallback: boolean;
	publicSupabaseUrl: string;
	publicSupabaseAnonKey: string;
}

export interface OsrmProxyDeps {
	fetcher?: Fetcher;
	/// Test seam for the auth gate (same pattern as the generate handler's
	/// `proChecker`). Defaults to a real Supabase `auth.getUser` round trip.
	authChecker?: (accessToken: string) => Promise<AuthVerdict>;
}

export type OsrmProxyResult =
	| { status: 200; body: unknown }
	| { status: 400 | 401 | 422 | 429 | 500 | 501 | 502; body: { error: string } };

interface ParsedOsrmPath {
	service: 'nearest' | 'route';
	profile: 'foot' | 'car';
	coords: [number, number][];
}

function isValidLngLat(lng: number, lat: number): boolean {
	return Number.isFinite(lng) && Number.isFinite(lat) && Math.abs(lng) <= 180 && Math.abs(lat) <= 90;
}

/// Parse the OSRM-shaped sub-path (`{service}/v1/{profile}/{lng,lat;...}`).
/// Returns null on anything that isn't exactly a supported service/profile
/// with well-formed in-range coordinates; the caller turns that into a 400.
export function parseOsrmProxyPath(path: string): ParsedOsrmPath | null {
	const m = path.replace(/^\/+/, '').match(/^(nearest|route)\/v1\/(foot|car)\/([^/]+)$/);
	if (!m) return null;
	const service = m[1] as ParsedOsrmPath['service'];
	const profile = m[2] as ParsedOsrmPath['profile'];
	const coords: [number, number][] = [];
	for (const pair of m[3].split(';')) {
		const parts = pair.split(',');
		if (parts.length !== 2) return null;
		const lng = Number(parts[0]);
		const lat = Number(parts[1]);
		if (parts[0].trim() === '' || parts[1].trim() === '' || !isValidLngLat(lng, lat)) return null;
		coords.push([lng, lat]);
	}
	if (service === 'nearest' && coords.length !== 1) return null;
	if (service === 'route' && (coords.length < 2 || coords.length > MAX_ROUTE_COORDS)) return null;
	return { service, profile, coords };
}

/// Rebuild the query string from the allowlist. Unknown params are dropped
/// (never forwarded); a recognised param with an invalid value is a 400 so a
/// buggy client fails loudly instead of silently changing meaning upstream.
export function buildUpstreamQuery(
	parsed: ParsedOsrmPath,
	query: Record<string, string | undefined>,
): string | null {
	const out = new URLSearchParams();

	if (query.number !== undefined) {
		if (parsed.service !== 'nearest' || !/^\d+$/.test(query.number)) return null;
		const n = Number(query.number);
		if (n < 1 || n > 10) return null;
		out.set('number', String(n));
	}

	if (query.radiuses !== undefined) {
		const entries = query.radiuses.split(';');
		if (entries.length !== parsed.coords.length) return null;
		for (const e of entries) {
			if (!/^\d+(\.\d+)?$/.test(e)) return null;
			const r = Number(e);
			if (r <= 0 || r > MAX_SNAP_RADIUS_M) return null;
		}
		out.set('radiuses', entries.map((e) => String(Number(e))).join(';'));
	}

	if (query.overview !== undefined) {
		if (!['full', 'simplified', 'false'].includes(query.overview)) return null;
		out.set('overview', query.overview);
	}

	if (query.geometries !== undefined) {
		if (!['geojson', 'polyline', 'polyline6'].includes(query.geometries)) return null;
		out.set('geometries', query.geometries);
	}

	const s = out.toString();
	return s.length > 0 ? `?${s}` : '';
}

function supabaseAuthChecker(config: OsrmProxyConfig) {
	return async (accessToken: string): Promise<AuthVerdict> => {
		if (!config.publicSupabaseUrl || !config.publicSupabaseAnonKey) {
			console.error('[osrm-proxy] missing Supabase config — auth gate cannot run');
			return 'error';
		}
		const supabase = createClient(config.publicSupabaseUrl, config.publicSupabaseAnonKey, {
			global: { headers: { Authorization: `Bearer ${accessToken}` } },
		});
		const userRes = await supabase.auth.getUser(accessToken);
		if (!userRes.data.user) {
			// Log the detail, return a generic verdict so the GoTrue error can't
			// be used as a token-shape oracle (mirrors the coach handler).
			console.error('[osrm-proxy] auth failed', {
				error: userRes.error?.message ?? 'no user returned',
			});
			return 'unauthenticated';
		}

		// Signed-in — enforce the per-user throttle on the SAME JWT-bound
		// client (one getUser, guard-satisfying user id). Fail-closed: a
		// throttle error denies (mapped to 'error' → 500) rather than
		// leaving the engine relay unbounded per JWT.
		const rl = await checkRouteRateLimit(
			supabase,
			userRes.data.user.id,
			OSRM_RATE_BUCKET,
			OSRM_RATE_MAX,
			OSRM_RATE_WINDOW_S,
		);
		if (rl === 'limited') return 'limited';
		if (rl === 'error') return 'error';
		return 'ok';
	};
}

export async function handleOsrmProxy(
	authHeader: string | null,
	path: string,
	query: Record<string, string | undefined>,
	config: OsrmProxyConfig,
	deps: OsrmProxyDeps = {},
): Promise<OsrmProxyResult> {
	const parsed = parseOsrmProxyPath(path);
	if (!parsed) return { status: 400, body: { error: 'unsupported OSRM path' } };
	const upstreamQuery = buildUpstreamQuery(parsed, query);
	if (upstreamQuery === null) return { status: 400, body: { error: 'invalid query parameter' } };

	// 501 before the auth gate, mirroring generate-route: an unconfigured
	// deploy answers "not available" without burning a GoTrue round trip.
	const baseUrl = config.osrmUrl?.replace(/\/+$/, '') || (config.allowDemoFallback ? OSRM_DEMO_URL : undefined);
	if (!baseUrl) return { status: 501, body: { error: 'waypoint routing is not configured' } };

	const accessToken = parseAuthHeader(authHeader);
	if (!accessToken) return { status: 401, body: { error: 'not authenticated' } };
	const verdict = await (deps.authChecker ?? supabaseAuthChecker(config))(accessToken);
	if (verdict === 'unauthenticated') return { status: 401, body: { error: 'not authenticated' } };
	// Per-user throttle tripped (issue #339): deny before proxying to the
	// engine. The builder treats any non-200 as a failed segment (straight-
	// line fallback), same as the 502 branch below.
	if (verdict === 'limited') return { status: 429, body: { error: 'rate_limited' } };
	if (verdict === 'error') return { status: 500, body: { error: 'auth check failed' } };

	const coordsStr = parsed.coords.map(([lng, lat]) => `${lng},${lat}`).join(';');
	const url = `${baseUrl}/${parsed.service}/v1/${parsed.profile}/${coordsStr}${upstreamQuery}`;
	const fetcher: Fetcher = deps.fetcher ?? ((u, i) => fetch(u, i));

	try {
		const res = await fetcher(url, { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
		if (!res.ok) {
			// An OSRM 4xx means the engine ANSWERED and rejected these
			// coordinates — `NoSegment` for a pin outside the loaded extract, or
			// off any routable way. That is the caller's geography, not an
			// outage, and it must not reach the `engine_unreachable` log line the
			// Lambda emits on a 502: a user dropping one pin in the sea would
			// otherwise raise "the OSRM engine is unreachable, all users
			// degraded". The engine's own status/code stays internal; 422 is the
			// stable app-level signal.
			if (res.status >= 400 && res.status < 500) {
				return { status: 422, body: { error: 'no_route_for_coordinates' } };
			}
			return { status: 502, body: { error: 'routing engine unavailable' } };
		}
		return { status: 200, body: await res.json() };
	} catch (e) {
		console.warn('[osrm-proxy] upstream error:', e instanceof Error ? e.message : String(e));
		return { status: 502, body: { error: 'routing engine unavailable' } };
	}
}
