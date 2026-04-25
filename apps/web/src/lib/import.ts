/**
 * Route file import — parses GPX, KML, KMZ, GeoJSON, and TCX into a
 * common format. Supports files exported from Google Maps, Google
 * Earth, Strava, Garmin, etc.
 *
 * A single file can describe multiple routes (e.g. a Google Earth KML
 * with several `<Placemark>` line segments, or a GPX file with several
 * `<trk>` elements). `parseRouteFile` always returns an array so the
 * caller can surface each one as its own saveable route. The older API
 * flattened every coordinate into one combined polyline, which silently
 * merged distinct routes and showed a phantom "bridge" between them.
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
 * Parse a route file. Detects format from filename extension. Always
 * returns an array; files with a single track yield a one-element
 * array, files with multiple tracks yield one entry per track.
 */
export async function parseRouteFile(file: File): Promise<ImportedRoute[]> {
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

	if (ext === 'tcx') {
		const text = await file.text();
		return parseTcx(text);
	}

	throw new Error(`Unsupported file format: .${ext}. Use GPX, KML, KMZ, GeoJSON, or TCX.`);
}

// --- TCX ---

/**
 * Parse a Garmin Training Center XML (TCX) file. TCX wraps track
 * points in `<Trackpoint>` elements with `<Position>` children; also
 * carries per-point `<AltitudeMeters>` and `<Time>`, which we keep for
 * downstream elevation / timing consumers.
 *
 * Each `<Activity>` (or `<Course>`) becomes its own route.
 */
function parseTcx(xml: string): ImportedRoute[] {
	const doc = new DOMParser().parseFromString(xml, 'text/xml');
	const activities = Array.from(doc.querySelectorAll('Activity, Course'));
	const routes: ImportedRoute[] = [];

	// If no explicit Activity/Course wrapper, fall back to one route for
	// the whole file — some exporters emit a bare `<Trackpoint>` list.
	const scopes = activities.length > 0 ? activities : [doc as unknown as Element];

	for (const scope of scopes) {
		const name =
			scope.querySelector('Notes')?.textContent?.trim() ||
			scope.querySelector('Id')?.textContent?.trim() ||
			scope.querySelector('Name')?.textContent?.trim() ||
			'Imported Route';

		const tps = Array.from(scope.querySelectorAll('Trackpoint'));
		const waypoints: TrackPoint[] = [];
		for (const tp of tps) {
			const pos = tp.querySelector('Position');
			if (!pos) continue;
			const latStr = pos.querySelector('LatitudeDegrees')?.textContent;
			const lngStr = pos.querySelector('LongitudeDegrees')?.textContent;
			if (!latStr || !lngStr) continue;
			const lat = parseFloat(latStr);
			const lng = parseFloat(lngStr);
			if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
			const eleStr = tp.querySelector('AltitudeMeters')?.textContent;
			const ele = eleStr ? parseFloat(eleStr) : undefined;
			const tsStr = tp.querySelector('Time')?.textContent;
			// TCX `<HeartRateBpm><Value>180</Value></HeartRateBpm>`.
			const hrStr = tp.querySelector('HeartRateBpm > Value')?.textContent;
			const bpm = hrStr ? parseInt(hrStr, 10) : NaN;
			waypoints.push({
				lat,
				lng,
				ele: Number.isFinite(ele as number) ? (ele as number) : undefined,
				ts: tsStr || undefined,
				bpm: Number.isFinite(bpm) && bpm >= 30 && bpm <= 230 ? bpm : undefined,
			});
		}

		if (waypoints.length > 0) routes.push(buildRoute(name, waypoints));
	}

	if (routes.length === 0) {
		throw new Error('TCX file contains no track points');
	}

	return routes;
}

// --- GPX ---

function parseGpx(xml: string): ImportedRoute[] {
	const doc = new DOMParser().parseFromString(xml, 'text/xml');
	const defaultName = doc.querySelector('metadata > name')?.textContent?.trim() ?? 'Imported Route';

	const routes: ImportedRoute[] = [];

	// One route per <trk>. A <trk> may contain several <trkseg>s —
	// those are segments of the same track (e.g. split around a pause)
	// so we concatenate them into the single route.
	const tracks = Array.from(doc.querySelectorAll('trk'));
	for (const trk of tracks) {
		const name = trk.querySelector('name')?.textContent?.trim() ?? defaultName;
		const waypoints = toWaypoints(Array.from(trk.querySelectorAll('trkpt')));
		if (waypoints.length > 0) routes.push(buildRoute(name, waypoints));
	}

	// Separately, one route per <rte> (a planned route, distinct from a
	// recorded track). GPX files typically use one or the other, not both.
	if (routes.length === 0) {
		const rtes = Array.from(doc.querySelectorAll('rte'));
		for (const rte of rtes) {
			const name = rte.querySelector('name')?.textContent?.trim() ?? defaultName;
			const waypoints = toWaypoints(Array.from(rte.querySelectorAll('rtept')));
			if (waypoints.length > 0) routes.push(buildRoute(name, waypoints));
		}
	}

	// Final fallback: loose <wpt> markers. Rarely useful as a route but
	// keeps older exports working.
	if (routes.length === 0) {
		const waypoints = toWaypoints(Array.from(doc.querySelectorAll('wpt')));
		if (waypoints.length > 0) routes.push(buildRoute(defaultName, waypoints));
	}

	if (routes.length === 0) {
		throw new Error('GPX file contains no track, route, or waypoints');
	}

	return routes;
}

function toWaypoints(points: Element[]): TrackPoint[] {
	return points.map((pt) => {
		const ts = pt.querySelector('time')?.textContent?.trim() || undefined;
		// Garmin's `gpxtpx:TrackPointExtension` puts `<hr>` under
		// `<extensions>`; namespace prefixes vary by exporter so match
		// any element with localName === 'hr' (or 'heartrate').
		let bpm: number | undefined;
		const ext = pt.getElementsByTagName('extensions')[0];
		if (ext) {
			const hrEls = ext.getElementsByTagNameNS('*', 'hr');
			const node = hrEls[0] ?? ext.getElementsByTagNameNS('*', 'heartrate')[0];
			if (node?.textContent) {
				const v = parseInt(node.textContent, 10);
				if (Number.isFinite(v) && v >= 30 && v <= 230) bpm = v;
			}
		}
		return {
			lat: parseFloat(pt.getAttribute('lat') ?? '0'),
			lng: parseFloat(pt.getAttribute('lon') ?? '0'),
			ele: parseFloat(pt.querySelector('ele')?.textContent ?? '0') || undefined,
			ts,
			bpm,
		};
	});
}

// --- KML ---

function parseKml(xml: string): ImportedRoute[] {
	const doc = new DOMParser().parseFromString(xml, 'text/xml');
	const defaultName = doc.querySelector('Document > name')?.textContent?.trim() ?? 'Imported Route';

	const routes: ImportedRoute[] = [];

	// One route per Placemark. Google Earth emits each drawn line as
	// its own Placemark; a document with 2 routes will have 2 Placemarks.
	// Nested LineStrings inside a single Placemark (MultiGeometry) are
	// treated as segments of the same route — flatten into one polyline.
	const placemarks = Array.from(doc.querySelectorAll('Placemark'));
	for (const pm of placemarks) {
		const name = pm.querySelector('name')?.textContent?.trim() ?? defaultName;
		const coordElements = pm.querySelectorAll('LineString coordinates, LinearRing coordinates');
		const waypoints: TrackPoint[] = [];
		coordElements.forEach((el) => {
			waypoints.push(...parseKmlCoordinates(el.textContent ?? ''));
		});
		// Skip Placemarks that are Points / Polygons / empty — only real
		// line tracks become routes. A single-point Placemark isn't a route.
		if (waypoints.length >= 2) routes.push(buildRoute(name, waypoints));
	}

	// Fallback: some minimal KML exports put raw <coordinates> under the
	// document without Placemarks. Treat the whole file as one route.
	if (routes.length === 0) {
		const coordElements = doc.querySelectorAll('coordinates');
		const waypoints: TrackPoint[] = [];
		coordElements.forEach((el) => {
			waypoints.push(...parseKmlCoordinates(el.textContent ?? ''));
		});
		if (waypoints.length >= 2) routes.push(buildRoute(defaultName, waypoints));
	}

	if (routes.length === 0) {
		throw new Error('KML file contains no line-based routes');
	}

	return routes;
}

function parseKmlCoordinates(text: string): TrackPoint[] {
	const out: TrackPoint[] = [];
	// Coordinate tuples are whitespace-separated; within a tuple the
	// order is lng,lat,[ele] and comma-separated. Split permissively
	// (newlines, spaces, tabs) to handle Google Earth's indented output.
	const tokens = text.trim().split(/\s+/).filter((s) => s.includes(','));
	for (const token of tokens) {
		const parts = token.split(',');
		if (parts.length < 2) continue;
		const lng = parseFloat(parts[0]);
		const lat = parseFloat(parts[1]);
		if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
		const ele = parts[2] ? parseFloat(parts[2]) || undefined : undefined;
		out.push({ lat, lng, ele });
	}
	return out;
}

// --- KMZ ---

async function parseKmz(file: File): Promise<ImportedRoute[]> {
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

function parseGeoJson(text: string): ImportedRoute[] {
	const geo = JSON.parse(text);
	const routes: ImportedRoute[] = [];
	const defaultName = geo.properties?.name ?? geo.name ?? 'Imported Route';

	function lineStringToWaypoints(coords: number[][]): TrackPoint[] {
		const out: TrackPoint[] = [];
		for (const c of coords) {
			if (!Array.isArray(c) || c.length < 2) continue;
			out.push({ lng: c[0], lat: c[1], ele: c[2] || undefined });
		}
		return out;
	}

	function addGeometry(geom: any, name: string) {
		if (!geom) return;
		if (geom.type === 'LineString' && Array.isArray(geom.coordinates)) {
			const wps = lineStringToWaypoints(geom.coordinates);
			if (wps.length >= 2) routes.push(buildRoute(name, wps));
		} else if (geom.type === 'MultiLineString' && Array.isArray(geom.coordinates)) {
			// Each sub-line becomes its own route so a MultiLineString
			// export (common in Google Earth's GeoJSON output) doesn't
			// get stitched end-to-end.
			for (let i = 0; i < geom.coordinates.length; i++) {
				const wps = lineStringToWaypoints(geom.coordinates[i]);
				if (wps.length >= 2) {
					const segName = geom.coordinates.length > 1 ? `${name} (${i + 1})` : name;
					routes.push(buildRoute(segName, wps));
				}
			}
		} else if (geom.type === 'GeometryCollection' && Array.isArray(geom.geometries)) {
			for (const g of geom.geometries) addGeometry(g, name);
		}
	}

	if (geo.type === 'FeatureCollection' && Array.isArray(geo.features)) {
		for (const feature of geo.features) {
			const name = feature.properties?.name ?? defaultName;
			addGeometry(feature.geometry, name);
		}
	} else if (geo.type === 'Feature') {
		const name = geo.properties?.name ?? defaultName;
		addGeometry(geo.geometry, name);
	} else if (geo.type) {
		// Bare geometry (e.g. `{ type: 'LineString', coordinates: [...] }`)
		addGeometry(geo, defaultName);
	}

	if (routes.length === 0) {
		throw new Error('GeoJSON file contains no line-based routes');
	}

	return routes;
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
