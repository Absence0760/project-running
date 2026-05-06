import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/licenses — third-party-license attribution page. A static
 * list rendered from a hardcoded `deps` array in LicenseList.svelte;
 * this page is the project's notice of attribution for its OSS deps.
 *
 * The test pins entries that must always render — if someone refactors
 * the dep list and accidentally drops a row, the regression surfaces
 * here rather than on the live site. Keep the assertions to deps that
 * are unlikely to be removed (the framework + the data layer).
 */

test.describe('/settings/licenses', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('open-source license list mounts with framework + data-layer rows', async ({
		page
	}) => {
		await page.goto('/settings/licenses');

		// Page header — h1 is unique on the page.
		await expect(
			page.getByRole('heading', { level: 1, name: /Open-source licenses/ })
		).toBeVisible({ timeout: 10_000 });

		// Pin deps that the app cannot run without — if any of these
		// disappear, something has gone very wrong upstream.
		await expect(page.getByRole('link', { name: 'SvelteKit' })).toBeVisible();
		await expect(page.getByRole('link', { name: 'Svelte', exact: true }))
			.toBeVisible();
		await expect(page.getByRole('link', { name: '@supabase/supabase-js' }))
			.toBeVisible();

		// "Map data" section (MapTiler attribution) — only renders if
		// the second .card mounted past the deps list.
		await expect(
			page.getByRole('heading', { level: 2, name: 'Map data' })
		).toBeVisible();
	});
});
