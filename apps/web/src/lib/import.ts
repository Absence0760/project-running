/**
 * Route file import — parses GPX, KML, KMZ, and GeoJSON into a common format.
 * Supports files exported from Google Maps, Google Earth, Strava, Garmin, etc.
 */
import JSZip from 'jszip';
import type { TrackPoint } from './types';

export interface ImportedRoute {
	name: string;
	waypoints: TrackPoint[];
	distance_m: number;
	elevation_m: number | null;
}

/**
 * Parse a route file. Detects format from filename extension.
 */
export async function parseRouteFile(file: File): Promise<ImportedRoute> {
	const ext = file.name.split('.').pop()?.toLowerCase();

	if (ext === 'gpx') {
		const text = await file.text();
		return parseGpx(text);
	}

	if (ext === 'kml') {
		const text = await file.text();
		return parseKml(text);
	}

	if (ext === 'kmz') {
		return parseKmz(file);
	}

	if (ext === 'geojson' || ext === 'json') {
		const text = await file.text();
		return parseGeoJson(text);
	}

	throw new Error(`Unsupported file format: .${ext}. Use GPX, KML, KMZ, or GeoJSON.`);
}

// --- GPX ---

function parseGpx(xml: string): ImportedRoute {
	const doc = new DOMParser().parseFromString(xml, 'text/xml');
	const name = doc.querySelector('trk > name')?.textContent
		?? doc.querySelector('metadata > name')?.textContent
		?? 'Imported Route';

	// Try track points first, then route points, then waypoints
	let points = Array.from(doc.querySelectorAll('trkpt'));
	if (points.length === 0) points = Array.from(doc.querySelectorAll('rtept'));
	if (points.length === 0) points = Array.from(doc.querySelectorAll('wpt'));

	if (points.length === 0) {
		throw new Error('GPX file contains no track, route, or waypoints');
	}

	const waypoints: TrackPoint[] = points.map((pt) => ({
		lat: parseFloat(pt.getAttribute('lat') ?? '0'),
		lng: parseFloat(pt.getAttribute('lon') ?? '0'),
		ele: parseFloat(pt.querySelector('ele')?.textContent ?? '0') || undefined,
	}));

	return buildRoute(name, waypoints);
}

// --- KML ---

function parseKml(xml: string): ImportedRoute {
	const doc = new DOMParser().parseFromString(xml, 'text/xml');
	const name = doc.querySelector('Document > name')?.textContent
		?? doc.querySelector('Placemark > name')?.textContent
		?? 'Imported Route';

	// Extract coordinates from LineString or Point elements
	const coordElements = doc.querySelectorAll('coordinates');
	const waypoints: TrackPoint[] = [];

	coordElements.forEach((el) => {
		const text = el.textContent?.trim() ?? '';
		const lines = text.split(/\s+/).filter((s) => s.includes(','));

		for (const line of lines) {
			const parts = line.split(',');
			if (parts.length >= 2) {
				waypoints.push({
					lng: parseFloat(parts[0]),
					lat: parseFloat(parts[1]),
					ele: parts[2] ? parseFloat(parts[2]) || undefined : undefined,
				});
			}
		}
	});

	if (waypoints.length === 0) {
		throw new Error('KML file contains no coordinates');
	}

	return buildRoute(name, waypoints);
}

// --- KMZ ---

async function parseKmz(file: File): Promise<ImportedRoute> {
	const zip = await JSZip.loadAsync(file);

	// Find the .kml file inside the archive
	const kmlFile = Object.keys(zip.files).find((name) => name.endsWith('.kml'));
	if (!kmlFile) {
		throw new Error('KMZ archive does not contain a .kml file');
	}

	const kmlText = await zip.files[kmlFile].async('text');
	return parseKml(kmlText);
}

// --- GeoJSON ---

function parseGeoJson(text: string): ImportedRoute {
	const geo = JSON.parse(text);
	const name = geo.properties?.name ?? geo.name ?? 'Imported Route';
	const waypoints: TrackPoint[] = [];

	function extractCoords(coords: number[][]) {
		for (const c of coords) {
			if (Array.isArray(c[0])) {
				// Nested (e.g. MultiLineString)
				extractCoords(c as unknown as number[][]);
			} else {
				waypoints.push({
					lng: c[0],
					lat: c[1],
					ele: c[2] || undefined,
				});
			}
		}
	}

	if (geo.type === 'FeatureCollection') {
		for (const feature of geo.features ?? []) {
			if (feature.geometry?.coordinates) {
				extractCoords(feature.geometry.coordinates);
			}
		}
	} else if (geo.type === 'Feature') {
		if (geo.geometry?.coordinates) {
			extractCoords(geo.geometry.coordinates);
		}
	} else if (geo.coordinates) {
		extractCoords(geo.coordinates);
	}

	if (waypoints.length === 0) {
		throw new Error('GeoJSON file contains no coordinates');
	}

	return buildRoute(name, waypoints);
}

// --- Shared ---

function buildRoute(name: string, waypoints: TrackPoint[]): ImportedRoute {
	let distance = 0;
	let elevGain = 0;

	for (let i = 1; i < waypoints.length; i++) {
		distance += haversine(waypoints[i - 1], waypoints[i]);
		const diff = (waypoints[i].ele ?? 0) - (waypoints[i - 1].ele ?? 0);
		if (diff > 0) elevGain += diff;
	}

	return {
		name,
		waypoints,
		distance_m: Math.round(distance * 100) / 100,
		elevation_m: elevGain > 0 ? Math.round(elevGain) : null,
	};
}

function haversine(a: TrackPoint, b: TrackPoint): number {
	const R = 6371000;
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(b.lat - a.lat);
	const dLng = toRad(b.lng - a.lng);
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const h = sinLat * sinLat + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
	return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}
