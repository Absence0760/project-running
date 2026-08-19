/**
 * Streaming + parallel ZIP writer for the `run-app-backup` v1 format.
 *
 * Extracted from `backup.ts` so the writer is unit-testable without
 * importing supabase-js (which transitively pulls in SvelteKit's
 * `$env` virtual module, unavailable to `node --test` / `tsx --test`).
 *
 * Mirrors the mobile fix in
 * [decisions.md § 66](../../../docs/architecture/decisions.md#66-backup-zip-writes-stream-to-disk-and-download-tracks-in-bounded-batches):
 * each `add()` flushes the entry's compressed bytes to the underlying
 * `BlobWriter` and drops the JS-side copy, so peak heap is
 * `O(concurrency × avg-track-size)` rather than `O(total-archive-size)`.
 */

import {
	BlobWriter,
	TextReader,
	Uint8ArrayReader,
	ZipWriter
} from '@zip.js/zip.js';

export const BACKUP_FORMAT = 'run-app-backup';
export const BACKUP_VERSION = 1;

export interface BackupProgress {
	stage: 'runs' | 'tracks' | 'routes' | 'profile' | 'writing' | 'done';
	current: number;
	total: number;
}

/**
 * Bounded concurrency for parallel track downloads. Six matches the
 * mobile fix's `_kTrackDownloadConcurrency` — enough to amortize
 * per-request latency, low enough that peak in-flight memory is
 * small and the browser connection pool isn't saturated.
 */
export const TRACK_DOWNLOAD_CONCURRENCY = 6;

/**
 * What the writer put in an archive it just finished.
 *
 * The row reads that feed the writer are uncapped, so the only way a
 * web archive can come up short of the account is a blob whose download
 * failed. `incomplete` names the sections that did, in the same
 * vocabulary the Go writer publishes (`BuildBackupZip` in
 * `apps/job_worker/internal/dataexport/server.go`) and the mobile writer
 * mirrors ([decisions.md § 668](../../../../docs/architecture/decisions.md)),
 * so one reader understands an archive from any writer.
 */
export interface BackupArchive {
	blob: Blob;
	/** Sorted section identifiers that came up short. Empty when whole. */
	incomplete: string[];
	blobsWanted: number;
	blobsWritten: number;
}

/// PostgREST clamps an unbounded SELECT at `db-max-rows` (1000) and answers
/// 200 with no flag, so a 3,000-run account that took a backup was told it
/// succeeded and got 1,000 runs — discovered at restore (the mobile half of
/// this is decisions.md § 668). Every row read behind a backup pages through
/// `readAllRows` instead, and there is deliberately no ceiling: the archive
/// is what the deepest histories rely on, and a cap would only reinstate the
/// silent truncation one order of magnitude higher.
export const BACKUP_PAGE_SIZE = 1000;
/// Runaway guard, not a product limit — a `fetchPage` that never returns a
/// short page (a server that ignores `range`) must terminate. Hitting it is
/// reported as a shortfall, never as a whole read.
export const BACKUP_PAGE_SAFETY_MAX = 200_000;

export interface PagedRead<T> {
	rows: T[];
	/// False when a page errored or the safety ceiling was hit — i.e. when
	/// `rows` is known to be short of what the table holds.
	complete: boolean;
	/// The first page error, for a caller that treats "nothing at all" as
	/// fatal rather than as a shortfall.
	error: unknown;
}

/// Read every row of a table by paging `fetchPage` in `pageSize` chunks.
///
/// Never throws: a read that dies half-way still has rows worth archiving,
/// and the caller has to be able to tell the difference between that and a
/// whole read — which is the entire point of the manifest's `complete` pair.
export async function readAllRows<T>(
	fetchPage: (
		from: number,
		to: number
	) => PromiseLike<{ data: T[] | null; error: unknown }>,
	pageSize: number = BACKUP_PAGE_SIZE,
	safetyMax: number = BACKUP_PAGE_SAFETY_MAX
): Promise<PagedRead<T>> {
	const rows: T[] = [];
	for (let from = 0; from < safetyMax; from += pageSize) {
		const { data, error } = await fetchPage(from, from + pageSize - 1);
		if (error) return { rows, complete: false, error };
		const page = data ?? [];
		rows.push(...page);
		if (page.length < pageSize) return { rows, complete: true, error: null };
	}
	return { rows, complete: false, error: null };
}

export interface BuildBackupZipOptions {
	runsOut: Record<string, unknown>[];
	routesOut: Record<string, unknown>[];
	profile: Record<string, unknown> | null;
	settingsPrefs: Record<string, unknown>;
	userId: string;
	exportedFrom: string;
	runsWithTracks: { id: string; track_url: string }[];
	fetchTrackBytes: (trackUrl: string) => Promise<Uint8Array>;
	/// Sections the CALLER already knows came up short — a row read that
	/// died half-way. Merged with the writer's own findings, mirroring the
	/// Go writer's `ExportCompleteness.Merge`.
	incompleteSections?: string[];
	concurrency?: number;
	onProgress?: (p: BackupProgress) => void;
}

export async function buildBackupZip(
	opts: BuildBackupZipOptions
): Promise<BackupArchive> {
	const concurrency = opts.concurrency ?? TRACK_DOWNLOAD_CONCURRENCY;
	if (concurrency < 1) {
		throw new Error('concurrency must be >= 1');
	}
	const onProgress = opts.onProgress;
	// `BlobWriter` accumulates the final ZIP to a Blob the browser
	// keeps disk-backed once it crosses the engine's blob-spill
	// threshold (~250 KB on Chrome). The JS heap doesn't grow with
	// total archive size.
	const blobWriter = new BlobWriter('application/zip');
	const zipWriter = new ZipWriter(blobWriter, { level: 6 });

	// Metadata first — small + cheap.
	await zipWriter.add('runs.json', new TextReader(JSON.stringify(opts.runsOut, null, 2)));
	await zipWriter.add('routes.json', new TextReader(JSON.stringify(opts.routesOut, null, 2)));
	await zipWriter.add(
		'profile.json',
		new TextReader(
			JSON.stringify(
				{
					profile: opts.profile ? stripId(opts.profile) : null,
					settings_prefs: opts.settingsPrefs
				},
				null,
				2
			)
		)
	);

	// Tracks — parallel batches of `concurrency`. Each track's bytes
	// flow `fetcher → ZipWriter.add → BlobWriter` and the JS-side
	// `Uint8Array` is unreferenced by the time the next batch fires.
	let tracksAdded = 0;
	onProgress?.({ stage: 'tracks', current: 0, total: opts.runsWithTracks.length });
	for (let i = 0; i < opts.runsWithTracks.length; i += concurrency) {
		const batch = opts.runsWithTracks.slice(i, i + concurrency);
		const pulls = await Promise.allSettled(
			batch.map(async (r) => ({ id: r.id, bytes: await opts.fetchTrackBytes(r.track_url) }))
		);
		for (const result of pulls) {
			if (result.status !== 'fulfilled') {
				// One dead download must not sink the archive — the run
				// row still ships in `runs.json` and restore lands it
				// trackless. But that is also the only way this file can
				// now be short of the account, so the shortfall leaves
				// the function in the returned summary and in the
				// manifest rather than stopping at a console line.
				console.warn('track download failed', result.reason);
				continue;
			}
			await zipWriter.add(
				`tracks/${result.value.id}.json.gz`,
				new Uint8ArrayReader(result.value.bytes),
				// Tracks are already gzipped — STORE rather than
				// DEFLATE means no wasted CPU on a re-compress that
				// can't shrink the bytes further.
				{ level: 0 }
			);
			tracksAdded++;
		}
		onProgress?.({
			stage: 'tracks',
			current: Math.min(i + batch.length, opts.runsWithTracks.length),
			total: opts.runsWithTracks.length
		});
	}

	const incomplete = [
		...new Set([
			...(opts.incompleteSections ?? []),
			...(tracksAdded < opts.runsWithTracks.length ? ['tracks'] : [])
		])
	].sort();
	const manifest = {
		format: BACKUP_FORMAT,
		version: BACKUP_VERSION,
		exported_at: new Date().toISOString(),
		exported_by_user_id: opts.userId,
		exported_from: opts.exportedFrom,
		counts: {
			runs: opts.runsOut.length,
			routes: opts.routesOut.length,
			goals: 0,
			tracks: tracksAdded
		},
		complete: incomplete.length === 0,
		incomplete
	};
	await zipWriter.add('manifest.json', new TextReader(JSON.stringify(manifest, null, 2)));

	onProgress?.({ stage: 'writing', current: 0, total: 1 });
	const blob = await zipWriter.close();
	onProgress?.({ stage: 'done', current: 1, total: 1 });
	return {
		blob,
		incomplete,
		blobsWanted: opts.runsWithTracks.length,
		blobsWritten: tracksAdded
	};
}

function stripId(row: Record<string, unknown>): Record<string, unknown> {
	const { id: _id, ...rest } = row;
	return rest;
}
