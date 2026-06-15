import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Cross-surface back navigation: pages launched from a club's tabs (route
 * builder, etc.) must return to the CLUB on Back, not their generic parent
 * list. The shared smartBack helper pops the history entry the club link
 * pushed; a hard load falls through to the static parent.
 *
 * USER_A owns Richmond Run Club (admin), so the admin-only "New route" action
 * on the Routes tab is visible.
 */

test.describe('club sub-page back navigation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('club Routes tab → New route → Back returns to the club', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club?tab=routes');
		await page.getByRole('link', { name: 'New route' }).click();
		await expect(page).toHaveURL(/\/routes\/new\?club=/, { timeout: 10_000 });

		await page.getByRole('link', { name: 'My routes' }).click();
		await expect(page).toHaveURL(/\/clubs\/richmond-run-club/, { timeout: 10_000 });
	});

	test('deep-linking the route builder → Back falls through to /routes', async ({ page }) => {
		// No in-app referrer to pop, so the back link uses its static parent.
		await page.goto('/routes/new');
		await page.getByRole('link', { name: 'My routes' }).click();
		await expect(page).toHaveURL(/\/routes$/, { timeout: 10_000 });
	});
});
