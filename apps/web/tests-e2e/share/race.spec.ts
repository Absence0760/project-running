import { expect, test } from '@playwright/test';

/**
 * `/share/race/[id]` — the public, anon, SSR race-listing share page.
 *
 * The data-present JSON-LD shape (SportsEvent + startDate + location) is
 * unit-tested in share_race_meta.test.ts. This e2e pins the route wiring +
 * head on the not-found path — deterministic without a seeded race — so a
 * crawler hitting a stale link still gets a valid head, never an app-shell
 * 404.
 */
test.describe('/share/race/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('unknown id renders the branded not-found page with a valid SEO head', async ({
		page,
	}) => {
		await page.goto('/share/race/00000000-0000-0000-0000-000000000000');

		await expect(page).toHaveTitle('Race — Threkir');
		await expect(page.getByRole('heading', { name: 'Race not found.' })).toBeVisible();

		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			/\/share\/race\/00000000-0000-0000-0000-000000000000$/
		);

		const ld = await page
			.locator('script[type="application/ld+json"]')
			.first()
			.textContent();
		const obj = JSON.parse(ld as string);
		expect(obj['@type']).toBe('SportsEvent');
		expect(obj.sport).toBe('Running');
	});
});
