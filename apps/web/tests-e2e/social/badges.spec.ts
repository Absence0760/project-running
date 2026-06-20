import { expect, test } from '@playwright/test';

import { insertAchievement, deleteAchievement } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Achievements / badges (docs/features/achievements.md).
 *
 * Pins the three surfaces: the profile Achievements tab renders the owner's
 * badges, the public share page loads anonymously, and a cross-user view shows
 * only public badges (a private badge is invisible to another user, per the
 * achievements_public_select RLS policy).
 */

test.describe('Achievements — profile, share page, cross-user privacy', () => {
	let publicBadgeId: string | null = null;
	let privateBadgeId: string | null = null;

	test.beforeAll(async () => {
		// Use tier slots the seed back-fill leaves free for USER_A (the seed
		// runner already holds distance_single up to silver + pr up to silver),
		// so these inserts don't collide on (user_id, badge_key, tier).
		publicBadgeId = await insertAchievement({
			user_id: USER_A.id,
			badge_key: 'distance_single',
			tier: 'platinum',
			source_kind: 'distance',
			value_num: 60_000,
			is_public: true
		});
		privateBadgeId = await insertAchievement({
			user_id: USER_A.id,
			badge_key: 'pr',
			tier: 'gold',
			source_kind: 'pr',
			value_num: 5,
			is_public: false
		});
	});

	test.afterAll(async () => {
		if (publicBadgeId) await deleteAchievement(publicBadgeId).catch(() => {});
		if (privateBadgeId) await deleteAchievement(privateBadgeId).catch(() => {});
	});

	test.describe('as the owner', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('owner sees both the public and the private badge', async ({ page }) => {
			await page.goto(`/u/${USER_A.id}?tab=achievements`);
			await expect(page.getByText('Ultra')).toBeVisible();
			await expect(page.getByText('PR collector')).toBeVisible();
		});
	});

	test.describe('as another user', () => {
		test.use({ storageState: USER_B.storageStatePath });

		test('only the public badge is visible cross-user', async ({ page }) => {
			await page.goto(`/u/${USER_A.id}?tab=achievements`);
			await expect(page.getByText('Ultra')).toBeVisible();
			await expect(page.getByText('PR collector')).toHaveCount(0);
		});
	});

	test.describe('public share page', () => {
		test('the share page loads anonymously for a public badge', async ({ page }) => {
			await page.goto(`/share/badge/${publicBadgeId}`);
			await expect(page.getByRole('heading', { name: 'Ultra' })).toBeVisible();
		});

		test('a private badge share renders the not-available card', async ({ page }) => {
			await page.goto(`/share/badge/${privateBadgeId}`);
			await expect(page.getByText("This badge isn't available.")).toBeVisible();
		});
	});
});
