import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/[slug] — open-policy join + leave round-trip.
 *
 * Richmond Run Club has `join_policy = 'open'` so any signed-in user
 * can become a member with a single click. Morgan is not seeded into
 * any club, so this test exercises the full conversion flow:
 *   not a member  → click Join → composer mounts → click Leave →
 *   ConfirmDialog → composer gone, "Join club" CTA back.
 *
 * Cleanup: belt-and-braces — UI Leave restores the seed shape, and
 * an admin-side delete in afterEach catches any failure mid-test.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug] — open-policy join + leave', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.afterEach(async () => {
		try {
			await getAdminClient()
				.from('club_members')
				.delete()
				.eq('club_id', SYDNEY_RUN_CLUB_ID)
				.eq('user_id', USER_C_PRO.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('morgan joins the open-policy Richmond Run Club, posts a feed message, then leaves', async ({
		page
	}) => {
		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Starting state: morgan is not a member → "Join club" button
		// renders and the post composer is hidden.
		await expect(page.getByRole('button', { name: 'Join club' }))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.post-form textarea')).toHaveCount(0);

		// Click Join. The handler calls joinClub(id, 'open') which
		// inserts an active club_members row and updates viewer_role.
		await page.getByRole('button', { name: 'Join club' }).click();

		// Once active, the composer mounts (gated on isMember).
		const composer = page.locator('.post-form textarea').first();
		await expect(composer).toBeVisible({ timeout: 10_000 });

		// Posting works — proves the membership is actually active,
		// not just the UI flipping a flag.
		const body = `e2e-join-post ${Date.now()}`;
		await composer.fill(body);
		await page.locator('.post-form button[type="submit"]').click();
		await expect(
			page.locator('article.post', { hasText: body })
		).toBeVisible({ timeout: 10_000 });

		// Leave via the now-visible Leave button.
		await page.getByRole('button', { name: 'Leave' }).click();
		const dialog = page.locator('.modal', { hasText: 'Leave club' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Leave', exact: true }).click();

		// Composer is gone, Join CTA returns.
		await expect(page.locator('.post-form textarea')).toHaveCount(0, {
			timeout: 10_000
		});
		await expect(page.getByRole('button', { name: 'Join club' }))
			.toBeVisible({ timeout: 10_000 });
	});
});
