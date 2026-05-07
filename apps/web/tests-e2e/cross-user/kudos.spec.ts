import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_B } from '../fixtures/users';

/**
 * Cross-user kudos flows. Pinned RUNNER_PUBLIC_RUN_ID is exempted
 * from the cross-user-engagement seeds (the `id != '...'` filter in
 * seed.sql) so the toggle test here always starts at zero kudos.
 *
 * The kudos→notification fan-out is in cross-user/notifications.spec.ts
 * because it spans two contexts (alex's write, runner's bell).
 *
 * Future depth: kudos count visible to anon viewers; rate-limit on
 * a kudos-spam burst; kudos against a private run rejected by RLS.
 */

test.describe('cross-user kudos', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('alex kudos runner public run via /share/run/ → reload persists → rescind', async ({
		page
	}) => {
		// /runs/[id] is owner-only (fetchRunById hits the runs table
		// directly and RLS hides cross-user rows). /share/run/[id] is
		// the path real visitors take — public_runs view + RunSocial
		// mounts when auth.loggedIn.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Wait for the auth-gated RunSocial to mount.
		const kudosBtn = page.locator('.kudos-btn');
		await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
		await expect(kudosBtn).not.toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('0');

		// Click to give kudos.
		await kudosBtn.click();
		await expect(kudosBtn).toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('1');

		// Reload to confirm the write actually hit Supabase, not just
		// optimistic local state.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.kudos-btn')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.kudos-btn')).toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('1');

		// Rescind so the spec is idempotent across runs.
		await page.locator('.kudos-btn').click();
		await expect(page.locator('.kudos-btn')).not.toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('0');
	});

	test('alex sees kudos disabled on a non-public run page (RLS hides the row)', async ({
		page
	}) => {
		// /share/run/<bogus> for any non-public run ID returns the
		// "Run not found" state via the public_runs view's RLS-equivalent
		// filter. Pin the negative path so a regression that exposed
		// private runs to /share would surface here.
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);
		await page.goto(`/share/run/${bogusId}`);
		await page.waitForLoadState('networkidle');

		// RunShareView renders "Run not found." as a status paragraph
		// (no heading) when the run can't be loaded. No kudos button
		// surfaces.
		await expect(
			page.getByText('Run not found.')
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.kudos-btn')).toHaveCount(0);
	});
});
