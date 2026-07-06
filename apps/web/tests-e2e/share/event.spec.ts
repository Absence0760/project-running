import { expect, test } from '@playwright/test';

/**
 * `/share/event/[id]` — the public, anon, SSR event share page.
 *
 * The rich data-present JSON-LD shape (SportsEvent vs Event, start/end,
 * organizer, coarse location) is unit-tested in share_event_meta.test.ts.
 * This e2e pins the route wiring + head on the not-found path — which is
 * deterministic without a seeded event — so a refactor can't silently
 * drop the canonical / structured data (a crawler that hits a stale link
 * must still get a valid, non-broken head, never an app-shell 404).
 */
test.describe('/share/event/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('unknown id renders the branded not-found page with a valid SEO head', async ({
		page,
	}) => {
		await page.goto('/share/event/00000000-0000-0000-0000-000000000000');

		await expect(page).toHaveTitle('Event — Threkir');
		await expect(page.getByRole('heading', { name: 'Event not found.' })).toBeVisible();

		// Canonical + og:url point at this share URL even on the fallback.
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			/\/share\/event\/00000000-0000-0000-0000-000000000000$/
		);

		// A valid generic Event JSON-LD node is still emitted.
		const ld = await page
			.locator('script[type="application/ld+json"]')
			.first()
			.textContent();
		const obj = JSON.parse(ld as string);
		expect(['Event', 'SportsEvent']).toContain(obj['@type']);
		expect(obj.url).toMatch(/\/share\/event\/00000000-0000-0000-0000-000000000000$/);
	});
});
