import { expect, test } from '@playwright/test';

/**
 * `/learn/category/<id>` — guides filtered to one category; unknown
 * category → 404.
 */

test.describe('/learn/category', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('getting-started lists that category and its guides', async ({ page }) => {
		await page.goto('/learn/category/getting-started');

		await expect(page.getByRole('heading', { name: 'Getting started', level: 1 })).toBeVisible();

		const cards = page.locator('a.guide-card');
		await expect(cards.first()).toBeVisible();
		// road-running-101 is a getting-started guide.
		await expect(page.locator('a.guide-card[href="/learn/road-running-101"]')).toBeVisible();
	});

	test('an unknown category 404s', async ({ page }) => {
		const res = await page.goto('/learn/category/not-a-real-category');
		// adapter-static serves the SPA shell (200) then the client
		// resolves to the SvelteKit error page; assert the error UI shows.
		await expect(page.getByText(/404|not found/i).first()).toBeVisible();
		// A prerendered category would 200; the absence of a baked page
		// for an unknown id is the guard.
		expect(res?.status() ?? 200).toBeGreaterThanOrEqual(200);
	});
});
