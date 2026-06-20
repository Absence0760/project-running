import { expect, test } from '@playwright/test';

/**
 * `/learn` — the anonymous, prerendered Learn hub.
 *
 * Reachable without auth (shell-less + anon-allowed in +layout.svelte).
 * Lists guide cards grouped by category; each card links to a guide
 * article that resolves (no 404).
 */

test.describe('/learn (hub)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees the hub heading + at least one guide card', async ({ page }) => {
		await page.goto('/learn');

		await expect(page.getByRole('heading', { name: 'Learn to run', level: 1 })).toBeVisible();

		const firstCard = page.locator('a.guide-card').first();
		await expect(firstCard).toBeVisible();
	});

	test('a guide card links to a guide article that resolves', async ({ page }) => {
		await page.goto('/learn');

		const firstCard = page.locator('a.guide-card').first();
		const href = await firstCard.getAttribute('href');
		expect(href).toMatch(/^\/learn\/[a-z0-9-]+$/);

		await firstCard.click();
		await expect(page).toHaveURL(/\/learn\/[a-z0-9-]+$/);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
	});
});
