import { supabase } from '../core/supabase';

/**
 * Client for the OSRM waypoint-routing proxy.
 *
 * The browser never talks to the OSRM host: every snapping/routing call goes
 * to `/api/routes/osrm/*` — the dev SvelteKit wrapper locally, the osrm-proxy
 * Lambda in production — and the OSRM base URL (`OSRM_URL`) is server-only,
 * matching the generate-route path's `GRAPHHOPPER_URL` posture. A user's pin
 * coordinates (routinely their home) therefore never leave our infra
 * unproxied, and there is no client-side env to misconfigure toward the
 * uncontracted community demo — that guard lives in the proxy handler now.
 * See decisions §242 / issue #198.
 */
export const OSRM_PROXY_BASE = '/api/routes/osrm';

/**
 * Issue a GET against the proxy, carrying the viewer JWT in
 * `x-supabase-authorization` (CloudFront's OAC owns `Authorization`, same as
 * the generate/coach endpoints). A failed session read just sends no header —
 * the proxy answers 401 and the caller takes its normal failure path.
 *
 * `pathAndQuery` is the OSRM-shaped remainder, e.g.
 * `/route/v1/foot/2.35,48.85;2.36,48.86?overview=full&geometries=geojson`.
 */
export async function osrmProxyFetch(
	pathAndQuery: string,
	init: { signal?: AbortSignal } = {},
): Promise<Response> {
	let token: string | undefined;
	try {
		token = (await supabase.auth.getSession()).data.session?.access_token;
	} catch {
		token = undefined;
	}
	return fetch(`${OSRM_PROXY_BASE}${pathAndQuery}`, {
		headers: token ? { 'x-supabase-authorization': `Bearer ${token}` } : {},
		signal: init.signal,
	});
}
