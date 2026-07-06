import { expect, test } from '@playwright/test';

/**
 * `/share/profile/[id]` — the public, anon, SSR profile share page.
 *
 * The data-present JSON-LD shape (ProfilePage + Person + avatar image) is
 * unit-tested in share_profile_meta.test.ts. This e2e pins the route wiring
 * + head on the not-found path — deterministic without a seeded profile —
 * so a crawler hitting a stale link still gets a valid head, never an
 * app-shell 404.
 */
test.describe('/share/profile/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('unknown id renders the branded not-found page with a valid SEO head', async ({
		page,
	}) => {
		await page.goto('/share/profile/00000000-0000-0000-0000-000000000000');

		await expect(page).toHaveTitle('Runner — Threkir');
		await expect(page.getByRole('heading', { name: 'Runner not found.' })).toBeVisible();

		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			/\/share\/profile\/00000000-0000-0000-0000-000000000000$/
		);

		const ld = await page
			.locator('script[type="application/ld+json"]')
			.first()
			.textContent();
		const obj = JSON.parse(ld as string);
		expect(obj['@type']).toBe('ProfilePage');
		expect(obj.mainEntity['@type']).toBe('Person');
	});
});
