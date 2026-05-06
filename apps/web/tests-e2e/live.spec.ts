import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from './fixtures/seeded-data';

/**
 * /live/[id] — anon spectator page for a public run that's broadcasting.
 *
 * This is one of the few pages that's intentionally public (the
 * layout's auth guard's `isPublic` includes /live/). Web has no
 * "start a broadcast" UI by design ([decisions § 24](docs/decisions.md))
 * — broadcasting is a mobile/watch capability. Tests here cover the
 * spectator side only; the recorder side will be exercised via a
 * service-role simulator in cross-user/sagas/.
 */

test.describe('/live/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visit to a public run live page mounts with status badge', async ({
		page
	}) => {
		// Without active broadcast pings the badge stays "Connecting..."
		// then transitions to "Demo" after the in-page timer fires.
		// We just assert the shell mounts — the brand label, badge
		// container, and stat tiles all exist regardless of connection
		// state.
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		await expect(page.locator('.live-logo')).toContainText('Run Onward');
		await expect(page.locator('.live-badge')).toBeVisible();
		// Three stat tiles: Distance / Elapsed / Pace.
		await expect(page.locator('.live-stat-label')).toHaveCount(3);
	});
});
