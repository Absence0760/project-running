import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Profile + avatar JOURNEY — a user edits their public identity and the
 * change surfaces on their public profile, both as they see it and as a
 * SECOND, different user sees it. Threads ONE display-name + avatar
 * change through:
 *
 *   1. USER_A on /settings/account edits the Display Name (unique via
 *      Date.now()) through the REAL profile-editor UI (the same
 *      `handleSave` → `user_profiles.update({ display_name })` path a
 *      human drives), waits for the "Saved!" button cue, and the save
 *      persists across a reload.
 *   2. Backend cross-check: the user_profiles row carries the new
 *      display_name + the avatar_url we set.
 *   3. /u/[USER_A.id] (the owner's own public profile) shows the new
 *      display_name as the <h1> hero heading AND renders the avatar as
 *      an <img> (.avatar-xl img), not the initial placeholder.
 *   4. In a SECOND browser context, USER_C_PRO (a DIFFERENT, pro user)
 *      opens /u/[USER_A.id] and sees the SAME new name + the avatar
 *      <img> — proving the change is genuinely public, not local state.
 *
 * Why the avatar is seeded via the admin client, not driven through a
 * file-upload UI:
 *   The web app has NO avatar-upload surface today (see the PRODUCT-GAP
 *   note below + the "future depth: profile avatar upload" comment at
 *   the top of settings/account.spec.ts). `/settings/account` edits the
 *   display name but exposes no <input type="file"> for an avatar, there
 *   is no `avatars` Storage bucket (only runs / run-photos / route-
 *   photos), and nothing in the client ever WRITES user_profiles.
 *   avatar_url — it is read-only on web, populated only from an OAuth
 *   provider's identity_data at sign-up. So there is no real upload
 *   button to click. This journey therefore seeds avatar_url to a valid
 *   `https://` URL through the admin client (the column the eventual
 *   upload feature WILL write) and routes that URL's <img> request to a
 *   tiny in-memory PNG in each browser context, so the avatar renders
 *   from bytes the test owns — no external network dependency. The
 *   `https://` scheme is mandatory: user_profiles carries a CHECK
 *   constraint (`user_profiles_avatar_url_scheme`, migration
 *   20260808_001) that rejects any non-http(s) avatar_url, and the
 *   renderer's safeImageSrc allow-lists only `https:` for DB values, so
 *   a `data:` URL would be both rejected at the DB and stripped at
 *   render. The DISPLAY-NAME half of the journey IS driven through the
 *   real UI; the avatar half asserts the real render path off a
 *   realistic stored value.
 *
 * CRITICAL teardown: USER_A is the SHARED seed user (`runner@test.com`,
 * display_name "Jared Howard") that ~50 other specs assert on (the
 * avatar-initial guard, the live-spectator handle, smoke, …). The
 * original display_name + avatar_url are captured from the row BEFORE
 * any mutation and restored in `finally`, even on failure. The avatar
 * we set is removed and the column put back to its captured value
 * (null in the seed).
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

// 1x1 transparent PNG. Routed into each context as the avatar bytes so
// the <img> actually decodes (an undecodable body would leave the img
// broken and the `complete && naturalWidth>0` checks below would fail).
const PNG_1x1 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
	'base64',
);

// A valid https:// avatar_url. It satisfies the user_profiles avatar_url
// scheme CHECK + safeImageSrc's https allow-list; the bytes are served
// locally via page.route, so the host never has to resolve.
const AVATAR_URL = `https://e2e-avatars.invalid/${Date.now()}.png`;

test.describe('profile + avatar journey', () => {
	// A multi-surface walk: a settings save round-trip + reload, the
	// owner's profile, plus a second-context cross-user view. The default
	// 30 s test timeout is tight for that many full navigations.
	test.describe.configure({ timeout: 90_000 });

	test.use({ storageState: USER_A.storageStatePath });

	test('USER_A edits name + has an avatar → owner /u sees it → a second user sees the same', async ({
		page,
		browser,
	}) => {
		const admin = getAdminClient();
		const newName = uniqueText('e2e-profile');

		// Captured from the live row BEFORE any mutation so the restore in
		// `finally` puts back the exact seed values other specs assert on.
		let originalName: string | null = null;
		let originalAvatarUrl: string | null = null;
		let captured = false;

		try {
			await test.step('capture the original profile + seed an avatar', async () => {
				const { data: before } = await admin
					.from('user_profiles')
					.select('display_name, avatar_url')
					.eq('id', USER_A.id)
					.single();
				originalName = before?.display_name ?? null;
				originalAvatarUrl = before?.avatar_url ?? null;
				captured = true;

				// Seed the avatar through the column the upload feature would
				// write (see the header note on why this isn't a UI upload).
				const { error: avatarErr } = await admin
					.from('user_profiles')
					.update({ avatar_url: AVATAR_URL })
					.eq('id', USER_A.id);
				expect(avatarErr).toBeNull();
			});

			// ── 1. Edit the Display Name through the real settings UI ─────
			await test.step('USER_A renames themself on /settings/account', async () => {
				await page.goto('/settings/account');

				const nameInput = page.getByLabel('Display Name');
				// The form hydrates from the persisted profile; assert the
				// original is in the field before clobbering it (the same
				// hydration guard the focused account spec relies on).
				await expect(nameInput).toHaveValue(originalName ?? '', {
					timeout: 10_000,
				});
				await nameInput.fill(newName);

				await page.getByRole('button', { name: /Save Profile/ }).click();
				// `handleSave` flips the button label to "Saved!" once the
				// user_profiles UPDATE resolves — wait for that before the
				// reload so it sees a persisted value, not in-flight UI.
				await expect(
					page.getByRole('button', { name: 'Saved!' }),
				).toBeVisible({ timeout: 5_000 });

				// Reload — confirms a persisted write, not optimistic state.
				await page.reload();
				await expect(page.getByLabel('Display Name')).toHaveValue(newName, {
					timeout: 10_000,
				});
			});

			// ── 2. Backend cross-check: the row carries name + avatar ─────
			await test.step('the user_profiles row reflects the new name + avatar', async () => {
				const { data: row } = await admin
					.from('user_profiles')
					.select('display_name, avatar_url')
					.eq('id', USER_A.id)
					.single();
				expect(row?.display_name).toBe(newName);
				expect(row?.avatar_url).toBe(AVATAR_URL);
			});

			// ── 3. Owner's public profile reflects name + avatar <img> ────
			await test.step('USER_A sees the new name + avatar image on /u/[me]', async () => {
				// Serve the avatar bytes locally so the <img> decodes from a
				// body the test owns (no external host resolution).
				await page.route(AVATAR_URL, (route) =>
					route.fulfill({ contentType: 'image/png', body: PNG_1x1 }),
				);

				await page.goto(`/u/${USER_A.id}`);

				// The hero <h1> is the public display name (fetchPublicProfile
				// reads user_profiles fresh on every mount — no cache).
				await expect(
					page.getByRole('heading', { name: newName, level: 1 }),
				).toBeVisible({ timeout: 10_000 });

				// The hero avatar (.avatar-xl) renders `<img src={avatar_url}>`
				// when avatar_url is set, the initial otherwise. Pin the <img>
				// branch (not initials) and that it actually decoded.
				const heroImg = page.locator('.profile-head .avatar-xl img');
				await expect(heroImg).toBeVisible({ timeout: 10_000 });
				await expect(heroImg).toHaveAttribute('src', AVATAR_URL);
				await expect
					.poll(() =>
						heroImg.evaluate(
							(el) =>
								(el as HTMLImageElement).complete &&
								(el as HTMLImageElement).naturalWidth > 0,
						),
					)
					.toBe(true);
				// Negative shape: the initial-placeholder fallback ("J" for
				// the seed name) is not what's showing — the img is.
				await expect(page.locator('.profile-head .avatar-xl')).not.toHaveText(
					/\S/,
				);
			});

			// ── 4. A DIFFERENT user sees the same public identity ─────────
			await test.step('USER_C_PRO sees USER_A’s new name + avatar', async () => {
				const ctx = await browser.newContext({
					storageState: USER_C_PRO.storageStatePath,
				});
				const guestPage = await ctx.newPage();
				try {
					await guestPage.route(AVATAR_URL, (route) =>
						route.fulfill({ contentType: 'image/png', body: PNG_1x1 }),
					);

					await guestPage.goto(`/u/${USER_A.id}`);

					await expect(
						guestPage.getByRole('heading', { name: newName, level: 1 }),
					).toBeVisible({ timeout: 10_000 });

					const guestImg = guestPage.locator(
						'.profile-head .avatar-xl img',
					);
					await expect(guestImg).toBeVisible({ timeout: 10_000 });
					await expect(guestImg).toHaveAttribute('src', AVATAR_URL);
					await expect
						.poll(() =>
							guestImg.evaluate(
								(el) =>
									(el as HTMLImageElement).complete &&
									(el as HTMLImageElement).naturalWidth > 0,
							),
						)
						.toBe(true);
				} finally {
					await ctx.close();
				}
			});
		} finally {
			// Restore the shared seed user's exact original identity — name
			// AND avatar — so the ~50 specs that assert on "Jared Howard" /
			// the initial-placeholder avatar stay green. Runs even on
			// failure; only attempts the restore if we captured the originals.
			if (captured) {
				await admin
					.from('user_profiles')
					.update({
						display_name: originalName,
						avatar_url: originalAvatarUrl,
					})
					.eq('id', USER_A.id);
			}
		}
	});
});
