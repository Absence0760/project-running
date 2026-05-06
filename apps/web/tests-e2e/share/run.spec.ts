import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';

/**
 * /share/run/[id] — public run share page (anon + authed paths).
 *
 * The non-owner kudos / comment writes go through this page's
 * RunSocial mount; those tests live under cross-user/ since they
 * need a second context. This file holds the anon read path —
 * authed-non-owner is structurally similar but currently gets
 * coverage incidentally via cross-user tests.
 *
 * Future depth: privacy-zone clipping rendering, photo gallery
 * mount, "view full run" gating for non-owners.
 */

test.describe('/share/run/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('public run loads without auth', async ({ page }) => {
		// Stub the clip-public-track Edge Function — we don't run
		// `supabase functions serve` alongside tests, and RunShareView
		// calls this for non-owner viewers (decisions §33). Without
		// the stub the await hangs and `loading` never flips off.
		// Returning [] here is the same shape the EF returns for a
		// run with no track in Storage (the seed shape).
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// share-page chrome + the run-meta block. The seeded run has no
		// track in Storage so we don't assert on the map. The chrome
		// + run-meta combo confirms anon read of the runs row succeeded
		// via the public_runs view (no auth, no 404).
		await expect(page.getByRole('link', { name: 'Run Onward' })).toBeVisible();
		await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });
	});
});
