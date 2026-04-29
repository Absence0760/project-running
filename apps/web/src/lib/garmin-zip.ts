/// Garmin bulk-export importer.
///
/// Two user paths land here:
///   - A single `.fit` file from "Export Original" on a Garmin Connect
///     activity page.
///   - A `.zip` from Garmin's "Account → Account Management → Request
///     Your Data" download — a multi-GB bundle whose activity files
///     live in `DI_CONNECT/DI-Connect-Fitness/` and (as originals
///     uploaded by the user) `DI_CONNECT/DI-Connect-Fitness-Uploaded-Files/`.
///     Some entries are themselves `.zip`-wrapped FIT files; we open
///     those one level deep.
///
/// GPX / TCX entries inside the bundle are routed to the existing
/// `parseRouteFile` so a Garmin export that contains user-uploaded
/// `.gpx` originals still hydrates a track.
///
/// Dedupe is keyed on `metadata.garmin_id = '<time_created>-<serial>'`
/// pulled from the FIT `file_id` message. Falls back to a
/// `started_at + distance` composite for non-FIT entries.

import JSZip from 'jszip';
import { parseRouteFile } from './import';
import { saveRun } from './data';
import { supabase } from './supabase';
import { auth } from './stores/auth.svelte';
import { parseFitBuffer, type ParsedFitRun } from './garmin-fit';

export interface GarminZipProgress {
	total: number;
	imported: number;
	skipped: number;
	failed: number;
	currentName: string | null;
}

type ProgressHandler = (p: GarminZipProgress) => void;

/// Top-level entry point. Accepts either a single `.fit` file or a
/// `.zip` bundle. Reports progress so the UI can render a bar without
/// blocking the main thread.
export async function importGarminBundle(
	file: File,
	onProgress?: ProgressHandler,
): Promise<GarminZipProgress> {
	const uid = auth.user?.id;
	if (!uid) throw new Error('Not signed in');

	const lower = file.name.toLowerCase();

	// Existing Garmin-sourced runs → dedupe key. `metadata.garmin_id`
	// is the canonical identity for FIT-sourced runs; `composite_key`
	// (`{started_at}|{distance_m}`) catches the GPX/TCX fallback path.
	const { data: existing } = await supabase
		.from('runs')
		.select('metadata, started_at, distance_m')
		.eq('user_id', uid)
		.eq('source', 'garmin');
	const seenIds = new Set<string>();
	const seenComposite = new Set<string>();
	for (const r of existing ?? []) {
		const md = r.metadata as Record<string, unknown> | null;
		const gid = md?.garmin_id;
		if (gid) seenIds.add(String(gid));
		seenComposite.add(`${r.started_at}|${r.distance_m}`);
	}

	if (lower.endsWith('.fit')) {
		const progress: GarminZipProgress = {
			total: 1,
			imported: 0,
			skipped: 0,
			failed: 0,
			currentName: file.name,
		};
		onProgress?.(progress);
		try {
			const handled = await importFitFile(
				new Uint8Array(await file.arrayBuffer()),
				file.name,
				seenIds,
				seenComposite,
			);
			if (handled === 'imported') progress.imported++;
			else if (handled === 'skipped') progress.skipped++;
		} catch (_e) {
			progress.failed++;
		}
		progress.currentName = null;
		onProgress?.(progress);
		return progress;
	}

	if (!lower.endsWith('.zip')) {
		throw new Error('Upload a .fit file or a .zip bundle.');
	}

	const zip = await JSZip.loadAsync(file);

	// Collect every importable entry first so we can report a real total.
	type Entry = { path: string; kind: 'fit' | 'route' | 'fit-zip' };
	const entries: Entry[] = [];
	zip.forEach((path, entry) => {
		if (entry.dir) return;
		const p = path.toLowerCase();
		if (p.endsWith('.fit')) entries.push({ path, kind: 'fit' });
		else if (/\.(gpx|tcx)$/.test(p)) entries.push({ path, kind: 'route' });
		else if (p.endsWith('.zip')) entries.push({ path, kind: 'fit-zip' });
	});

	const progress: GarminZipProgress = {
		total: entries.length,
		imported: 0,
		skipped: 0,
		failed: 0,
		currentName: null,
	};
	onProgress?.(progress);

	for (const e of entries) {
		progress.currentName = e.path.split('/').pop() ?? e.path;
		onProgress?.(progress);
		try {
			let handled: 'imported' | 'skipped' | 'failed' = 'failed';
			if (e.kind === 'fit') {
				const buf = await zip.file(e.path)!.async('uint8array');
				handled = await importFitFile(buf, e.path, seenIds, seenComposite);
			} else if (e.kind === 'route') {
				const blob = await zip.file(e.path)!.async('blob');
				const synthetic = new File([blob], e.path.split('/').pop()!);
				handled = await importRouteFile(synthetic, seenComposite);
			} else if (e.kind === 'fit-zip') {
				// Garmin sometimes wraps a single FIT inside a per-activity
				// .zip; open it and pull out any .fit entries.
				const blob = await zip.file(e.path)!.async('blob');
				const inner = await JSZip.loadAsync(blob);
				let innerHandled: 'imported' | 'skipped' | 'failed' = 'failed';
				for (const name of Object.keys(inner.files)) {
					if (!name.toLowerCase().endsWith('.fit')) continue;
					const buf = await inner.file(name)!.async('uint8array');
					innerHandled = await importFitFile(buf, name, seenIds, seenComposite);
					if (innerHandled === 'imported' || innerHandled === 'skipped') break;
				}
				handled = innerHandled;
			}
			if (handled === 'imported') progress.imported++;
			else if (handled === 'skipped') progress.skipped++;
			else progress.failed++;
		} catch (_err) {
			progress.failed++;
		}
		onProgress?.(progress);
	}

	progress.currentName = null;
	onProgress?.(progress);
	return progress;
}

/// Parse a FIT buffer, dedupe, and persist. Returns the disposition.
async function importFitFile(
	buf: Uint8Array,
	displayName: string,
	seenIds: Set<string>,
	seenComposite: Set<string>,
): Promise<'imported' | 'skipped' | 'failed'> {
	let parsed: ParsedFitRun | null;
	try {
		parsed = await parseFitBuffer(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
	} catch (_e) {
		return 'failed';
	}
	if (!parsed) return 'skipped';

	// Skip non-foot/cycle activities — we don't model swim, ski, etc.
	if (!parsed.activity_type) return 'skipped';

	if (parsed.garmin_file_id && seenIds.has(parsed.garmin_file_id)) {
		return 'skipped';
	}
	const composite = `${parsed.startedAt}|${parsed.distance_m}`;
	if (seenComposite.has(composite)) return 'skipped';

	const metadata: Record<string, unknown> = {
		activity_type: parsed.activity_type,
		imported_from: 'garmin',
		imported_at: new Date().toISOString(),
		source_file: displayName,
	};
	if (parsed.garmin_file_id) metadata.garmin_id = parsed.garmin_file_id;
	if (parsed.avg_bpm != null) metadata.avg_bpm = parsed.avg_bpm;
	if (parsed.max_bpm != null) metadata.max_bpm = parsed.max_bpm;

	await saveRun({
		started_at: parsed.startedAt,
		distance_m: parsed.distance_m,
		duration_s: parsed.duration_s,
		elevation_m: parsed.elevation_m,
		source: 'garmin',
		metadata,
		track: parsed.track.length > 0 ? parsed.track : undefined,
		title: null,
	});

	if (parsed.garmin_file_id) seenIds.add(parsed.garmin_file_id);
	seenComposite.add(composite);
	return 'imported';
}

/// GPX / TCX fallback path — Garmin exports include user-uploaded
/// originals in those formats. Reuses the existing `parseRouteFile`,
/// then synthesises a Run with the basic distance/duration/track. No
/// FIT file_id, so dedupe is composite-key only.
async function importRouteFile(
	file: File,
	seenComposite: Set<string>,
): Promise<'imported' | 'skipped' | 'failed'> {
	let routes;
	try {
		routes = await parseRouteFile(file);
	} catch (_e) {
		return 'failed';
	}
	if (!routes || routes.length === 0) return 'skipped';
	const r = routes[0];
	const waypoints = r.waypoints;
	if (waypoints.length < 2) return 'skipped';

	// Best-effort started_at + duration from the per-point timestamps.
	const firstTs = waypoints.find((w) => typeof w.ts === 'string')?.ts;
	const lastTs = [...waypoints].reverse().find((w) => typeof w.ts === 'string')?.ts;
	const startedAt = firstTs ?? new Date().toISOString();
	const durationS =
		firstTs && lastTs
			? Math.max(0, Math.round((Date.parse(lastTs) - Date.parse(firstTs)) / 1000))
			: 0;

	const composite = `${new Date(startedAt).toISOString()}|${Math.round(r.distance_m)}`;
	if (seenComposite.has(composite)) return 'skipped';

	await saveRun({
		started_at: new Date(startedAt).toISOString(),
		distance_m: Math.max(0, Math.round(r.distance_m)),
		duration_s: durationS,
		elevation_m: r.elevation_m ?? null,
		source: 'garmin',
		metadata: {
			activity_type: 'run',
			imported_from: 'garmin',
			imported_at: new Date().toISOString(),
			source_file: file.name,
		},
		track: waypoints.length > 0 ? waypoints : undefined,
		title: r.name || null,
	});

	seenComposite.add(composite);
	return 'imported';
}
