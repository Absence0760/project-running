import { expect, test } from '@playwright/test';

import { USER_C_PRO } from '../fixtures/users';

/**
 * /coach — a failed `is_pro()` lookup must not present itself as a free
 * account.
 *
 * The RPC's `error` was never read, so `data: null` on any transient failure
 * fell into the free branch: the header badged a paying subscriber "Free",
 * `dailyLimit` dropped to the free cap, and because `usedToday` had already
 * loaded from `get_coach_usage`, `limitReached` fired and replaced the whole
 * composer with a "you've used your messages today — upgrade" bar. A Pro
 * runner was locked out of the feature they pay for and upsold their own
 * subscription, over a blip.
 *
 * The tier is now left unresolved when the lookup fails. Nothing is granted
 * client-side: /api/coach re-checks the tier server-side and answers 429 with
 * the authoritative tier + limit, which is what re-arms the limit bar.
 */

test.describe('/coach — tier lookup failure', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test('a Pro runner keeps the composer and is never badged Free', async ({ page }) => {
		await page.route('**/rest/v1/rpc/is_pro*', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated tier lookup failure' })
			});
		});
		// Any non-zero usage is enough to trip the free cap of 2.
		await page.route('**/rest/v1/rpc/get_coach_usage*', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify(9)
			});
		});

		await page.goto('/coach');

		// The composer must still be there — this is the lockout.
		await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({ timeout: 15_000 });
		// ...and the upgrade prompt must not have taken its place.
		await expect(page.getByText(/messages? today/i)).toHaveCount(0);

		// No tier is asserted either way, and no message allowance is quoted
		// off the seeded free cap.
		await expect(page.getByText('Free', { exact: true })).toHaveCount(0);
		await expect(page.getByText(/of 2 messages remaining today/)).toHaveCount(0);
		await expect(page.getByText(/Couldn’t check your plan/)).toBeVisible();
	});

	test('a healthy tier lookup still resolves Pro', async ({ page }) => {
		await page.goto('/coach');
		await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({ timeout: 15_000 });
		await expect(page.getByText('Pro', { exact: true })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText(/messages remaining today/)).toBeVisible();
	});
});
