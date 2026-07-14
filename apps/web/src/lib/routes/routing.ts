import { supabase } from '../core/supabase';
import type { TrackPoint } from '../types';

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

interface OsrmRoute {
	geometry: {
		coordinates: [number, number][];
	};
	distance: number;
	duration: number;
}

interface OsrmWaypoint {
	location: [number, number]; // [lng, lat] snapped to road
}

interface OsrmResponse {
	code: string;
	routes: OsrmRoute[];
	waypoints?: OsrmWaypoint[];
}

/**
 * Snap a point to the nearest road using OSRM's nearest service.
 * Returns the snapped [lng, lat] position.
 */
export async function snapToRoad(
	point: { lng: number; lat: number },
	profile: 'foot' | 'car' = 'foot'
): Promise<[number, number]> {
	const res = await osrmProxyFetch(`/nearest/v1/${profile}/${point.lng},${point.lat}`);
	if (!res.ok) return [point.lng, point.lat];

	const data = await res.json();
	if (data.code === 'Ok' && data.waypoints?.[0]?.location) {
		return data.waypoints[0].location;
	}
	return [point.lng, point.lat];
}

/**
 * Fetch a road-snapped route between two points using OSRM.
 * Profile: 'foot' for trail mode, 'car' for road mode.
 * Returns the snapped coordinates, distance, and snapped waypoint positions.
 */
export async function fetchRoute(
	from: TrackPoint,
	to: TrackPoint,
	profile: 'foot' | 'car' = 'foot'
): Promise<{ coordinates: [number, number][]; distance: number; snappedFrom: [number, number]; snappedTo: [number, number] }> {
	const coords = `${from.lng},${from.lat};${to.lng},${to.lat}`;
	const res = await osrmProxyFetch(`/route/v1/${profile}/${coords}?overview=full&geometries=geojson`);
	if (!res.ok) throw new Error(`OSRM error: ${res.status}`);

	const data: OsrmResponse = await res.json();
	if (data.code !== 'Ok' || data.routes.length === 0) {
		throw new Error(`OSRM: no route found`);
	}

	const route = data.routes[0];
	const snappedFrom = data.waypoints?.[0]?.location ?? [from.lng, from.lat];
	const snappedTo = data.waypoints?.[1]?.location ?? [to.lng, to.lat];

	return {
		coordinates: route.geometry.coordinates,
		distance: route.distance,
		snappedFrom,
		snappedTo
	};
}

/**
 * Fetch a full route through multiple waypoints in one OSRM call.
 */
export async function fetchFullRoute(
	waypoints: TrackPoint[],
	profile: 'foot' | 'car' = 'foot'
): Promise<{ coordinates: [number, number][]; distance: number }> {
	if (waypoints.length < 2) {
		return { coordinates: [], distance: 0 };
	}

	const coords = waypoints.map((w) => `${w.lng},${w.lat}`).join(';');
	const res = await osrmProxyFetch(`/route/v1/${profile}/${coords}?overview=full&geometries=geojson`);
	if (!res.ok) throw new Error(`OSRM error: ${res.status}`);

	const data: OsrmResponse = await res.json();
	if (data.code !== 'Ok' || data.routes.length === 0) {
		throw new Error(`OSRM: no route found`);
	}

	const route = data.routes[0];
	return {
		coordinates: route.geometry.coordinates,
		distance: route.distance
	};
}
