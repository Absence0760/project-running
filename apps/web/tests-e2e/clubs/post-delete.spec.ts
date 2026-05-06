import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] Feed tab — post delete.
 *
 * `cross-cutting/clubs-journey.spec.ts` covers post create + the
 * post-list refresh; club deletion at the end of that journey
 * cascades the post away. This test isolates the explicit
 * Delete-post path (admin-only icon button on each post row →
 * ConfirmDialog → deleteClubPost RPC).
 *
 * Runner is the owner of Sydney Run Club, so isAdmin=true and the
 * Delete-post button renders. Self-contained: post a fresh message,
 * delete it, verify gone.
 */

test.describe('/clubs/[slug] — post delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('post → delete via the admin icon → confirm → post gone', async ({
		page
	}) => {
		const body = `e2e-post-delete ${Date.now()}`;

		await page.goto('/clubs/sydney-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Composer is gated on `isMember = club.viewer_role != null` —
		// runner is the owner per seed, but there's an auth-race window
		// after the heading mounts where viewer_role hasn't lifted off
		// fetchClubBySlug yet (the seeded session takes a beat to
		// resolve via supabase.auth.getSession in the data layer).
		// Wait for the composer to actually mount before filling.
		const composer = page.locator('.post-form textarea').first();
		await expect(composer).toBeVisible({ timeout: 15_000 });
		await composer.fill(body);
		await page.locator('.post-form button[type="submit"]').click();
		const post = page.locator('article.post', { hasText: body });
		await expect(post).toBeVisible({ timeout: 10_000 });

		// Click the Delete-post icon on the new post's row.
		await post.getByRole('button', { name: 'Delete post' }).click();
		const dialog = page.locator('.modal', { hasText: 'Delete post' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
		await expect(dialog).toHaveCount(0);

		// Post is gone from the list. Other posts in the seed (if any)
		// remain — assert specifically on the test's body text.
		await expect(page.locator('article.post', { hasText: body }))
			.toHaveCount(0, { timeout: 10_000 });
	});
});
