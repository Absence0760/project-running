import { gunzipSync, gzipSync } from 'node:zlib';

import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Backup & restore JOURNEY — the full account-data round-trip walked
 * end to end through the REAL affordances on /settings/account, rather
 * than asserting one direction in isolation the way
 * settings/export.spec.ts (download shape only) and
 * settings/restore-backup.spec.ts (synthetic-zip import only) each do.
 *
 *   1. Plant a recognizable run for USER_A — a deterministic id, a
 *      unique `metadata.title` + `metadata.notes` stamped with
 *      Date.now(), AND a real GPS track (gzipped into the `runs`
 *      Storage bucket). The track makes the round-trip exercise the
 *      tracks/<id>.json.gz writer + the restore upload path, not just
 *      the row.
 *   2. Export a REAL full backup via the "Download full backup" button
 *      (createBackup → buildBackupZip, entirely client-side — no Edge
 *      Function, so no export-data rate-limit slot to wipe). Capture
 *      the download, unpack the zip with JSZip the way the
 *      privacy-data-rights + export specs do, and PROVE the planted
 *      entity is IN the payload: runs.json carries the row with its
 *      metadata.title/notes, and tracks/<id>.json.gz carries the
 *      planted track points (gunzip + JSON-parse the entry).
 *   3. DELETE the planted run (admin client — sweeps the row + its
 *      track blob). Confirm it's gone from /runs and from the DB, so
 *      the restore in step 4 has something real to bring back.
 *   4. Restore from the exact backup file captured in step 2, fed back
 *      through the REAL restore affordance (the hidden `.zip` file
 *      input + the "Restore from backup" ConfirmDialog), the same path
 *      restore-backup.spec.ts drives. The "Restored N runs" result line
 *      renders.
 *   5. Confirm the entity is BACK — the run row re-exists in the DB
 *      with the planted distance + metadata.title intact, its track was
 *      re-uploaded (track_url set), it surfaces on /runs, and its
 *      run-detail h1 shows the planted title. The data round-tripped.
 *
 * Restore is ADDITIVE, not whole-account-replace: restoreBackup →
 * restoreOrchestrate UPSERTS runs/routes BY id
 * (restore_orchestrator.ts:147,164) and upserts the profile/settings
 * from the archive's own profile.json. Because this is USER_A's OWN
 * backup, captured seconds earlier, the profile/settings it writes back
 * are USER_A's current values — a no-op for the seed. The ONLY row this
 * journey removes-then-restores is the one it planted (deterministic
 * id), so the ~200 seeded runs + USER_A's profile/zones are never
 * disturbed and downstream specs on the shard keep their preconditions.
 * Teardown deletes the planted run unconditionally via the admin client.
 */

const PLANTED_RUN_ID = '11111111-2222-3333-4444-bac01000beef';

// A small, recognizable track. The exact coords don't matter for the
// round-trip assertion; they just have to survive gzip → zip → gunzip →
// re-upload unchanged. Kept clear of USER_A's seeded Melbourne CBD
// privacy zone (irrelevant for an owner export/restore, but tidy).
const PLANTED_TRACK = [
	{ lat: -37.84, lng: 144.99, ele: 20 },
	{ lat: -37.841, lng: 144.991, ele: 21 },
	{ lat: -37.842, lng: 144.992, ele: 22 }
];

const PLANTED_DISTANCE_M = 8123; // a sharp, identifiable distance

async function downloadToBuffer(
	download: import('@playwright/test').Download
): Promise<Buffer> {
	const stream = await download.createReadStream();
	const chunks: Buffer[] = [];
	for await (const chunk of stream) chunks.push(Buffer.from(chunk));
	return Buffer.concat(chunks);
}

test.describe('backup & restore journey', () => {
	// The export builds a real zip (including a Storage track download)
	// and the restore re-uploads it; the default 30 s test timeout is
	// tight for the full round-trip.
	test.describe.configure({ timeout: 120_000 });

	test.use({ storageState: USER_A.storageStatePath });

	test('plant a run → export full backup (run is IN it) → delete it → restore → run returns', async ({
		page
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `e2e-backup-journey ${stamp}`;
		const notes = `unique-notes-${stamp}-${Math.random().toString(36).slice(2, 8)}`;

		// Holds the exported zip bytes so the restore leg feeds back the
		// EXACT archive the export produced (not a synthetic one).
		let backupZip: Buffer | null = null;

		try {
			// ── 1. Plant a recognizable run (row + metadata + track) ─────
			//
			// simulate.insertRun() mints its own id, but every leg here keys
			// off a DETERMINISTIC id (export lookup, delete, restore-returns
			// check, teardown). So plant the row directly via the admin
			// client with PLANTED_RUN_ID + upload the gzipped track to the
			// canonical {user_id}/{run_id}.json.gz path — the exact shape
			// insertRun produces, the export's track_url contract expects,
			// and deleteRun sweeps in teardown.
			await test.step('seed: a run with a unique title/notes and a real GPS track', async () => {
				const trackPath = `${USER_A.id}/${PLANTED_RUN_ID}.json.gz`;
				const { error: upErr } = await admin.storage
					.from('runs')
					.upload(
						trackPath,
						gzipSync(Buffer.from(JSON.stringify(PLANTED_TRACK), 'utf-8')),
						{ contentType: 'application/octet-stream', upsert: true }
					);
				expect(upErr, 'planted track upload must succeed').toBeNull();

				const { error: insErr } = await admin.from('runs').insert({
					id: PLANTED_RUN_ID,
					user_id: USER_A.id,
					started_at: new Date(stamp - 3 * 60_000).toISOString(),
					duration_s: 2400,
					distance_m: PLANTED_DISTANCE_M,
					source: 'app',
					is_public: false,
					activity_type: 'run',
					metadata: { activity_type: 'run', title, notes },
					track_url: trackPath
				});
				expect(insErr, 'planted run insert must succeed').toBeNull();
			});

			// ── 2. Export the REAL full backup; the planted run is inside ─
			await test.step('Download full backup, unpack it, and confirm the planted run + track are present', async () => {
				await page.goto('/settings/account');

				const downloadPromise = page.waitForEvent('download');
				await page
					.getByRole('button', { name: /Download full backup/ })
					.click();
				const download = await downloadPromise;
				expect(download.suggestedFilename()).toMatch(/^run-app-backup-.*\.zip$/);

				backupZip = await downloadToBuffer(download);
				// ZIP local-file-header magic — the bytes are a real archive.
				expect(backupZip.length).toBeGreaterThan(64);
				expect(backupZip.subarray(0, 4)).toEqual(
					Buffer.from([0x50, 0x4b, 0x03, 0x04])
				);

				const JSZip = (await import('jszip')).default;
				const zip = await JSZip.loadAsync(backupZip);

				// runs.json lists the planted run with its metadata intact.
				const runsTxt = await zip.file('runs.json')!.async('string');
				const runs = JSON.parse(runsTxt) as Array<{
					id: string;
					distance_m: number;
					track_url?: string | null;
					metadata?: { title?: string; notes?: string } | null;
				}>;
				const planted = runs.find((r) => r.id === PLANTED_RUN_ID);
				expect(
					planted,
					'the planted run must appear in the backup runs.json'
				).toBeTruthy();
				expect(planted!.distance_m).toBe(PLANTED_DISTANCE_M);
				expect(planted!.metadata?.title).toBe(title);
				expect(planted!.metadata?.notes).toBe(notes);

				// tracks/<id>.json.gz carries the planted track. Gunzip the
				// stored (already-gzipped, STORE'd) entry and parse it back to
				// the planted point set — proof the GPS data round-tripped into
				// the archive, not just the row.
				const trackEntry = zip.file(`tracks/${PLANTED_RUN_ID}.json.gz`);
				expect(
					trackEntry,
					'the planted run must have a per-run track in the backup'
				).not.toBeNull();
				const gzBytes = await trackEntry!.async('uint8array');
				const trackPts = JSON.parse(
					gunzipSync(Buffer.from(gzBytes)).toString('utf-8')
				) as Array<{ lat: number; lng: number }>;
				expect(trackPts.length).toBe(PLANTED_TRACK.length);
				expect(trackPts[0].lat).toBeCloseTo(PLANTED_TRACK[0].lat, 6);
			});

			// ── 3. Delete the planted run (the thing restore must bring back)
			await test.step('delete the planted run; confirm it is gone from the DB + /runs', async () => {
				await deleteRun(PLANTED_RUN_ID);

				const { data: gone } = await admin
					.from('runs')
					.select('id')
					.eq('id', PLANTED_RUN_ID);
				expect(gone ?? []).toHaveLength(0);

				// And gone from the list surface.
				await page.goto('/runs');
				await page
					.getByRole('combobox', { name: /Date range/i })
					.selectOption('all');
				await expect(
					page.locator(`a[href="/runs/${PLANTED_RUN_ID}"]`)
				).toHaveCount(0);
			});

			// ── 4. Restore from the captured backup via the REAL affordance ─
			await test.step('restore from the exported backup; the result line renders', async () => {
				expect(backupZip, 'export must have produced a zip').not.toBeNull();

				await page.goto('/settings/account');
				// The hidden file input behind the "Restore from backup" button.
				await page
					.locator('input[type="file"][accept=".zip"]')
					.setInputFiles({
						name: 'e2e-backup-journey-restore.zip',
						mimeType: 'application/zip',
						buffer: backupZip!
					});
				// ConfirmDialog — the user's last off-ramp.
				const dialog = page.locator('.modal', {
					hasText: /Restore from backup/i
				});
				await expect(dialog).toBeVisible({ timeout: 5_000 });
				await dialog.getByRole('button', { name: /^Restore$/ }).click();

				// "Restored N runs, M tracks, K routes." — N includes the whole
				// owner backup (seed runs + ours), so just assert the line shows
				// a positive count.
				await expect(page.locator('.ok-text')).toContainText(
					/Restored \d+ runs/,
					{ timeout: 60_000 }
				);
				// The restore must not have surfaced an error banner.
				await expect(page.locator('.error-text')).toHaveCount(0);
			});

			// ── 5. The entity is BACK — DB + Storage + UI all agree ─────
			await test.step('the planted run re-exists with its data + track, and shows on /runs', async () => {
				// Backend: the row is back under USER_A with the planted
				// distance + metadata, and its track_url was re-set (the
				// gzipped track re-uploaded to the runs bucket).
				const { data: row } = await admin
					.from('runs')
					.select('user_id, distance_m, track_url, metadata')
					.eq('id', PLANTED_RUN_ID)
					.single();
				expect(row?.user_id).toBe(USER_A.id);
				expect(row?.distance_m).toBe(PLANTED_DISTANCE_M);
				expect((row?.metadata as { title?: string } | null)?.title).toBe(
					title
				);
				expect(
					row?.track_url,
					'restore must re-upload the track + set track_url'
				).toBe(`${USER_A.id}/${PLANTED_RUN_ID}.json.gz`);

				// The re-uploaded track blob actually exists in Storage and
				// gunzips back to the planted points.
				const { data: blob, error: dlErr } = await admin.storage
					.from('runs')
					.download(`${USER_A.id}/${PLANTED_RUN_ID}.json.gz`);
				expect(dlErr).toBeNull();
				const restoredPts = JSON.parse(
					gunzipSync(Buffer.from(await blob!.arrayBuffer())).toString('utf-8')
				) as Array<{ lat: number }>;
				expect(restoredPts.length).toBe(PLANTED_TRACK.length);

				// UI: the run is back on the list, and its detail page shows the
				// title that round-tripped through export → delete → restore.
				await page.goto('/runs');
				await page
					.getByRole('combobox', { name: /Date range/i })
					.selectOption('all');
				const link = page.locator(`a[href="/runs/${PLANTED_RUN_ID}"]`);
				await expect(link).toBeVisible({ timeout: 10_000 });
				await link.click();
				await expect(
					page.getByRole('heading', { level: 1, name: new RegExp(title) })
				).toBeVisible({ timeout: 10_000 });
			});
		} finally {
			// Sweep ONLY what we planted: the run row + its (re-uploaded)
			// track blob. The seed runs + USER_A's profile/zones were never
			// touched by the additive upsert restore.
			try {
				await deleteRun(PLANTED_RUN_ID);
			} catch {
				/* best-effort: already deleted, or never created */
			}
		}
	});
});
