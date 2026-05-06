import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/integrations — Strava / parkrun / Garmin Connect rows
 * with connect / sync / disconnect affordances. Strava is OAuth-
 * gated, parkrun is a one-button athlete-number scrape, Garmin is
 * bulk-import only.
 *
 * Future depth: Strava connect button click → mock OAuth flow,
 * parkrun import button against the seeded athlete number, Garmin
 * .fit / .zip upload + per-file progress.
 */

test.describe('/settings/integrations', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('integration list renders Strava + parkrun + Garmin rows', async ({
		page
	}) => {
		// The integrations page lists three providers regardless of
		// connection state. Runner's seed has parkrun + strava
		// connected (last_sync_at populated); garmin is unconnected.
		// All three rows must appear — the list is built from a
		// hardcoded array, but the connection state comes from a
		// query, so a regression there could break the page render.
		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'Strava', exact: true })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'parkrun', exact: true })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'Garmin Connect', exact: true })
		).toBeVisible();
	});
});
