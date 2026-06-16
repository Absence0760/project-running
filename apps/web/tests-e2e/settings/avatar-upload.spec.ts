import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Avatar upload — the in-app profile-picture feature (data.ts uploadAvatar /
 * removeAvatar → the public `avatars` Storage bucket, migration 20260927_001).
 *
 *   1. USER_A picks a PNG in /settings/account; uploadAvatar writes
 *      {uid}/avatar.png to the public bucket and points avatar_url at it.
 *   2. The owner's /u/[id] profile renders the <img> (decodes, naturalWidth>0).
 *   3. A second user (USER_C_PRO) sees the same avatar — it's public.
 *   4. Uploading a JPEG that carries an EXIF "Exif" APP1 segment with fake GPS
 *      proves the privacy-critical client-side strip: the STORED object has no
 *      "Exif" bytes (stripExifFromFile ran before the public upload), and the
 *      prior .png object was swept on the format switch.
 *   5. Remove clears avatar_url back to null and deletes the objects.
 *
 * USER_A's avatar_url is shared seed state, so the original value is captured
 * up front and restored in `finally` (with a sweep of any object we created).
 */

// A valid, decodable 1x1 transparent PNG — used for the render assertions.
const PNG_1x1 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
	'base64',
);

// A minimal JPEG carrying an APP1 "Exif" segment with fake GPS-ish bytes — the
// thing stripExifFromFile must drop before a geotagged selfie reaches the
// world-readable bucket. SOI + APP1(Exif…) + EOI.
function jpegWithExif(): Buffer {
	const exifPayload = Buffer.concat([
		Buffer.from('Exif\0\0', 'latin1'),
		// II* TIFF header + a few filler bytes standing in for a GPS IFD.
		Buffer.from([0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00]),
	]);
	const len = exifPayload.length + 2; // length field includes its own 2 bytes
	const app1 = Buffer.concat([
		Buffer.from([0xff, 0xe1, (len >> 8) & 0xff, len & 0xff]),
		exifPayload,
	]);
	return Buffer.concat([
		Buffer.from([0xff, 0xd8]), // SOI
		app1,
		Buffer.from([0xff, 0xd9]), // EOI
	]);
}

const decodes = (img: HTMLImageElement) => img.complete && img.naturalWidth > 0;

test.describe('avatar upload', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('upload PNG → owner + others see it → EXIF stripped on JPEG → remove', async ({
		page,
		browser,
	}) => {
		const admin = getAdminClient();
		const objectPaths = ['jpg', 'png', 'webp'].map((e) => `${USER_A.id}/avatar.${e}`);
		// Service-role list bypasses RLS — the robust way to assert which objects
		// actually exist for the user (download-of-missing isn't reliably null).
		const avatarNames = async (): Promise<string[]> => {
			const { data } = await admin.storage.from('avatars').list(USER_A.id);
			return (data ?? []).map((i) => i.name);
		};

		const { data: before } = await admin
			.from('user_profiles')
			.select('avatar_url')
			.eq('id', USER_A.id)
			.single();
		const originalAvatar = (before?.avatar_url as string | null) ?? null;

		try {
			// ── 1. Upload a PNG via the real file input ─────────────────
			await test.step('USER_A uploads a PNG avatar', async () => {
				await page.goto('/settings/account');
				await page.getByTestId('avatar-change').waitFor({ timeout: 10_000 });
				await page
					.getByTestId('avatar-file-input')
					.setInputFiles({ name: 'me.png', mimeType: 'image/png', buffer: PNG_1x1 });
				await expect(page.locator('.toast-success')).toContainText(/updated/i, {
					timeout: 10_000,
				});

				// avatar_url now points at the public avatars bucket; the object exists.
				const { data: after } = await admin
					.from('user_profiles')
					.select('avatar_url')
					.eq('id', USER_A.id)
					.single();
				expect(String(after?.avatar_url ?? '')).toMatch(
					/\/storage\/v1\/object\/public\/avatars\/.*\/avatar\.png/,
				);
				expect(await avatarNames()).toContain('avatar.png');
			});

			// ── 2. Owner's public profile renders the image ─────────────
			await test.step("the owner's /u/[id] shows the avatar image", async () => {
				await page.goto(`/u/${USER_A.id}`);
				const img = page.locator('.avatar-xl img');
				await expect(img).toBeVisible({ timeout: 10_000 });
				await expect
					.poll(async () => img.evaluate(decodes), { timeout: 10_000 })
					.toBe(true);
			});

			// ── 3. A second user sees the same public avatar ────────────
			await test.step('USER_C_PRO sees the same avatar', async () => {
				const ctx = await browser.newContext({
					storageState: USER_C_PRO.storageStatePath,
				});
				const guest = await ctx.newPage();
				try {
					await guest.goto(`/u/${USER_A.id}`);
					const img = guest.locator('.avatar-xl img');
					await expect(img).toBeVisible({ timeout: 10_000 });
					await expect
						.poll(async () => img.evaluate(decodes), { timeout: 10_000 })
						.toBe(true);
				} finally {
					await ctx.close();
				}
			});

			// ── 4. EXIF is stripped before the public upload ────────────
			await test.step('uploading a geotagged JPEG strips EXIF in the stored object', async () => {
				await page.goto('/settings/account');
				await page.getByTestId('avatar-change').waitFor({ timeout: 10_000 });
				await page
					.getByTestId('avatar-file-input')
					.setInputFiles({ name: 'geo.jpg', mimeType: 'image/jpeg', buffer: jpegWithExif() });
				await expect(page.locator('.toast-success')).toContainText(/updated/i, {
					timeout: 10_000,
				});

				const names = await avatarNames();
				expect(names).toContain('avatar.jpg');
				// The prior .png object was swept on the format switch.
				expect(names).not.toContain('avatar.png');

				const { data: jpgDl } = await admin.storage
					.from('avatars')
					.download(`${USER_A.id}/avatar.jpg`);
				expect(jpgDl).toBeTruthy();
				const jpgBytes = Buffer.from(await jpgDl!.arrayBuffer());
				// The APP1 "Exif" segment (and its GPS) is gone from the stored blob.
				expect(jpgBytes.includes(Buffer.from('Exif', 'latin1'))).toBe(false);
			});

			// ── 5. Remove clears the avatar ─────────────────────────────
			await test.step('USER_A removes the avatar', async () => {
				await page.goto('/settings/account');
				await page.getByTestId('avatar-remove').click();
				await expect(page.locator('.toast-success')).toContainText(/removed/i, {
					timeout: 10_000,
				});
				const { data: cleared } = await admin
					.from('user_profiles')
					.select('avatar_url')
					.eq('id', USER_A.id)
					.single();
				expect((cleared?.avatar_url as string | null) ?? null).toBeNull();
				expect(await avatarNames()).toHaveLength(0);
			});
		} finally {
			await admin
				.from('user_profiles')
				.update({ avatar_url: originalAvatar })
				.eq('id', USER_A.id);
			await admin.storage.from('avatars').remove(objectPaths);
		}
	});
});
