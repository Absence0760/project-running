/**
 * Course-waypoint GPX export: the route line as a `<trk>` plus one `<wpt>`
 * per course marker (aid station, cutoff, crew access, hazard, …). Imported
 * by every Garmin/Coros/Suunto so the runner sees "Aid 2 in 1.3 km" on the
 * wrist mid-race.
 *
 * Pure + deterministic (no `new Date()`): the GPX `<metadata>` carries only a
 * `<name>`, so the output is byte-stable for tests. GPX 1.1 schema requires
 * `<wpt>` elements BEFORE `<trk>`, so waypoints are emitted first.
 *
 * Twin of `apps/mobile_android/lib/route_gpx.dart` — keep the element order,
 * `<sym>` mapping, `<desc>` construction, escaping, and test count in lockstep.
 */

import { parseCutoff } from './route_markers';

export interface RouteGpxMarker {
	label: string;
	lat: number;
	lng: number;
	/** RouteMarkerKind value. */
	kind: string;
	/** Carries cutoff_clock / cutoff_elapsed_s / services. */
	meta: Record<string, unknown>;
}

/** Garmin-recognised `<sym>` name per marker kind; absent → no `<sym>`. */
const SYM_BY_KIND: Record<string, string> = {
	aid_station: 'Water Source',
	cutoff: 'Danger Area',
	crew_access: 'Parking Area',
	hazard: 'Danger Area',
	note: 'Information',
	climb: 'Summit'
};

/**
 * Generate a GPX 1.1 document for a route line plus its course markers.
 * `coordinates` are `[lng, lat]` pairs (same order as `toGpx`).
 */
export function toRouteGpxWithMarkers(
	name: string,
	coordinates: [number, number][],
	elevations: number[],
	markers: RouteGpxMarker[]
): string {
	const waypoints = markers.map((m) => renderWaypoint(m)).join('\n');

	const trackpoints = coordinates
		.map(([lng, lat], i) => {
			const ele = elevations[i] ?? 0;
			return `      <trkpt lat="${lat}" lon="${lng}"><ele>${ele}</ele></trkpt>`;
		})
		.join('\n');

	return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Threkir"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata>
    <name>${escapeXml(name)}</name>
  </metadata>
${waypoints ? waypoints + '\n' : ''}  <trk>
    <name>${escapeXml(name)}</name>
    <trkseg>
${trackpoints}
    </trkseg>
  </trk>
</gpx>`;
}

function renderWaypoint(m: RouteGpxMarker): string {
	const parts: string[] = [
		`  <wpt lat="${m.lat}" lon="${m.lng}">`,
		`<name>${escapeXml(m.label)}</name>`,
		`<type>${escapeXml(m.kind)}</type>`
	];
	const sym = SYM_BY_KIND[m.kind];
	if (sym) parts.push(`<sym>${sym}</sym>`);
	const desc = buildDesc(m.meta);
	if (desc) parts.push(`<desc>${escapeXml(desc)}</desc>`);
	parts.push('</wpt>');
	return parts.join('');
}

/** Locale-agnostic canonical-English `<desc>` built purely from `meta`. */
function buildDesc(meta: Record<string, unknown>): string {
	const segments: string[] = [];

	const cutoff = parseCutoff(meta);
	if (cutoff) {
		if (cutoff.clock !== undefined) segments.push(`Cutoff ${cutoff.clock}`);
		if (cutoff.elapsedS !== undefined) {
			const h = Math.floor(cutoff.elapsedS / 3600);
			const m = Math.floor((cutoff.elapsedS % 3600) / 60);
			segments.push(`Cutoff ${h}h${String(m).padStart(2, '0')}m elapsed`);
		}
	}

	const services = meta.services;
	if (Array.isArray(services)) {
		const named = services.filter((s): s is string => typeof s === 'string');
		if (named.length > 0) segments.push(`Services: ${named.join(', ')}`);
	}

	return segments.join(' | ');
}

function escapeXml(str: string): string {
	return str
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}
