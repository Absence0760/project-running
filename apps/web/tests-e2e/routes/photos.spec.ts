import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] — photo upload + caption + delete via the RoutePhotos
 * component (backlog C1 — the run_photos capability applied to routes).
 *
 * RoutePhotos mounts on the route-detail page; canManage is true when
 * `auth.user.id === routeOwnerId`. The owner uploads through
 * addRoutePhoto in data.ts which strips EXIF, uploads to the private
 * `route-photos` Storage bucket at `{user_id}/<photo_id>.<ext>`, and
 * inserts a `route_photos` row keyed by owner_id.
 */

const ONE_PIXEL_PNG = Buffer.from([
	0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
	0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
	0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
	0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
	0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
	0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
]);

async function insertOwnedRoute(isPublic: boolean): Promise<string> {
	const admin = getAdminClient();
	const id = crypto.randomUUID();
	const { error } = await admin.from('routes').insert({
		id,
		user_id: USER_A.id,
		name: 'E2E route-photos course',
		waypoints: [
			{ lat: 51.5, lng: -0.12 },
			{ lat: 51.51, lng: -0.13 }
		],
		distance_m: 5_000,
		is_public: isPublic
	});
	if (error) throw new Error(`insertOwnedRoute failed: ${error.message}`);
	return id;
}

test.describe('/routes/[id] — RoutePhotos upload + caption + delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* best-effort; cascade clears route_photos */
			}
			routeId = null;
		}
	});

	test('owner uploads a photo via Add-photo → grid renders → DB + Storage agree', async ({
		page
	}) => {
		routeId = await insertOwnedRoute(false);

		await page.goto(`/routes/${routeId}`);
		await expect(
			page.getByRole('button', { name: /Add photo/ })
		).toBeVisible({ timeout: 10_000 });

		await page.locator('input[type="file"]').setInputFiles({
			name: 'e2e-route-photo.png',
			mimeType: 'image/png',
			buffer: ONE_PIXEL_PNG
		});

		await page.locator('.pending input[type="text"]').fill('e2e route caption');
		await page.getByRole('button', { name: 'Upload' }).click();

		await expect(page.locator('.tile').first()).toBeVisible({ timeout: 15_000 });
		await expect(
			page.locator('figcaption', { hasText: 'e2e route caption' })
		).toBeVisible({ timeout: 5_000 });

		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('route_photos')
			.select('id, route_id, caption, storage_path')
			.eq('route_id', routeId);
		expect(rows?.length).toBe(1);
		const row = rows?.[0] as {
			id: string;
			route_id: string;
			caption: string | null;
			storage_path: string;
		};
		expect(row.caption).toBe('e2e route caption');
		expect(row.storage_path).toContain(USER_A.id);

		const { data: dl } = await admin.storage
			.from('route-photos')
			.download(row.storage_path);
		expect(dl).not.toBeNull();
	});

	test('owner deletes their photo → tile gone, DB row gone', async ({ page }) => {
		routeId = await insertOwnedRoute(false);

		const admin = getAdminClient();
		const photoId = crypto.randomUUID();
		const path = `${USER_A.id}/${photoId}.png`;
		await admin.storage.from('route-photos').upload(path, ONE_PIXEL_PNG, {
			contentType: 'image/png',
			upsert: true
		});
		await admin.from('route_photos').insert({
			id: photoId,
			route_id: routeId,
			owner_id: USER_A.id,
			storage_path: path,
			caption: 'e2e to-delete',
			position_idx: 0
		});

		await page.goto(`/routes/${routeId}`);
		const tile = page.locator('.tile').first();
		await expect(tile).toBeVisible({ timeout: 10_000 });

		await tile.getByRole('button', { name: 'Delete photo' }).click({ force: true });
		const dialog = page.locator('.modal', { hasText: 'Delete photo' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		await expect(page.locator('.tile')).toHaveCount(0, { timeout: 10_000 });

		const { count } = await admin
			.from('route_photos')
			.select('id', { count: 'exact', head: true })
			.eq('route_id', routeId);
		expect(count).toBe(0);
	});
});

test.describe('/share/route/[id] — RoutePhotos read-only for non-owner', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon viewer sees the gallery but no Add-photo / delete affordances', async ({
		page
	}) => {
		const admin = getAdminClient();
		const photoId = crypto.randomUUID();
		const path = `${USER_A.id}/${photoId}.png`;
		try {
			await admin.storage.from('route-photos').upload(path, ONE_PIXEL_PNG, {
				contentType: 'image/png',
				upsert: true
			});
			await admin.from('route_photos').insert({
				id: photoId,
				route_id: RUNNER_PUBLIC_ROUTE_ID,
				owner_id: USER_A.id,
				storage_path: path,
				caption: 'e2e share-route view',
				position_idx: 99
			});

			await page.goto(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);

			await expect(page.locator('.tile').first()).toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('button', { name: /Add photo/ })).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Delete photo' })).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Edit caption' })).toHaveCount(0);
		} finally {
			await admin.from('route_photos').delete().eq('id', photoId);
			await admin.storage.from('route-photos').remove([path]);
		}
	});
});
