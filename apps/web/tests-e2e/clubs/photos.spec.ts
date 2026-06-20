import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /clubs/[slug] Photos tab — the club photo gallery (roadmap backlog
 * row 8, the deferred "club-photo features").
 *
 * ClubPhotos mounts under the Photos tab on the club-detail page.
 * canUpload is true for any active member; canModerate for owner/admin.
 * The member uploads through addClubPhoto in data.ts which strips EXIF,
 * uploads to the private `club-photos` Storage bucket at
 * `{user_id}/<photo_id>.<ext>`, and inserts a `club_photos` row keyed by
 * owner_id. USER_A owns richmond-run-club (active owner → member + admin);
 * USER_B is NOT a member of the public nova-trail-crew (read-only view).
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';
const NOVA_CLUB_ID = 'c4444444-0000-0000-0000-000000000004';
const NOVA_SLUG = 'nova-trail-crew';

const ONE_PIXEL_PNG = Buffer.from([
	0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
	0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
	0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
	0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
	0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
	0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
]);

async function openPhotosTab(page: import('@playwright/test').Page, slug: string) {
	await page.goto(`/clubs/${slug}?tab=photos`);
	await expect(page.getByRole('tab', { name: /Photos/ })).toBeVisible({ timeout: 10_000 });
}

test.describe('/clubs/[slug] — ClubPhotos upload + delete (member/owner)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('club_photos')
			.select('storage_path, thumb_512_path')
			.eq('club_id', RICHMOND_CLUB_ID);
		const paths = (rows ?? [])
			.flatMap((r) => [r.storage_path, r.thumb_512_path])
			.filter((p): p is string => !!p);
		if (paths.length > 0) await admin.storage.from('club-photos').remove(paths);
		await admin.from('club_photos').delete().eq('club_id', RICHMOND_CLUB_ID);
	});

	test('owner uploads a photo via Add-photo → grid renders → DB + Storage agree', async ({
		page
	}) => {
		await openPhotosTab(page, RICHMOND_SLUG);

		await expect(page.getByRole('button', { name: /Add photo/ })).toBeVisible({
			timeout: 10_000
		});

		await page.locator('input[type="file"]').setInputFiles({
			name: 'e2e-club-photo.png',
			mimeType: 'image/png',
			buffer: ONE_PIXEL_PNG
		});

		await page.locator('.pending input[type="text"]').fill('e2e club caption');
		await page.getByRole('button', { name: 'Upload' }).click();

		await expect(page.locator('.tile').first()).toBeVisible({ timeout: 15_000 });
		await expect(
			page.locator('figcaption', { hasText: 'e2e club caption' })
		).toBeVisible({ timeout: 5_000 });

		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('club_photos')
			.select('id, club_id, caption, storage_path')
			.eq('club_id', RICHMOND_CLUB_ID);
		expect(rows?.length).toBe(1);
		const row = rows?.[0] as {
			id: string;
			club_id: string;
			caption: string | null;
			storage_path: string;
		};
		expect(row.caption).toBe('e2e club caption');
		expect(row.storage_path).toContain(USER_A.id);

		const { data: dl } = await admin.storage.from('club-photos').download(row.storage_path);
		expect(dl).not.toBeNull();
	});

	test('owner deletes a photo → tile gone, DB row gone', async ({ page }) => {
		const admin = getAdminClient();
		const photoId = crypto.randomUUID();
		const path = `${USER_A.id}/${photoId}.png`;
		await admin.storage.from('club-photos').upload(path, ONE_PIXEL_PNG, {
			contentType: 'image/png',
			upsert: true
		});
		await admin.from('club_photos').insert({
			id: photoId,
			club_id: RICHMOND_CLUB_ID,
			owner_id: USER_A.id,
			storage_path: path,
			caption: 'e2e to-delete',
			position_idx: 0
		});

		await openPhotosTab(page, RICHMOND_SLUG);
		const tile = page.locator('.tile').first();
		await expect(tile).toBeVisible({ timeout: 10_000 });

		await tile.getByRole('button', { name: 'Delete photo' }).click({ force: true });
		const dialog = page.locator('.modal', { hasText: 'Delete photo' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		await expect(page.locator('.tile')).toHaveCount(0, { timeout: 10_000 });

		const { count } = await admin
			.from('club_photos')
			.select('id', { count: 'exact', head: true })
			.eq('club_id', RICHMOND_CLUB_ID);
		expect(count).toBe(0);
	});
});

test.describe('/clubs/[slug] — ClubPhotos read-only for a non-member', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('non-member of a public club sees the gallery but no Add-photo / delete', async ({
		page
	}) => {
		const admin = getAdminClient();
		const photoId = crypto.randomUUID();
		const path = `${USER_A.id}/${photoId}.png`;
		try {
			await admin.storage.from('club-photos').upload(path, ONE_PIXEL_PNG, {
				contentType: 'image/png',
				upsert: true
			});
			await admin.from('club_photos').insert({
				id: photoId,
				club_id: NOVA_CLUB_ID,
				owner_id: USER_A.id,
				storage_path: path,
				caption: 'e2e public-club view',
				position_idx: 0
			});

			await openPhotosTab(page, NOVA_SLUG);

			await expect(page.locator('.tile').first()).toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('button', { name: /Add photo/ })).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Delete photo' })).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Edit caption' })).toHaveCount(0);
		} finally {
			await admin.from('club_photos').delete().eq('id', photoId);
			await admin.storage.from('club-photos').remove([path]);
		}
	});
});
