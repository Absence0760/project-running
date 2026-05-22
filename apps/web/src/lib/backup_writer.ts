/**
 * Streaming + parallel ZIP writer for the `run-app-backup` v1 format.
 *
 * Extracted from `backup.ts` so the writer is unit-testable without
 * importing supabase-js (which transitively pulls in SvelteKit's
 * `$env` virtual module, unavailable to `node --test` / `tsx --test`).
 *
 * Mirrors the mobile fix in
 * [decisions.md § 66](../../../docs/decisions.md#66-backup-zip-writes-stream-to-disk-and-download-tracks-in-bounded-batches):
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

export interface BuildBackupZipOptions {
	runsOut: Record<string, unknown>[];
	routesOut: Record<string, unknown>[];
	profile: Record<string, unknown> | null;
	settingsPrefs: Record<string, unknown>;
	userId: string;
	exportedFrom: string;
	runsWithTracks: { id: string; track_url: string }[];
	fetchTrackBytes: (trackUrl: string) => Promise<Uint8Array>;
	concurrency?: number;
	onProgress?: (p: BackupProgress) => void;
}

export async function buildBackupZip(opts: BuildBackupZipOptions): Promise<Blob> {
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
				// Swallow individual download failures — the run row
				// still ships in `runs.json`, restore will land it
				// without a track (`r.track = []`). Same partial-
				// success contract the old loop had.
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
		}
	};
	await zipWriter.add('manifest.json', new TextReader(JSON.stringify(manifest, null, 2)));

	onProgress?.({ stage: 'writing', current: 0, total: 1 });
	const blob = await zipWriter.close();
	onProgress?.({ stage: 'done', current: 1, total: 1 });
	return blob;
}

function stripId(row: Record<string, unknown>): Record<string, unknown> {
	const { id: _id, ...rest } = row;
	return rest;
}
