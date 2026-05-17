import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /feed and /u/[me]?tab=feed — legacy URLs that now redirect to the
 * Feed tab under /social. The surface itself is covered by
 * tests-e2e/social/feed.spec.ts; this file pins the redirects so old
 * bookmarks, sitemap entries, bell-popover CTAs, and mobile push deep
 * links keep resolving.
 */

test.describe('/feed → /social?tab=feed', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/feed redirects to /social?tab=feed', async ({ page }) => {
		await page.goto('/feed');
		await expect(page).toHaveURL(/\/social\?tab=feed/, { timeout: 10_000 });
	});

	test('/u/[me]?tab=feed (legacy) also redirects to /social?tab=feed', async ({ page }) => {
		await page.goto(`/u/${USER_A.id}?tab=feed`);
		await expect(page).toHaveURL(/\/social\?tab=feed/, { timeout: 10_000 });
	});
});
