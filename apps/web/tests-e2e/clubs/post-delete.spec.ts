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
 * Runner is the owner of Richmond Run Club, so isAdmin=true and the
 * Delete-post button renders. Self-contained: post a fresh message,
 * delete it, verify gone.
 */

test.describe('/clubs/[slug] — post delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a member without admin powers does not see the Delete-post icon on others\' posts', async ({
		browser
	}) => {
		// Pin the negative side of the admin-gate: a normal member who
		// did NOT author a post must NOT see the Delete-post icon on
		// it. The icon-btn renders only when canDelete (post author OR
		// club admin). A regression that exposed the icon to all
		// members would let any member nuke any other member's posts.
		const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
		const body = `e2e-post-gating ${Date.now()}`;

		// Owner posts via service-role to skip the composer race.
		const { getAdminClient } = await import('../fixtures/local-supabase');
		const admin = getAdminClient();
		const { data: planted, error } = await admin
			.from('club_posts')
			.insert({
				club_id: SYDNEY_RUN_CLUB_ID,
				author_id: USER_A.id,
				body
			})
			.select('id')
			.single();
		if (error) throw error;
		const postId = (planted as { id: string }).id;

		try {
			// Visit as alex (USER_B) — alex is an active member of
			// Richmond Run Club per seed but NOT an admin/owner.
			const { USER_B } = await import('../fixtures/users');
			const ctxAlex = await browser.newContext({
				storageState: USER_B.storageStatePath
			});
			const alex = await ctxAlex.newPage();
			try {
				await alex.goto('/clubs/richmond-run-club');
				const post = alex.locator('article.post', { hasText: body });
				await expect(post).toBeVisible({ timeout: 10_000 });
				// Delete-post button absent for the non-author non-admin.
				await expect(
					post.getByRole('button', { name: 'Delete post' })
				).toHaveCount(0);
			} finally {
				await ctxAlex.close();
			}
		} finally {
			await admin.from('club_posts').delete().eq('id', postId);
		}
	});

	test('post → delete via the admin icon → confirm → post gone', async ({
		page
	}) => {
		const body = `e2e-post-delete ${Date.now()}`;

		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
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
