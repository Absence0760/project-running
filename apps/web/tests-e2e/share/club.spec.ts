import { expect, test } from '@playwright/test';

/**
 * `/share/club/[slug]` — the public, anon, SSR club share page.
 *
 * The data-present JSON-LD shape (SportsOrganization + sport + logo +
 * areaServed) is unit-tested in share_club_meta.test.ts. This e2e pins the
 * route wiring + head on the not-found path — deterministic without a
 * seeded club — so a crawler hitting a stale/private link still gets a
 * valid head, never an app-shell 404.
 */
test.describe('/share/club/[slug] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	// Seed fixture (apps/backend/supabase/seed.sql): the public
	// 'Richmond Run Club'. Data-present test — proves anon can actually
	// READ a public club by slug through RLS + column grants.
	test('a public club renders its data + SportsOrganization JSON-LD', async ({ page }) => {
		await page.goto('/share/club/richmond-run-club');

		await expect(page).toHaveTitle('Richmond Run Club — Threkir');
		await expect(page.getByRole('heading', { name: 'Richmond Run Club' })).toBeVisible();

		const ld = JSON.parse(
			(await page.locator('script[type="application/ld+json"]').first().textContent()) as string
		);
		expect(ld['@type']).toBe('SportsOrganization');
		expect(ld.name).toBe('Richmond Run Club');
		expect(ld.sport).toBe('Running');
	});

	test('unknown slug renders the branded not-found page with a valid SEO head', async ({
		page,
	}) => {
		await page.goto('/share/club/no-such-club-xyz');

		await expect(page).toHaveTitle('Club — Threkir');
		await expect(page.getByRole('heading', { name: 'Club not found.' })).toBeVisible();

		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			/\/share\/club\/no-such-club-xyz$/
		);

		const ld = await page
			.locator('script[type="application/ld+json"]')
			.first()
			.textContent();
		const obj = JSON.parse(ld as string);
		expect(obj['@type']).toBe('SportsOrganization');
		expect(obj.sport).toBe('Running');
	});
});
