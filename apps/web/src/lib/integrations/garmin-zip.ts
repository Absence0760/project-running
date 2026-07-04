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
import { saveRun } from '../core/data';
import { supabase } from '../core/supabase';
import { TABLES, METADATA_KEYS } from '../core/schema';
import { auth } from '../stores/auth.svelte';
import {
	parseFitBuffer,
	garminExternalId,
	computeEmbeddedBests,
	type ParsedFitRun,
	type FitHrZones,
} from './garmin-fit';
import { loadSettings, effective, updateUniversal } from '../settings/settings';
import {
	compositeKey,
	collectRunIdentities,
	isCrossProviderDuplicate,
	type RawRunRow,
	type RunIdentity,
} from './garmin_dedupe';

export interface GarminZipProgress {
	total: number;
	imported: number;
	skipped: number;
	failed: number;
	currentName: string | null;
	/// True when the import seeded the user's HR zones from a FIT file's
	/// `hr_zone` messages (only happens when the user had none set).
	hrZonesImported?: boolean;
}

/// Collects the first HR-zone set seen across an import so it can seed the
/// user's settings once (only when they have none).
interface HrZoneCollector {
	hrZones: FitHrZones | null;
}

/// One-time seed of the user's HR zones from a parsed FIT file. No-op when
/// the file carried no zones or the user already has zones configured — we
/// never clobber an existing set. Sets `progress.hrZonesImported` so the
/// caller can surface a toast.
async function seedHrZonesIfUnset(
	uid: string,
	collector: HrZoneCollector,
	progress: GarminZipProgress,
): Promise<void> {
	if (!collector.hrZones) return;
	try {
		const settings = await loadSettings(uid);
		if (effective<Record<string, number>>(settings, 'hr_zones')) return;
		await updateUniversal(uid, { hr_zones: collector.hrZones });
		progress.hrZonesImported = true;
	} catch (_e) {
		// Best-effort — a failed seed must not fail the whole import.
	}
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
	// is the canonical identity for FIT-sourced runs; the normalised
	// `compositeKey` (started_at + distance) catches the GPX/TCX
	// fallback path against DB rows, the FIT entries, and other entries
	// in the same bundle.
	const { data: existing } = await supabase
		.from(TABLES.runs)
		.select('metadata, started_at, distance_m')
		.eq('user_id', uid)
		.eq('source', 'garmin');
	const seenIds = new Set<string>();
	const seenComposite = new Set<string>();
	for (const r of existing ?? []) {
		const md = r.metadata as Record<string, unknown> | null;
		const gid = md?.garmin_id;
		if (gid) seenIds.add(String(gid));
		seenComposite.add(compositeKey(r.started_at, r.distance_m));
	}

	// Cross-provider near-duplicate guard. `seenIds` / `seenComposite` above
	// are scoped to `source='garmin'`, so the same activity that already
	// arrived under another source (a Garmin watch auto-uploaded to Strava,
	// an Apple HealthKit copy) is invisible to them and re-imports. Pull every
	// existing run's start time + distance ACROSS ALL SOURCES so an import
	// skips a run already present under any provider.
	//
	// PAGE the read: PostgREST caps an unbounded SELECT at 1000 rows, which
	// for the high-volume pros this guard exists to protect (1000+ runs) would
	// silently compare against an arbitrary 1000-row slice and re-create
	// duplicates anyway. `collectRunIdentities` loops `.range()` in 1000-row
	// chunks the same way `fetchRuns` in core/data.ts does.
	const existingIdentities = await collectRunIdentities((from, to) =>
		supabase
			.from(TABLES.runs)
			.select('started_at, distance_m')
			.eq('user_id', uid)
			.order('started_at', { ascending: false })
			.range(from, to)
			.then(({ data, error }): RawRunRow[] | null => (error ? null : (data as RawRunRow[]))),
	);
	const hrZoneCollector: HrZoneCollector = { hrZones: null };

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
				existingIdentities,
				hrZoneCollector,
			);
			if (handled === 'imported') progress.imported++;
			else if (handled === 'skipped') progress.skipped++;
		} catch (_e) {
			progress.failed++;
		}
		await seedHrZonesIfUnset(uid, hrZoneCollector, progress);
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
				handled = await importFitFile(
					buf,
					e.path,
					seenIds,
					seenComposite,
					existingIdentities,
					hrZoneCollector,
				);
			} else if (e.kind === 'route') {
				const blob = await zip.file(e.path)!.async('blob');
				const synthetic = new File([blob], e.path.split('/').pop()!);
				handled = await importRouteFile(synthetic, seenComposite, existingIdentities);
			} else if (e.kind === 'fit-zip') {
				// Garmin sometimes wraps a single FIT inside a per-activity
				// .zip; open it and pull out any .fit entries.
				const blob = await zip.file(e.path)!.async('blob');
				const inner = await JSZip.loadAsync(blob);
				let innerHandled: 'imported' | 'skipped' | 'failed' = 'failed';
				for (const name of Object.keys(inner.files)) {
					if (!name.toLowerCase().endsWith('.fit')) continue;
					const buf = await inner.file(name)!.async('uint8array');
					innerHandled = await importFitFile(
							buf,
							name,
							seenIds,
							seenComposite,
							existingIdentities,
							hrZoneCollector,
						);
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

	await seedHrZonesIfUnset(uid, hrZoneCollector, progress);
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
	existingIdentities: RunIdentity[],
	collector?: HrZoneCollector,
): Promise<'imported' | 'skipped' | 'failed'> {
	let parsed: ParsedFitRun | null;
	try {
		// TS 6 typed Uint8Array.buffer as ArrayBufferLike (union with
		// SharedArrayBuffer); parseFitBuffer wants a concrete ArrayBuffer.
		// .slice() always returns a fresh ArrayBuffer either way.
		parsed = await parseFitBuffer(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer);
	} catch (_e) {
		return 'failed';
	}
	if (!parsed) return 'skipped';

	// Capture HR zones even from a duplicate/skipped run — the zones are
	// the same regardless of whether this particular activity is new.
	if (collector && !collector.hrZones && parsed.hr_zones) {
		collector.hrZones = parsed.hr_zones;
	}

	// Skip non-foot/cycle activities — we don't model swim, ski, etc.
	if (!parsed.activity_type) return 'skipped';

	if (parsed.garmin_file_id && seenIds.has(parsed.garmin_file_id)) {
		return 'skipped';
	}
	const composite = compositeKey(parsed.startedAt, parsed.distance_m);
	if (seenComposite.has(composite)) return 'skipped';

	// Cross-provider near-duplicate: this same activity may already exist
	// under another source (e.g. auto-uploaded to Strava). The garmin_id /
	// composite checks above are garmin-scoped and never see it.
	const startMs = Date.parse(parsed.startedAt);
	if (
		Number.isFinite(startMs) &&
		isCrossProviderDuplicate(
			{ startedAtMs: startMs, distanceM: parsed.distance_m },
			existingIdentities,
		)
	) {
		return 'skipped';
	}

	const metadata: Record<string, unknown> = {
		[METADATA_KEYS.imported_from]: 'garmin',
		[METADATA_KEYS.imported_at]: new Date().toISOString(),
		[METADATA_KEYS.source_file]: displayName,
	};
	if (parsed.garmin_file_id) metadata[METADATA_KEYS.garmin_id] = parsed.garmin_file_id;
	if (parsed.avg_bpm != null) metadata[METADATA_KEYS.avg_bpm] = parsed.avg_bpm;
	if (parsed.max_bpm != null) metadata[METADATA_KEYS.max_bpm] = parsed.max_bpm;
	if (parsed.avg_cadence_spm != null) metadata[METADATA_KEYS.cadence_spm] = parsed.avg_cadence_spm;
	if (parsed.laps.length > 0) metadata[METADATA_KEYS.laps] = parsed.laps;
	if (parsed.indoor) metadata[METADATA_KEYS.indoor] = true;
	if (parsed.sub_sport) metadata[METADATA_KEYS.sub_sport] = parsed.sub_sport;
	if (parsed.running_dynamics) metadata[METADATA_KEYS.running_dynamics] = parsed.running_dynamics;
	// Embedded best efforts (the promoted fastest_{5k,10k,half_marathon,
	// marathon}_s columns, 20270325_001) so a fast sub-distance inside a long
	// imported run reaches personal_records. Empty {} → nothing written for
	// indoor/trackless or too-short runs; no fake bests.
	const embeddedBests = computeEmbeddedBests(parsed.track);

	await saveRun({
		embedded_bests: embeddedBests,
		started_at: parsed.startedAt,
		distance_m: parsed.distance_m,
		duration_s: parsed.duration_s,
		elevation_m: parsed.elevation_m,
		source: 'garmin',
		activity_type: parsed.activity_type,
		metadata,
		track: parsed.track.length > 0 ? parsed.track : undefined,
		// Indoor / treadmill runs have no track but carry per-point HR; saveRun
		// uploads it as a sidecar so the HR-zone chart renders (decisions §116).
		hrSeries: parsed.hr_series.length > 0 ? parsed.hr_series : undefined,
		title: null,
		// Cross-source dedupe key so a re-import (ZIP or future OAuth) of the
		// same FIT activity is skipped by the per-user runs.external_id unique
		// index. metadata.garmin_id alone never engaged that guard. (#18)
		external_id: garminExternalId(parsed.garmin_file_id),
	});

	if (parsed.garmin_file_id) seenIds.add(parsed.garmin_file_id);
	seenComposite.add(composite);
	if (Number.isFinite(startMs)) {
		existingIdentities.push({ startedAtMs: startMs, distanceM: parsed.distance_m });
	}
	return 'imported';
}

/// GPX / TCX fallback path — Garmin exports include user-uploaded
/// originals in those formats. Reuses the existing `parseRouteFile`,
/// then synthesises a Run with the basic distance/duration/track. No
/// FIT file_id, so dedupe is composite-key only.
async function importRouteFile(
	file: File,
	seenComposite: Set<string>,
	existingIdentities: RunIdentity[],
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

	const composite = compositeKey(startedAt, r.distance_m);
	if (seenComposite.has(composite)) return 'skipped';

	const distanceM = Math.max(0, Math.round(r.distance_m));
	const startMs = Date.parse(startedAt);
	if (
		Number.isFinite(startMs) &&
		isCrossProviderDuplicate({ startedAtMs: startMs, distanceM }, existingIdentities)
	) {
		return 'skipped';
	}

	const metadata: Record<string, unknown> = {
		imported_from: 'garmin',
		imported_at: new Date().toISOString(),
		source_file: file.name,
	};
	// Embedded best efforts off the GPX/TCX per-point timestamps + positions,
	// same as the FIT path — written to the promoted runs columns. {} when
	// the original carried no per-point times.
	await saveRun({
		embedded_bests: computeEmbeddedBests(waypoints),
		started_at: new Date(startedAt).toISOString(),
		distance_m: distanceM,
		duration_s: durationS,
		elevation_m: r.elevation_m ?? null,
		source: 'garmin',
		activity_type: 'run',
		metadata,
		track: waypoints.length > 0 ? waypoints : undefined,
		title: r.name || null,
	});

	seenComposite.add(composite);
	if (Number.isFinite(startMs)) {
		existingIdentities.push({ startedAtMs: startMs, distanceM });
	}
	return 'imported';
}
