import JSZip from 'jszip';
import { supabase } from './supabase';
import { auth } from './stores/auth.svelte';
import { buildBackupZip, BACKUP_FORMAT, BACKUP_VERSION } from './backup_writer';
import type { BackupProgress } from './backup_writer';

/**
 * Backup + restore for a user's runs, routes, and profile. See
 * `docs/backup_restore.md` for the on-disk format.
 *
 * The archive keeps GPS tracks pre-gzipped so restore can upload them
 * straight into the `runs` Storage bucket without a re-encode step.
 *
 * **Streaming construction (May 2026):** the write side delegates to
 * `buildBackupZip` in `./backup_writer.ts`, which uses
 * `@zip.js/zip.js`'s `ZipWriter` + `BlobWriter`. Each entry's bytes
 * flush to the underlying Blob and the JS-side copy drops. Restore
 * still uses JSZip — the read path needs random access by name
 * (`zip.file('runs.json')`), which JSZip supports out of the box;
 * the write path was the heap hot-spot. Mirrors the mobile fix in
 * [decisions.md § 66](../../../docs/decisions.md#66-backup-zip-writes-stream-to-disk-and-download-tracks-in-bounded-batches).
 */

export { BACKUP_FORMAT, BACKUP_VERSION };
export type { BackupProgress };

export interface RestoreProgress {
	stage: 'reading' | 'profile' | 'tracks' | 'runs' | 'routes' | 'done';
	current: number;
	total: number;
}

export async function createBackup(
	onProgress?: (p: BackupProgress) => void
): Promise<Blob> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	onProgress?.({ stage: 'runs', current: 0, total: 1 });
	const { data: runs, error: runsErr } = await supabase
		.from('runs')
		.select('*')
		.eq('user_id', userId)
		.order('started_at', { ascending: false });
	if (runsErr) throw runsErr;
	const runRows = runs ?? [];

	onProgress?.({ stage: 'routes', current: 0, total: 1 });
	const { data: routes } = await supabase
		.from('routes')
		.select('*')
		.eq('user_id', userId);

	onProgress?.({ stage: 'profile', current: 0, total: 1 });
	// Use the get_my_profile RPC because subscription_tier / parkrun_number
	// / subscription_at are column-level revoked from authenticated direct
	// reads (migration 20260707_001).
	const { data: profile } = await supabase.rpc('get_my_profile');
	const { data: userSettings } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();

	// Strip user_id from rows so the archive is re-homeable.
	const runsOut = runRows.map((r) => {
		const { user_id: _uid, ...rest } = r as Record<string, unknown>;
		return rest;
	});
	const routesOut = (routes ?? []).map((r) => {
		const { user_id: _uid, ...rest } = r as Record<string, unknown>;
		return rest;
	});

	const runsWithTracks = runRows.filter(
		(r): r is typeof r & { track_url: string } =>
			typeof r.track_url === 'string' && r.track_url.length > 0
	);

	return buildBackupZip({
		runsOut,
		routesOut,
		profile: profile ?? null,
		settingsPrefs: userSettings?.prefs ?? {},
		userId,
		exportedFrom: 'web',
		runsWithTracks,
		fetchTrackBytes: defaultTrackFetcher,
		onProgress,
	});
}

/**
 * Default Storage-backed track fetcher. Pulled out as a function so
 * tests can substitute a deterministic in-memory fake without booting
 * supabase-js.
 */
async function defaultTrackFetcher(trackUrl: string): Promise<Uint8Array> {
	const { data, error } = await supabase.storage.from('runs').download(trackUrl);
	if (error || !data) {
		throw error ?? new Error('track download returned no body');
	}
	return new Uint8Array(await data.arrayBuffer());
}

// `buildBackupZip` lives in `./backup_writer.ts` so the streaming +
// parallel-download contract is unit-testable without supabase-js.
// Re-exported here for callers that still import from `./backup`.
export { buildBackupZip } from './backup_writer';
export type { BuildBackupZipOptions } from './backup_writer';

export interface RestoreResult {
	runsImported: number;
	routesImported: number;
	tracksUploaded: number;
	profileRestored: boolean;
	warnings: string[];
}

export async function restoreBackup(
	file: File | Blob,
	opts: { generateNewIds?: boolean; onProgress?: (p: RestoreProgress) => void } = {}
): Promise<RestoreResult> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const onProgress = opts.onProgress;

	onProgress?.({ stage: 'reading', current: 0, total: 1 });
	const zip = await JSZip.loadAsync(file);

	const manifestFile = zip.file('manifest.json');
	if (!manifestFile) throw new Error('Not a valid backup — missing manifest.json');
	const manifest = JSON.parse(await manifestFile.async('string'));
	if (manifest.format !== BACKUP_FORMAT) {
		throw new Error(`Unexpected format: ${manifest.format}`);
	}
	if (manifest.version > BACKUP_VERSION) {
		throw new Error(
			`Backup is from a newer version (${manifest.version}). Update the app before restoring.`
		);
	}

	const result: RestoreResult = {
		runsImported: 0,
		routesImported: 0,
		tracksUploaded: 0,
		profileRestored: false,
		warnings: [],
	};

	// Profile + settings first — later rows may reference preferences.
	const profileFile = zip.file('profile.json');
	if (profileFile) {
		onProgress?.({ stage: 'profile', current: 0, total: 1 });
		try {
			const parsed = JSON.parse(await profileFile.async('string'));
			if (parsed.profile) {
				// Strip server-managed fields before the upsert. These
				// are derived from the user's actual subscription /
				// linked-account state on the server and must not
				// round-trip through a client-controlled archive — the
				// 20260718_001 INSERT WITH CHECK + 20260624_001 UPDATE
				// trigger reject these for non-service-role callers
				// anyway, but stripping here means the rest of the
				// profile (display_name, avatar_url, preferred_unit,
				// etc.) restores cleanly instead of failing the upsert.
				const {
					subscription_tier: _ignoreTier,
					subscription_at: _ignoreSubAt,
					parkrun_number: _ignoreParkrun,
					...portableProfile
				} = parsed.profile as Record<string, unknown>;
				void _ignoreTier; void _ignoreSubAt; void _ignoreParkrun;
				await supabase.from('user_profiles').upsert({
					...portableProfile,
					id: userId,
				});
				result.profileRestored = true;
			}
			if (parsed.settings_prefs && Object.keys(parsed.settings_prefs).length > 0) {
				await supabase.from('user_settings').upsert({
					user_id: userId,
					prefs: parsed.settings_prefs,
					updated_at: new Date().toISOString(),
				});
			}
		} catch (e) {
			result.warnings.push(`profile: ${(e as Error).message}`);
		}
	}

	// Runs + tracks. We upload the track first, then insert the row with
	// a track_url pointing at the freshly-uploaded file. If the track is
	// missing in the archive we still insert the row without it.
	const runsFile = zip.file('runs.json');
	if (runsFile) {
		const runs = JSON.parse(await runsFile.async('string')) as Record<string, unknown>[];
		const idMap = new Map<string, string>();

		// Resolve valid event ids up front — we null any `event_id` that
		// doesn't resolve, so a cross-account import doesn't FK-fail.
		const incomingEventIds = [
			...new Set(
				runs
					.map((r) => r.event_id)
					.filter((v): v is string => typeof v === 'string' && v.length > 0)
			),
		];
		const validEventIds = new Set<string>();
		if (incomingEventIds.length > 0) {
			const { data } = await supabase
				.from('events')
				.select('id')
				.in('id', incomingEventIds);
			for (const e of data ?? []) validEventIds.add(e.id);
		}

		let i = 0;
		for (const r of runs) {
			onProgress?.({ stage: 'runs', current: i, total: runs.length });
			const origId = r.id as string;
			const newId = opts.generateNewIds ? crypto.randomUUID() : origId;
			idMap.set(origId, newId);

			// Track upload.
			let trackUrl: string | null = null;
			const trackEntry = zip.file(`tracks/${origId}.json.gz`);
			if (trackEntry) {
				try {
					const bytes = await trackEntry.async('uint8array');
					const path = `${userId}/${newId}.json.gz`;
					const { error } = await supabase.storage
						.from('runs')
						.upload(path, bytes, {
							contentType: 'application/gzip',
							upsert: true,
							cacheControl: '0',
						});
					if (error) throw error;
					trackUrl = path;
					result.tracksUploaded++;
				} catch (e) {
					result.warnings.push(`track ${origId}: ${(e as Error).message}`);
				}
			}

			const eventId =
				typeof r.event_id === 'string' && validEventIds.has(r.event_id)
					? r.event_id
					: null;

			// Older backups (pre-Apr 2026) may lack metadata.activity_type.
			// The DB CHECK trigger requires it on insert, so coalesce to
			// 'run' on restore. The user can still edit it afterwards.
			const restoredMeta = (r.metadata && typeof r.metadata === 'object'
				? { ...(r.metadata as Record<string, unknown>) }
				: {}) as Record<string, unknown>;
			if (typeof restoredMeta.activity_type !== 'string') {
				restoredMeta.activity_type = 'run';
			}

			const row = {
				...r,
				id: newId,
				user_id: userId,
				event_id: eventId,
				track_url: trackUrl,
				metadata: restoredMeta,
			};

			try {
				const { error } = await supabase
					.from('runs')
					.upsert(row, { onConflict: 'id' });
				if (error) throw error;
				result.runsImported++;
			} catch (e) {
				result.warnings.push(`run ${origId}: ${(e as Error).message}`);
			}
			i++;
		}
	}

	// Routes — simpler, no Storage dependency.
	const routesFile = zip.file('routes.json');
	if (routesFile) {
		const routes = JSON.parse(await routesFile.async('string')) as Record<string, unknown>[];
		let i = 0;
		for (const r of routes) {
			onProgress?.({ stage: 'routes', current: i, total: routes.length });
			const newId = opts.generateNewIds ? crypto.randomUUID() : (r.id as string);
			try {
				const { error } = await supabase
					.from('routes')
					.upsert({ ...r, id: newId, user_id: userId }, { onConflict: 'id' });
				if (error) throw error;
				result.routesImported++;
			} catch (e) {
				result.warnings.push(`route ${r.id}: ${(e as Error).message}`);
			}
			i++;
		}
	}

	onProgress?.({ stage: 'done', current: 1, total: 1 });
	return result;
}

function stripId(row: Record<string, unknown>): Record<string, unknown> {
	const { id: _id, ...rest } = row;
	return rest;
}
