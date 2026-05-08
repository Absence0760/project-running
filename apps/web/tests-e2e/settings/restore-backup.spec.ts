import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/account — Restore from backup.
 *
 * Pins the full restore round-trip: build a small backup ZIP in the
 * test, upload it via the hidden file input on /settings/account,
 * confirm the dialog, then verify two downstream surfaces actually
 * see the new rows:
 *
 *   1. /dashboard — the "This Week" mileage card increases by the
 *      total distance of imported runs that fall in the current
 *      week. This is the easiest user-visible signal that the
 *      restore actually wrote data, since the card aggregates runs
 *      per `started_at` window.
 *   2. /runs — the run list contains a row whose title matches the
 *      one we set in `metadata.title`. This confirms the row landed
 *      with a working metadata payload.
 *
 * The restore path is `apps/web/src/lib/backup.ts:restoreBackup` —
 * it `upsert`s by `id`, so deterministic UUIDs make the cleanup
 * trivial even when the test is interrupted.
 *
 * Companion to `apps/mobile_android/test/backup_test.dart` which
 * pins the same ZIP shape on the Flutter side.
 */

const RESTORE_ID_1 = '11111111-2222-3333-4444-e2eb01000001';
const RESTORE_ID_2 = '11111111-2222-3333-4444-e2eb01000002';
const RESTORE_ID_3 = '11111111-2222-3333-4444-e2eb01000003';

/** Build a minimal `run-app-backup` ZIP in memory. */
async function buildBackupZip(runs: Array<Record<string, unknown>>): Promise<Buffer> {
	const JSZip = (await import('jszip')).default;
	const zip = new JSZip();
	zip.file(
		'manifest.json',
		JSON.stringify({
			format: 'run-app-backup',
			version: 1,
			exported_at: new Date().toISOString(),
			exported_from: 'e2e-restore-backup-spec',
			counts: { runs: runs.length, routes: 0, goals: 0, tracks: 0 }
		})
	);
	zip.file('runs.json', JSON.stringify(runs));
	const arr = await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
	return Buffer.from(arr);
}

/** A run row in the shape `restoreBackup` expects (DB columns minus
 *  `user_id`, which the restore helper fills in from `auth.user`). */
function runRow(opts: {
	id: string;
	started_at: string;
	duration_s: number;
	distance_m: number;
	title: string;
}): Record<string, unknown> {
	return {
		id: opts.id,
		started_at: opts.started_at,
		duration_s: opts.duration_s,
		distance_m: opts.distance_m,
		source: 'app',
		is_public: false,
		metadata: {
			activity_type: 'run',
			title: opts.title,
			imported_from: 'e2e-restore-backup-spec'
		}
	};
}

/** Drop the test rows by id. Service-role bypasses RLS. */
async function cleanup(ids: string[]): Promise<void> {
	const admin = getAdminClient();
	await admin.from('runs').delete().in('id', ids);
}

/** Read the current week's distance from the dashboard hero card.
 *  The "This Week" card renders e.g. "12.4 km" or "7.7 mi" — we just
 *  scrape the numeric prefix. Returns 0 when the card is absent
 *  (empty-state). */
async function thisWeekDistanceKm(page: import('@playwright/test').Page): Promise<number> {
	await page.goto('/dashboard');
	const card = page.getByRole('button', { name: /This Week/i }).first();
	await expect(card).toBeVisible({ timeout: 10_000 });
	const text = (await card.innerText()).trim();
	const m = text.match(/([0-9]+(?:\.[0-9]+)?)\s*(km|mi)/i);
	if (!m) return 0;
	const value = parseFloat(m[1]);
	const unit = m[2].toLowerCase();
	return unit === 'mi' ? value * 1.609344 : value;
}

test.describe('/settings/account — restore-from-backup propagation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await cleanup([RESTORE_ID_1, RESTORE_ID_2, RESTORE_ID_3]);
	});

	test('importing a backup with this-week runs updates the Dashboard "This Week" card',
		async ({ page }) => {
			// Baseline — what the dashboard says BEFORE the import.
			const before = await thisWeekDistanceKm(page);

			// Build a single run with started_at = now (guaranteed
			// inside the current week) and a distinct distance so the
			// delta is measurable.
			const importedDistanceM = 7321; // ~7.32 km, a sharp signal
			const startedAt = new Date().toISOString();
			const buf = await buildBackupZip([
				runRow({
					id: RESTORE_ID_1,
					started_at: startedAt,
					duration_s: 1800,
					distance_m: importedDistanceM,
					title: `e2e-restore-this-week ${Date.now()}`
				})
			]);

			await page.goto('/settings/account');
			// The Restore button click triggers the hidden file input.
			// setInputFiles drives the input directly — same pattern as
			// `routes/import.spec.ts` for the route ZIP path.
			await page.locator('input[type="file"][accept=".zip"]').setInputFiles({
				name: 'e2e-restore.zip',
				mimeType: 'application/zip',
				buffer: buf
			});
			// ConfirmDialog opens with title "Restore from backup".
			const dialog = page.locator('.modal', { hasText: /Restore from backup/i });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: /^Restore$/ }).click();

			// Result line on the page: "Restored 1 runs, 0 tracks, 0 routes."
			await expect(page.getByText(/Restored 1 runs/)).toBeVisible({ timeout: 15_000 });

			// Dashboard now reflects the +7.32 km. Allow a small float
			// tolerance for unit rounding (the card may render "12.4 km"
			// rather than "12.42 km").
			const after = await thisWeekDistanceKm(page);
			const delta = after - before;
			expect(delta).toBeGreaterThan(importedDistanceM / 1000 - 0.2);
			expect(delta).toBeLessThan(importedDistanceM / 1000 + 0.2);
		});

	test('importing a backup with multiple runs makes them appear on /runs',
		async ({ page }) => {
			const titleA = `e2e-restore-runs-A ${Date.now()}`;
			const titleB = `e2e-restore-runs-B ${Date.now()}`;
			const buf = await buildBackupZip([
				runRow({
					id: RESTORE_ID_2,
					started_at: '2026-04-01T08:00:00.000Z',
					duration_s: 1500,
					distance_m: 5000,
					title: titleA
				}),
				runRow({
					id: RESTORE_ID_3,
					started_at: '2026-04-02T08:00:00.000Z',
					duration_s: 1800,
					distance_m: 6000,
					title: titleB
				})
			]);

			await page.goto('/settings/account');
			await page.locator('input[type="file"][accept=".zip"]').setInputFiles({
				name: 'e2e-restore-multi.zip',
				mimeType: 'application/zip',
				buffer: buf
			});
			const dialog = page.locator('.modal', { hasText: /Restore from backup/i });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: /^Restore$/ }).click();
			await expect(page.getByText(/Restored 2 runs/)).toBeVisible({ timeout: 15_000 });

			// Both rows surface on the run list. Each row is an
			// `<a href="/runs/<id>">` so we match by URL — the list's
			// rendered link text is "{date} {source} {distance} ..."
			// and doesn't include the metadata title.
			//
			// /runs's "Date range" filter defaults to "Today" on a
			// fresh load — our imported runs are dated April 2026, so
			// flip to "All time" before asserting. This mirrors the
			// realistic flow: restore, then widen the date range to
			// find historical runs.
			await page.goto('/runs');
			await page.getByRole('combobox', { name: /Date range/i }).selectOption('all');
			await expect(page.locator(`a[href="/runs/${RESTORE_ID_2}"]`))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.locator(`a[href="/runs/${RESTORE_ID_3}"]`))
				.toBeVisible({ timeout: 5_000 });

			// Confirm the metadata title round-tripped through the
			// import — the run-detail h1 displays it.
			await page.locator(`a[href="/runs/${RESTORE_ID_2}"]`).click();
			await expect(page.getByRole('heading', { level: 1, name: new RegExp(titleA) }))
				.toBeVisible({ timeout: 10_000 });
		});

	test('re-importing the same backup is idempotent (no duplicate rows)',
		async ({ page }) => {
			// `restoreBackup` upserts by id. Importing the same ZIP
			// twice should produce a single row, not two — the user's
			// real-world expectation when they rerun an import to
			// "make sure it took". Pin that contract.
			const startedAt = '2026-04-03T08:00:00.000Z';
			const distanceM = 4321;
			const buf = await buildBackupZip([
				runRow({
					id: RESTORE_ID_1,
					started_at: startedAt,
					duration_s: 1200,
					distance_m: distanceM,
					title: `e2e-restore-idempotent ${Date.now()}`
				})
			]);

			async function importOnce(label: string) {
				await page.goto('/settings/account');
				await page.locator('input[type="file"][accept=".zip"]').setInputFiles({
					name: `e2e-restore-${label}.zip`,
					mimeType: 'application/zip',
					buffer: buf
				});
				const dialog = page.locator('.modal', { hasText: /Restore from backup/i });
				await expect(dialog).toBeVisible({ timeout: 5_000 });
				await dialog.getByRole('button', { name: /^Restore$/ }).click();
				await expect(page.getByText(/Restored 1 runs/)).toBeVisible({ timeout: 15_000 });
			}

			await importOnce('first');
			await importOnce('second');

			// DB-level verification: exactly one row exists for the
			// deterministic id, with the values we expect. Service-role
			// bypasses RLS so we see the user's row directly.
			const admin = getAdminClient();
			const { data, error } = await admin
				.from('runs')
				.select('id, distance_m, started_at')
				.eq('id', RESTORE_ID_1);
			expect(error).toBeNull();
			expect(data).toHaveLength(1);
			expect(data![0].distance_m).toBe(distanceM);
		});
});
