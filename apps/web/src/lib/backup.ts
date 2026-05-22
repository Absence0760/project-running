import { supabase } from './supabase';
import { auth } from './stores/auth.svelte';
import { buildBackupZip, BACKUP_FORMAT, BACKUP_VERSION } from './backup_writer';
import type { BackupProgress } from './backup_writer';
import { parseBackupArchive } from './backup_reader';
import {
	restoreOrchestrate,
	type RestoreBackend,
	type RestoreProgress,
	type RestoreResult
} from './restore_orchestrator';

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

export type { RestoreProgress, RestoreResult } from './restore_orchestrator';

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

export async function restoreBackup(
	file: File | Blob,
	opts: { generateNewIds?: boolean; onProgress?: (p: RestoreProgress) => void } = {}
): Promise<RestoreResult> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const onProgress = opts.onProgress;

	onProgress?.({ stage: 'reading', current: 0, total: 1 });
	const parsed = await parseBackupArchive(file);

	return restoreOrchestrate(parsed, userId, supabaseRestoreBackend(), {
		generateNewIds: opts.generateNewIds,
		onProgress
	});
}

/**
 * Production [RestoreBackend] adapter — thin wrappers around the
 * existing supabase-js calls. Tests substitute a counter-tracking
 * fake; see `restore_orchestrator.test.ts`.
 */
function supabaseRestoreBackend(): RestoreBackend {
	return {
		async upsertProfile(row) {
			const { error } = await supabase.from('user_profiles').upsert(row);
			if (error) throw error;
		},
		async upsertSettings(prefs) {
			const userId = auth.user?.id;
			if (!userId) throw new Error('Not authenticated');
			const { error } = await supabase.from('user_settings').upsert({
				user_id: userId,
				prefs,
				updated_at: new Date().toISOString()
			});
			if (error) throw error;
		},
		async uploadTrack(path, bytes) {
			const { error } = await supabase.storage.from('runs').upload(path, bytes, {
				contentType: 'application/gzip',
				upsert: true,
				cacheControl: '0'
			});
			if (error) throw error;
		},
		async upsertRun(row) {
			const { error } = await supabase.from('runs').upsert(row, { onConflict: 'id' });
			if (error) throw error;
		},
		async upsertRoute(row) {
			const { error } = await supabase.from('routes').upsert(row, { onConflict: 'id' });
			if (error) throw error;
		},
		async fetchValidEventIds(ids) {
			const { data } = await supabase.from('events').select('id').in('id', ids);
			const valid = new Set<string>();
			for (const e of data ?? []) valid.add(e.id);
			return valid;
		}
	};
}
