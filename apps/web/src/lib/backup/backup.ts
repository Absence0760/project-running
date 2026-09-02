import { supabase } from '../core/supabase';
import { TABLES, BUCKETS } from '../core/schema';
import { auth } from '../stores/auth.svelte';
import {
	buildBackupZip,
	readAllRows,
	BACKUP_FORMAT,
	BACKUP_VERSION
} from './backup_writer';
import type { BackupArchive, BackupProgress } from './backup_writer';
import { parseBackupArchive } from './backup_reader';
import {
	restoreOrchestrate,
	type RestoreBackend,
	type RestoreProgress,
	type RestoreResult
} from './restore_orchestrator';

/**
 * Backup + restore for a user's runs, routes, and profile. See
 * `docs/ops/backup_restore.md` for the on-disk format.
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
 * [decisions.md § 66](../../../docs/architecture/decisions.md#66-backup-zip-writes-stream-to-disk-and-download-tracks-in-bounded-batches).
 */

export { BACKUP_FORMAT, BACKUP_VERSION };
export type { BackupArchive, BackupProgress };

export type { RestoreProgress, RestoreResult } from './restore_orchestrator';

/**
 * Build the account's local backup archive.
 *
 * Returns the writer's own verdict alongside the bytes, not just the
 * bytes: a track whose download failed is skipped so one dead blob
 * can't sink the file, which makes the returned `incomplete` and the
 * archive's manifest the only record that it is short. The caller has
 * to disclose that — an archive that reads as whole is what someone
 * wipes a device on.
 */
export async function createBackup(
	onProgress?: (p: BackupProgress) => void
): Promise<BackupArchive> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	// PAGED, and uncapped. An unranged select is clamped to `db-max-rows`
	// (1000) and answered 200 with no flag, so a deep history backed itself
	// up, was told it succeeded, and found out at restore.
	onProgress?.({ stage: 'runs', current: 0, total: 1 });
	const runsRead = await readAllRows<Record<string, unknown>>((from, to) =>
		supabase
			.from(TABLES.runs)
			.select('*')
			.eq('user_id', userId)
			.order('started_at', { ascending: false })
			// Secondary key so the pages compose into the whole table: LIMIT /
			// OFFSET over a non-unique sort key lets a row on a page boundary
			// be returned twice or not at all, and this read is the one whose
			// manifest then claims `complete`. Same rule `fetchClubMembers`
			// states for load-more, where the cost is a visibly duplicated
			// name rather than a run missing from an archive.
			.order('id', { ascending: false })
			.range(from, to)
	);
	// Nothing at all is a failed backup, not a short one — the runner gets
	// the error rather than a file with no runs in it. A read that died
	// PART-way still holds runs worth keeping, so it ships flagged.
	if (runsRead.error && runsRead.rows.length === 0) throw runsRead.error;
	const runRows = runsRead.rows;

	onProgress?.({ stage: 'routes', current: 0, total: 1 });
	const routesRead = await readAllRows<Record<string, unknown>>((from, to) =>
		// Ordered on the primary key alone: `routes` has no natural sort and a
		// paged read with no ORDER BY is undefined -- Postgres may answer two
		// OFFSETs from different row orders, so an account past one page could
		// archive a route twice and lose another, under a whole manifest.
		supabase
			.from('routes')
			.select('*')
			.eq('user_id', userId)
			.order('id', { ascending: true })
			.range(from, to)
	);
	const routes = routesRead.rows;

	onProgress?.({ stage: 'profile', current: 0, total: 1 });
	// Use the get_my_profile RPC because subscription_tier / parkrun_number
	// / subscription_at are column-level revoked from authenticated direct
	// reads (migration 20260707_001).
	//
	// Graded, not discarded. These two reads are the rest of the archive,
	// and an error here used to leave `profile: null` / an empty prefs bag
	// under a manifest still claiming `complete: true` — the same false
	// all-clear the paged row reads were fixed for. A missing settings ROW
	// is not a shortfall (a runner who never changed a preference has
	// none); only an error is.
	const { data: profile, error: profileErr } = await supabase.rpc('get_my_profile');
	const { data: userSettings, error: settingsErr } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();

	// Strip user_id from rows so the archive is re-homeable.
	const runsOut = runRows.map((r) => {
		const { user_id: _uid, ...rest } = r as Record<string, unknown>;
		return rest;
	});
	const routesOut = routes.map((r) => {
		const { user_id: _uid, ...rest } = r as Record<string, unknown>;
		return rest;
	});

	const runsWithTracks = runRows.filter(
		(r): r is Record<string, unknown> & { id: string; track_url: string } =>
			typeof r.id === 'string' &&
			typeof r.track_url === 'string' &&
			r.track_url.length > 0
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
		// A row read that came up short is the caller's finding, not the
		// writer's; the manifest merges both.
		incompleteSections: [
			...(runsRead.complete ? [] : ['runs']),
			...(routesRead.complete ? [] : ['routes']),
			...(profileErr ? ['profile'] : []),
			...(settingsErr ? ['settings_prefs'] : [])
		],
		onProgress,
	});
}

/**
 * Default Storage-backed track fetcher. Pulled out as a function so
 * tests can substitute a deterministic in-memory fake without booting
 * supabase-js.
 */
async function defaultTrackFetcher(trackUrl: string): Promise<Uint8Array> {
	const { data, error } = await supabase.storage.from(BUCKETS.runs).download(trackUrl);
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
			const { error } = await supabase.storage.from(BUCKETS.runs).upload(path, bytes, {
				contentType: 'application/gzip',
				upsert: true,
				cacheControl: '0'
			});
			if (error) throw error;
		},
		async upsertRun(row) {
			const { error } = await supabase.from(TABLES.runs).upsert(row, { onConflict: 'id' });
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
