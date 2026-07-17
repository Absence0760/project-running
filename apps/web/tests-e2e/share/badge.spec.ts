import { expect, test } from '@playwright/test';

import { insertAchievement, deleteAchievement } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /share/badge/[id] — share-page chrome (issue #247).
 *
 * Share pages are shell-less, so each page carries its own way back to the
 * site: the .share-logo header link plus the footer home / sign-in links.
 * The badge page shipped without them; this pins the same chrome the run
 * share page pins, on both the found and the not-available states.
 */

test.describe('/share/badge/[id] — anon chrome', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	let publicBadgeId: string | null = null;
	let privateBadgeId: string | null = null;

	test.beforeAll(async () => {
		publicBadgeId = await insertAchievement({
			user_id: USER_A.id,
			badge_key: 'distance_single',
			tier: 'gold',
			source_kind: 'distance',
			value_num: 42_195,
			is_public: true
		});
		privateBadgeId = await insertAchievement({
			user_id: USER_A.id,
			badge_key: 'streak',
			tier: 'silver',
			source_kind: 'streak',
			value_num: 14,
			is_public: false
		});
	});

	test.afterAll(async () => {
		if (publicBadgeId) await deleteAchievement(publicBadgeId).catch(() => {});
		if (privateBadgeId) await deleteAchievement(privateBadgeId).catch(() => {});
	});

	test('public badge page has the header logo and footer home links', async ({ page }) => {
		await page.goto(`/share/badge/${publicBadgeId}`);

		await expect(page.getByRole('heading', { name: 'Marathon' })).toBeVisible({
			timeout: 10_000
		});
		const logo = page.locator('.share-logo');
		await expect(logo).toBeVisible();
		await expect(logo).toHaveAttribute('href', '/');
		const footer = page.locator('.share-footer');
		await expect(footer.getByRole('link', { name: 'Threkir home' })).toHaveAttribute('href', '/');
		await expect(footer.getByRole('link', { name: 'Sign in' })).toHaveAttribute('href', '/login');
	});

	test('not-available badge page still carries the chrome', async ({ page }) => {
		await page.goto(`/share/badge/${privateBadgeId}`);

		await expect(page.getByText("This badge isn't available.")).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.share-logo')).toBeVisible();
		await expect(
			page.locator('.share-footer').getByRole('link', { name: 'Threkir home' })
		).toBeVisible();
	});
});
