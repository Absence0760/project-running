import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /routes/[id] — report affordance on route-review cards. A user can
 * flag a review authored by someone else; they never see the flag on
 * their own review. A signed-out viewer never sees it either, because
 * /routes/[id] is not in the layout's anon-allowed set (like /runs/[id],
 * public read happens via /share, not the app shell) — anon is bounced
 * to /login before the review surface renders. Mirrors the run-detail /
 * comment report gating (auth.loggedIn && not the author).
 *
 * The review is authored by USER_B (alex) on USER_A's public route via
 * service-role so the gating is exercised without a UI submit / rate
 * limit. RUNNER_PUBLIC_ROUTE_ID is public, so any signed-in user can
 * review it.
 */

async function seedBReview() {
	await getAdminClient()
		.from('route_reviews')
		.upsert(
			{
				route_id: RUNNER_PUBLIC_ROUTE_ID,
				user_id: USER_B.id,
				rating: 2,
				comment: 'e2e report-target review'
			},
			{ onConflict: 'route_id,user_id' }
		);
}

async function deleteBReview() {
	await getAdminClient()
		.from('route_reviews')
		.delete()
		.eq('route_id', RUNNER_PUBLIC_ROUTE_ID)
		.eq('user_id', USER_B.id);
}

test.beforeEach(async () => {
	await seedBReview();
});

test.afterEach(async () => {
	await deleteBReview();
});

const reviewCard = '.review-card:has-text("e2e report-target review")';

test.describe('a non-author signed-in viewer', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('sees the flag on someone else’s review and can open the report dialog', async ({
		page
	}) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		const flag = page.locator(`${reviewCard} .review-report-btn`);
		await expect(flag).toBeVisible({ timeout: 10_000 });

		await flag.click();

		// The report dialog opens with its reason picker.
		await expect(page.getByRole('group', { name: 'Reason' })).toBeVisible();
	});
});

test.describe('the review author', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('does not see a flag on their own review', async ({ page }) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		await expect(page.locator(reviewCard)).toBeVisible({ timeout: 10_000 });
		await expect(page.locator(`${reviewCard} .review-report-btn`)).toHaveCount(0);
	});
});

test.describe('a signed-out viewer', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('is redirected to /login and never reaches a review card', async ({ page }) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		await page.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
		await expect(page.locator(reviewCard)).toHaveCount(0);
	});
});
