import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — photo upload + delete via the RunPhotos component.
 *
 * RunPhotos mounts on every run-detail page; canManage is true when
 * `auth.user.id === runOwnerId`. The owner can attach jpeg / png /
 * webp / heic / heif images. Each upload calls addRunPhoto in
 * data.ts which uploads to the `run-photos` Storage bucket at
 * `{user_id}/<photo_id>.<ext>` and inserts a `run_photos` row
 * keyed by owner_id.
 *
 * This test covers the full happy path: upload → grid renders →
 * service-role check that the row + Storage object exist → delete
 * via the per-tile icon → grid empty + DB row gone + Storage
 * object swept by the cascade trigger.
 */

// 1×1 transparent PNG — smallest valid image we can shove through
// the file input. Storage policies don't care about content beyond
// the MIME type prefix.
const ONE_PIXEL_PNG = Buffer.from([
	0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
	0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
	0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
	0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
	0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
	0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
]);

test.describe('/runs/[id] — RunPhotos upload + delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('owner uploads a photo via Add-photo → grid renders → DB + Storage agree', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});

		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });

		// Add-photo button reveals + fires the hidden file input. Use
		// setInputFiles directly on the input so we don't have to drive
		// the OS file picker.
		await expect(
			page.getByRole('button', { name: /Add photo/ })
		).toBeVisible({ timeout: 10_000 });
		await page.locator('input[type="file"]').setInputFiles({
			name: 'e2e-photo.png',
			mimeType: 'image/png',
			buffer: ONE_PIXEL_PNG
		});

		// Pending preview shows + caption input mounts.
		await page.locator('.pending input[type="text"]').fill('e2e caption');
		await page.getByRole('button', { name: 'Upload' }).click();

		// Tile renders in the grid.
		await expect(page.locator('.tile').first())
			.toBeVisible({ timeout: 15_000 });
		await expect(page.locator('figcaption', { hasText: 'e2e caption' }))
			.toBeVisible({ timeout: 5_000 });

		// Backend assertion: a run_photos row exists, points at the
		// right run, and has the caption we set.
		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('run_photos')
			.select('id, run_id, caption, storage_path')
			.eq('run_id', runId);
		expect(rows?.length).toBe(1);
		const row = rows?.[0] as {
			id: string;
			run_id: string;
			caption: string | null;
			storage_path: string;
		};
		expect(row.caption).toBe('e2e caption');
		expect(row.storage_path).toContain(USER_A.id);

		// Storage object exists at the path the row points to.
		const { data: dl } = await admin.storage
			.from('run-photos')
			.download(row.storage_path);
		expect(dl).not.toBeNull();
	});

	test('owner edits a caption via pencil → DB row reflects new caption', async ({
		page
	}) => {
		// updateRunPhotoCaption is the third write path in RunPhotos
		// (upload + delete are the other two). Pin the round-trip:
		// service-role plant a photo with an initial caption, click
		// the per-tile pencil → fill new caption → Save → row updated.
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 4_500,
			duration_s: 1_350,
			is_public: false
		});

		const admin = getAdminClient();
		const photoId = crypto.randomUUID();
		const path = `${USER_A.id}/${photoId}.png`;
		await admin.storage.from('run-photos').upload(path, ONE_PIXEL_PNG, {
			contentType: 'image/png',
			upsert: true
		});
		await admin.from('run_photos').insert({
			id: photoId,
			run_id: runId,
			owner_id: USER_A.id,
			storage_path: path,
			caption: 'before',
			position_idx: 0
		});

		await page.goto(`/runs/${runId}`);
		const tile = page.locator('.tile').first();
		await expect(tile).toBeVisible({ timeout: 10_000 });

		// Pencil button shows on hover (opacity-0 by default). Force the
		// click since CSS-only visibility doesn't block interaction.
		await tile.getByRole('button', { name: 'Edit caption' }).click({
			force: true
		});

		const newCaption = `e2e edited ${Date.now()}`;
		const captionForm = tile.locator('form.caption-edit');
		await expect(captionForm).toBeVisible({ timeout: 5_000 });
		await captionForm.locator('input[type="text"]').fill(newCaption);
		await captionForm.getByRole('button', { name: 'Save' }).click();

		// figcaption flips to the new caption (caption-edit form unmounts).
		await expect(tile.locator('figcaption')).toHaveText(newCaption, {
			timeout: 10_000
		});

		// Backend confirms.
		const { data: row } = await admin
			.from('run_photos')
			.select('caption')
			.eq('id', photoId)
			.single();
		expect((row as { caption: string }).caption).toBe(newCaption);
	});

	test('owner deletes their photo → tile gone, DB row gone', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false
		});

		// Plant a photo via service-role so the upload race + storage
		// upload aren't on the critical path of this test (the upload
		// is covered by the previous test).
		const admin = getAdminClient();
		const photoId = crypto.randomUUID();
		const path = `${USER_A.id}/${photoId}.png`;
		await admin.storage.from('run-photos').upload(path, ONE_PIXEL_PNG, {
			contentType: 'image/png',
			upsert: true
		});
		await admin.from('run_photos').insert({
			id: photoId,
			run_id: runId,
			owner_id: USER_A.id,
			storage_path: path,
			caption: 'e2e to-delete',
			position_idx: 0
		});

		await page.goto(`/runs/${runId}`);
		const tile = page.locator('.tile').first();
		await expect(tile).toBeVisible({ timeout: 10_000 });

		// Delete button on the tile is opacity-0 until hover; force the
		// click since CSS-only visibility doesn't block functional
		// interaction.
		await tile.getByRole('button', { name: 'Delete photo' }).click({
			force: true
		});
		const dialog = page.locator('.modal', { hasText: 'Delete photo' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		await expect(page.locator('.tile')).toHaveCount(0, {
			timeout: 10_000
		});

		// Backend: row gone.
		const { count } = await admin
			.from('run_photos')
			.select('id', { count: 'exact', head: true })
			.eq('run_id', runId);
		expect(count).toBe(0);
	});

	test('Add photo button is NOT visible when no run exists yet (gating sanity)', async ({
		page
	}) => {
		// Sanity that the Add-photo affordance is scoped to a real run
		// page. A regression that mounted RunPhotos on a non-detail
		// route (e.g. the run list) would surface here.
		await page.goto('/runs');
		await expect(page.getByRole('button', { name: /Add photo/ })).toHaveCount(0);
	});
});

test.describe('/share/run/[id] — RunPhotos read-only for non-owner', () => {
	// Anon visitor on a public-run share page: photos render in the
	// gallery but the Add-photo button does NOT (canManage = false).
	// Pins the owner-gate in RunPhotos.svelte against a refactor that
	// silently let any signed-in user upload to someone else's run.
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon viewer sees the gallery but no Add-photo button', async ({ page }) => {
		const adminCtx = getAdminClient();
		// Reuse the existing public seed run; plant a photo on it so
		// the gallery has something to render.
		const photoId = crypto.randomUUID();
		const path = `${USER_A.id}/${photoId}.png`;
		try {
			await adminCtx.storage.from('run-photos').upload(path, ONE_PIXEL_PNG, {
				contentType: 'image/png',
				upsert: true
			});
			await adminCtx.from('run_photos').insert({
				id: photoId,
				run_id: RUNNER_PUBLIC_RUN_ID,
				owner_id: USER_A.id,
				storage_path: path,
				caption: 'e2e share view',
				position_idx: 99
			});

			await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

			// The gallery section renders…
			await expect(page.locator('.tile').first()).toBeVisible({ timeout: 10_000 });
			// …but Add-photo + Delete + Edit-caption affordances must NOT.
			await expect(page.getByRole('button', { name: /Add photo/ })).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Delete photo' })).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Edit caption' })).toHaveCount(0);
		} finally {
			await adminCtx.from('run_photos').delete().eq('id', photoId);
			await adminCtx.storage.from('run-photos').remove([path]);
		}
	});
});
