import { env as publicEnv } from '$env/dynamic/public';
import type { TrackPoint } from './types';

/**
 * Base URL for the OSRM routing service. Defaults to the public demo
 * server (rate-limited, occasionally overloaded); set PUBLIC_OSRM_URL
 * to point at a self-hosted instance (see apps/job_worker/osrm/ for
 * the docker-compose recipe and `npm run dev:run:osrm`). Single source
 * of truth — RouteBuilder.svelte imports OSRM_BASE_URL from here so a
 * future env flip doesn't leave two hardcoded URLs out of sync.
 *
 * Read via `$env/dynamic/public` rather than the static variant so a
 * fresh clone with no local `.env.local` still type-checks — the
 * dynamic API tolerates undeclared keys and returns `undefined`.
 */
export const OSRM_BASE_URL = (publicEnv.PUBLIC_OSRM_URL || 'https://router.project-osrm.org').replace(/\/+$/, '');

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
