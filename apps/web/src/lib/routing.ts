import type { TrackPoint } from './types';

const OSRM_BASE = 'https://router.project-osrm.org';

interface OsrmRoute {
	geometry: {
		coordinates: [number, number][];
	};
	distance: number;
	duration: number;
}

interface OsrmResponse {
	code: string;
	routes: OsrmRoute[];
}

/**
 * Fetch a road-snapped route between two points using OSRM.
 * Profile: 'foot' for trail mode, 'car' for road mode.
 * Returns the snapped coordinates and segment distance in metres.
 */
export async function fetchRoute(
	from: TrackPoint,
	to: TrackPoint,
	profile: 'foot' | 'car' = 'foot'
): Promise<{ coordinates: [number, number][]; distance: number }> {
	const coords = `${from.lng},${from.lat};${to.lng},${to.lat}`;
	const url = `${OSRM_BASE}/route/v1/${profile}/${coords}?overview=full&geometries=geojson`;

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
	const url = `${OSRM_BASE}/route/v1/${profile}/${coords}?overview=full&geometries=geojson`;

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
