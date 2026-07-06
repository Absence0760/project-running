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

	// Seed fixture (apps/backend/supabase/seed.sql): a public 'Sunday Long
	// Run' event under the public 'Richmond Run Club'. Data-present test —
	// proves anon can actually READ a public event through RLS + the club
	// embed (the check that would have caught the race-listings anon-policy
	// bug, where a wrong table read silently returned nothing).
	const SEED_EVENT = 'e1111111-0000-0000-0000-000000000001';

	test('a public event renders its data + SportsEvent JSON-LD', async ({ page }) => {
		await page.goto(`/share/event/${SEED_EVENT}`);

		await expect(page).toHaveTitle('Sunday Long Run — Threkir');
		await expect(page.getByRole('heading', { name: 'Sunday Long Run' })).toBeVisible();
		expect(
			await page.locator('meta[property="og:title"]').getAttribute('content')
		).toContain('Sunday Long Run');

		const ld = JSON.parse(
			(await page.locator('script[type="application/ld+json"]').first().textContent()) as string
		);
		expect(ld['@type']).toBe('SportsEvent');
		expect(ld.name).toBe('Sunday Long Run');
		// startDate is the row's starts_at verbatim; Postgres/PostgREST
		// renders the +00:00 offset form, which is valid ISO 8601 for
		// schema.org (equivalent to the Z form).
		expect(ld.startDate).toMatch(/^2026-04-19T06:30:00(Z|\+00:00)$/);
		// The host club is the organizer; only the coarse club location is
		// present — never the precise meet point.
		expect(ld.organizer?.name).toBe('Richmond Run Club');
		expect(JSON.stringify(ld)).not.toContain('Paddington Gate');
	});

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
