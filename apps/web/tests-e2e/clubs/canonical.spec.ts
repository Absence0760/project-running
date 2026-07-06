import { expect, test } from '@playwright/test';

/**
 * SEO consolidation: the in-app club + club-event pages point their
 * canonical at the crawlable /share/{club,event}/* twins so search
 * engines don't split ranking signal across the two URLs. The canonical
 * derives from the URL param (not fetched data), so it's present even
 * before/without the client data load. Anon-viewable surfaces (public
 * clubs + their events are RLS-visible to anon), so no auth needed.
 *
 * Seed fixtures (apps/backend/supabase/seed.sql): the public
 * 'richmond-run-club' + its public 'Sunday Long Run' event.
 */
test.describe('in-app canonical → /share twins (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('/clubs/[slug] canonicals to /share/club/[slug] + titles with the club name', async ({
		page,
	}) => {
		await page.goto('/clubs/richmond-run-club');
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			/\/share\/club\/richmond-run-club$/
		);
		// Title fills in with the club name once the CSR data load resolves
		// (toHaveTitle auto-retries); before the code shipped it stayed the
		// generic "Threkir" app-shell title.
		await expect(page).toHaveTitle('Richmond Run Club — Threkir');
	});

	test('/clubs/[slug]/events/[id] canonicals to /share/event/[id] + titles with the event name', async ({
		page,
	}) => {
		const EVENT = 'e1111111-0000-0000-0000-000000000001';
		await page.goto(`/clubs/richmond-run-club/events/${EVENT}`);
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			new RegExp(`/share/event/${EVENT}$`)
		);
		await expect(page).toHaveTitle('Sunday Long Run — Threkir');
	});
});
