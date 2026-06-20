import { expect, test } from '@playwright/test';

/**
 * Click-through pin: an article's feature CTA navigates to its app route.
 * Anon → the layout auth guard redirects to /login?return_to=..., which
 * is the intended acquisition funnel (not a hard 404).
 */

test.describe('/learn CTA links resolve into the app', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('the feature CTA lands on /login (auth funnel), not a 404', async ({ page }) => {
		await page.goto('/learn/road-running-101');

		await page.getByRole('link', { name: 'Build a training plan' }).click();

		// Anon clicking an app-route CTA is bounced through the auth guard.
		await expect(page).toHaveURL(/\/login/);
		await expect(page.getByText(/404|not found/i)).toHaveCount(0);
	});
});
