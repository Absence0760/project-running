import { dev } from '$app/environment';
import { env as publicEnv } from '$env/dynamic/public';
import type { TrackPoint } from './types';

/**
 * Base URL for the OSRM routing service.
 *
 * **Dev**: falls back to `https://router.project-osrm.org`, the public
 * community demo. This is convenient locally but it's a third-party
 * service with no DPA, no published region, and an unauthenticated
 * URL — sending production user IPs + waypoints to it is a GDPR Art
 * 28 violation (no processor contract). audit/third-party-data-flows
 * (May 2026) flagged the silent fallback as Critical.
 *
 * **Prod**: `PUBLIC_OSRM_URL` MUST be set (typically pointing at the
 * `apps/job_worker/osrm/` self-hosted instance on Fly.io). If it's
 * absent the routing helpers throw the moment they're called rather
 * than silently leaking traffic to the community endpoint.
 *
 * Read via `$env/dynamic/public` rather than the static variant so a
 * fresh clone with no local `.env.local` still type-checks — the
 * dynamic API tolerates undeclared keys and returns `undefined`.
 */
const PUBLIC_DEMO_OSRM = 'https://router.project-osrm.org';
const RAW_OSRM_URL = publicEnv.PUBLIC_OSRM_URL;

export const OSRM_BASE_URL = (RAW_OSRM_URL || PUBLIC_DEMO_OSRM).replace(/\/+$/, '');

/**
 * Throws when the build is running in production mode AND the env var
 * is unset (or still points at the community demo). Callers invoke
 * this at the top of each fetch helper so a misconfigured deploy
 * fails loudly on the first routing request instead of quietly
 * forwarding user data to an uncontracted third party.
 */
export function assertOsrmConfiguredForProd(): void {
	if (dev) return;
	if (!RAW_OSRM_URL || OSRM_BASE_URL === PUBLIC_DEMO_OSRM) {
		throw new Error(
			'OSRM not configured: set PUBLIC_OSRM_URL to a self-hosted ' +
				'instance. The community endpoint router.project-osrm.org is ' +
				'uncontracted (no DPA) and must not receive production traffic. ' +
				'audit/third-party-data-flows (May 2026).',
		);
	}
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
	assertOsrmConfiguredForProd();
	const url = `${OSRM_BASE_URL}/nearest/v1/${profile}/${point.lng},${point.lat}`;
	const res = await fetch(url);
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
	assertOsrmConfiguredForProd();
	const coords = `${from.lng},${from.lat};${to.lng},${to.lat}`;
	const url = `${OSRM_BASE_URL}/route/v1/${profile}/${coords}?overview=full&geometries=geojson`;

	const res = await fetch(url);
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

	assertOsrmConfiguredForProd();
	const coords = waypoints.map((w) => `${w.lng},${w.lat}`).join(';');
	const url = `${OSRM_BASE_URL}/route/v1/${profile}/${coords}?overview=full&geometries=geojson`;

	const res = await fetch(url);
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
