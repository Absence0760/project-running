/// Strava bulk-export zip importer.
///
/// Strava's "Request your archive" download is a zip with a root-level
/// `activities.csv` (the index) and an `activities/` folder of per-run
/// files — GPX (most runs), TCX (older exports), or FIT (binary, not
/// yet supported by our parsers). The csv carries scalar fields (name,
/// type, moving time, distance, avg HR, etc.) that aren't necessarily
/// present in the activity file; we combine the two so metadata
/// survives the round trip.
///
/// Dedupe: the importer tags each run's metadata with `strava_id` (from
/// the csv `Activity ID` column) and skips any ID already present on
/// the user's `source = 'strava'` runs.

import JSZip from 'jszip';
import { parseRouteFile, type ImportedRoute } from './import';
import { saveRun } from './data';
import { supabase } from './supabase';
import { auth } from './stores/auth.svelte';

export interface StravaZipProgress {
	total: number;
	imported: number;
	skipped: number;
	failed: number;
	currentName: string | null;
}

type ProgressHandler = (p: StravaZipProgress) => void;

/// Parse a Strava export zip and import every run-type activity it
/// contains. Reports progress via `onProgress` so the UI can render a
/// bar without blocking the main thread. Returns the final summary.
export async function importStravaZip(
	file: File,
	onProgress?: ProgressHandler,
): Promise<StravaZipProgress> {
	const uid = auth.user?.id;
	if (!uid) throw new Error('Not signed in');

	const zip = await JSZip.loadAsync(file);
	const csvFile = zip.file('activities.csv');
	if (!csvFile) {
		throw new Error('Not a Strava export zip (missing activities.csv).');
	}

	const csvText = await csvFile.async('text');
	const rows = parseCsv(csvText);
	if (rows.length === 0) {
		throw new Error('activities.csv contained no rows.');
	}

	// Column names shift across Strava export eras; look them up case-
	// insensitively and by alias. If we can't find the essentials, bail.
	const header = rows[0];
	const idx = indexHeader(header);
	if (idx.id < 0 || idx.filename < 0) {
		throw new Error('activities.csv is missing required columns (Activity ID / Filename).');
	}

	// Existing Strava-sourced runs → dedupe key.
	const { data: existing } = await supabase
		.from('runs')
		.select('metadata')
		.eq('user_id', uid)
		.eq('source', 'strava');
	const seen = new Set<string>();
	for (const r of existing ?? []) {
		const sid = (r.metadata as Record<string, unknown> | null)?.strava_id;
		if (sid) seen.add(String(sid));
	}

	const dataRows = rows.slice(1);
	const progress: StravaZipProgress = {
		total: dataRows.length,
		imported: 0,
		skipped: 0,
		failed: 0,
		currentName: null,
	};
	onProgress?.(progress);

	for (const row of dataRows) {
		const stravaId = row[idx.id];
		const name = row[idx.name >= 0 ? idx.name : idx.id] ?? 'Strava activity';
		const actType = (row[idx.type] ?? '').toLowerCase();
		const filename = row[idx.filename];
		progress.currentName = name;

		// Skip non-foot activities — the app is opinionated about what's
		// a "run" (which also covers walks / hikes).
		if (actType && !actType.includes('run') && !actType.includes('walk') && !actType.includes('hike')) {
			progress.skipped++;
			onProgress?.(progress);
			continue;
		}
		if (stravaId && seen.has(stravaId)) {
			progress.skipped++;
			onProgress?.(progress);
			continue;
		}

		try {
			await importOne(zip, row, idx, stravaId, filename);
			seen.add(stravaId);
			progress.imported++;
		} catch (_err) {
			progress.failed++;
		}
		onProgress?.(progress);
	}

	progress.currentName = null;
	onProgress?.(progress);
	return progress;
}

async function importOne(
	zip: JSZip,
	row: string[],
	idx: HeaderIndex,
	stravaId: string,
	filename: string,
): Promise<void> {
	const startedAt = row[idx.date];
	const distanceM = parseCsvNumber(row[idx.distance]) * 1000; // CSV is km
	const durationS = parseCsvNumber(row[idx.movingTime]);
	const elevationM = idx.elevation >= 0 ? parseCsvNumber(row[idx.elevation]) : 0;
	const avgBpm = idx.avgHr >= 0 ? parseCsvNumber(row[idx.avgHr]) : 0;
	const actType = (row[idx.type] ?? 'run').toLowerCase();
	const activityType = actType.includes('walk') ? 'walk' : actType.includes('hike') ? 'hike' : 'run';

	// Try to parse the per-activity file for the GPS track. Strava
	// occasionally writes `.gz` files — JSZip handles the outer archive
	// but a `.gpx.gz` inside needs a second decompress. We support the
	// plain extensions here and skip the compressed ones (FIT too)
	// rather than pull in a decompression helper for an edge case.
	let track: ImportedRoute['waypoints'] | null = null;
	if (filename) {
		const entry = zip.file(filename);
		if (entry && /\.(gpx|tcx|kml|geojson|json)$/i.test(filename)) {
			const blob = await entry.async('blob');
			const synthetic = new File([blob], filename.split('/').pop()!);
			try {
				const routes = await parseRouteFile(synthetic);
				if (routes.length > 0) track = routes[0].waypoints;
			} catch (_) {
				// Fallthrough — keep row without track.
			}
		}
	}

	const metadata: Record<string, unknown> = {
		strava_id: stravaId,
		activity_type: activityType,
		imported_from: 'strava',
		imported_at: new Date().toISOString(),
	};
	if (avgBpm > 0) metadata.avg_bpm = Math.round(avgBpm);
	if (idx.stravaType >= 0 && row[idx.stravaType]) metadata.strava_activity_type = row[idx.stravaType];

	await saveRun({
		started_at: new Date(startedAt).toISOString(),
		distance_m: Math.max(0, Math.round(distanceM)),
		duration_s: Math.max(0, Math.round(durationS)),
		elevation_m: elevationM > 0 ? Math.round(elevationM) : null,
		source: 'strava',
		metadata,
		track: track ?? undefined,
		title: row[idx.name] || null,
	});
}

// --- CSV parsing ---

interface HeaderIndex {
	id: number;
	name: number;
	type: number;
	stravaType: number;
	date: number;
	filename: number;
	distance: number;
	movingTime: number;
	elevation: number;
	avgHr: number;
}

function indexHeader(header: string[]): HeaderIndex {
	const find = (...names: string[]) => {
		for (const n of names) {
			const i = header.findIndex((h) => h.trim().toLowerCase() === n.toLowerCase());
			if (i >= 0) return i;
		}
		return -1;
	};
	return {
		id: find('Activity ID'),
		name: find('Activity Name'),
		type: find('Activity Type'),
		stravaType: find('Activity Type'),
		date: find('Activity Date'),
		filename: find('Filename'),
		distance: find('Distance', 'Distance (km)'),
		movingTime: find('Moving Time', 'Moving Time (seconds)'),
		elevation: find('Elevation Gain', 'Elevation Gain (m)'),
		avgHr: find('Average Heart Rate'),
	};
}

/// Minimal CSV parser — handles quoted fields with embedded commas and
/// double-quote escapes (`""`). That's the shape Strava emits; we
/// don't try to support every RFC 4180 edge case.
function parseCsv(text: string): string[][] {
	const out: string[][] = [];
	let row: string[] = [];
	let field = '';
	let inQuotes = false;
	for (let i = 0; i < text.length; i++) {
		const c = text[i];
		if (inQuotes) {
			if (c === '"') {
				if (text[i + 1] === '"') {
					field += '"';
					i++;
				} else {
					inQuotes = false;
				}
			} else {
				field += c;
			}
		} else {
			if (c === '"') {
				inQuotes = true;
			} else if (c === ',') {
				row.push(field);
				field = '';
			} else if (c === '\n') {
				row.push(field);
				out.push(row);
				row = [];
				field = '';
			} else if (c === '\r') {
				// swallow — handled on the \n
			} else {
				field += c;
			}
		}
	}
	if (field.length > 0 || row.length > 0) {
		row.push(field);
		out.push(row);
	}
	return out;
}

function parseCsvNumber(s: string | undefined): number {
	if (!s) return 0;
	const n = parseFloat(s.replace(/,/g, ''));
	return Number.isFinite(n) ? n : 0;
}
