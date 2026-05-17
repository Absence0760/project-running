import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /social?tab=feed — activity feed surface. The user-facing list of
 * recent public runs from people the viewer follows, 14-day window,
 * activity-segmented filter. The legacy /feed and /u/[me]?tab=feed
 * redirect tests live in tests-e2e/feed/redirect.spec.ts.
 */

test.describe('/social?tab=feed — feed surface', () => {
	test.use({ storageState: USER_B.storageStatePath });

	// Plant a fresh runner-authored public run inside the 14-day window
	// so the feed has at least one entry, regardless of how far the
	// clock has drifted past the seed's fixed run dates.
	let plantedRunId: string | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
		const { data: row, error } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
				duration_s: 1800,
				distance_m: 7000,
				source: 'app',
				is_public: true,
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();
		if (error) throw error;
		plantedRunId = (row as { id: string }).id;
	});

	test.afterEach(async () => {
		if (plantedRunId) {
			const admin = getAdminClient();
			await admin.from('runs').delete().eq('id', plantedRunId);
			plantedRunId = null;
		}
	});

	test('renders at least one feed entry from followed runner', async ({ page }) => {
		await page.goto('/social?tab=feed');
		await expect(page.getByText(/Jared/).first()).toBeVisible({
			timeout: 10_000
		});
	});

	test('activity-type filter narrows to a no-match empty state on Cycle', async ({
		page
	}) => {
		await page.goto('/social?tab=feed');
		// Wait for the initial feed to mount with at least one entry so
		// the activityFilter $effect has the `mounted` flag set true by
		// the time Cycle is clicked (otherwise the click can race the
		// initial load and the re-fetch never fires).
		await expect(page.locator('article').first()).toBeVisible({ timeout: 10_000 });
		await page.getByRole('button', { name: 'Cycle' }).click();
		await expect(
			page.getByRole('heading', { name: 'No matches' })
		).toBeVisible({ timeout: 10_000 });
	});
});
