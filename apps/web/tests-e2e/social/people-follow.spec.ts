import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /social?tab=people — follow toggle FAILURE path + the follow→feed
 * link. people.spec.ts covers the happy-path optimistic flip + DB
 * persistence; this pins two gaps:
 *   1. when the follow write FAILS, the optimistic flip ROLLS BACK and
 *      a failure toast surfaces (SocialPeople.toggleFollow catch).
 *   2. the follow graph actually drives the feed: a followed user's
 *      public run appears; after unfollow it disappears. This is the
 *      end-to-end contract people.spec + feed.spec each test one half
 *      of — joined here so a break in the resolveFollowedAuthorIds →
 *      feed seam is caught.
 */

test.describe('/social?tab=people — follow failure rolls back', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		// Start with runner NOT following alex so the button reads "Follow".
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_A.id)
			.eq('followee_id', USER_B.id);
	});

	test.afterEach(async () => {
		// Restore the seeded runner→alex edge.
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_A.id, followee_id: USER_B.id },
				{ onConflict: 'follower_id,followee_id' }
			);
	});

	test('a failed follow INSERT rolls the button back to Follow + shows a failure toast', async ({
		page
	}) => {
		// Fail every user_follows write (POST) — the follow insert. The
		// optimistic flip paints "Following" immediately, then the catch
		// must roll it back to "Follow" when the write 500s.
		await page.route('**/rest/v1/user_follows*', async (route) => {
			if (route.request().method() === 'POST') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated follow failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto('/social?tab=people');
		const search = page.getByPlaceholder('Search runners by name');
		await expect(search).toBeVisible({ timeout: 10_000 });
		await search.fill('Alex');
		const alexRow = page.locator('.person-row', { hasText: 'Alex Chen' });
		await expect(alexRow).toBeVisible({ timeout: 5_000 });
		const followBtn = alexRow.locator('.follow-btn');
		await expect(followBtn).toContainText('Follow');

		await followBtn.click();

		// Failure toast surfaces.
		await expect(
			page.locator('.toast-error', { hasText: /Could not update follow/ })
		).toBeVisible({ timeout: 10_000 });
		// And the button has rolled back to "Follow" (not stuck Following).
		await expect(followBtn).toContainText('Follow', { timeout: 5_000 });
		await expect(followBtn).not.toContainText('Following');

		// No row was written server-side.
		const admin = getAdminClient();
		const { data: edge } = await admin
			.from('user_follows')
			.select('follower_id')
			.eq('follower_id', USER_A.id)
			.eq('followee_id', USER_B.id)
			.maybeSingle();
		expect(edge).toBeNull();
	});
});

/**
 * The follow graph drives the feed. Plant a public run owned by alex,
 * have runner follow alex via the People UI, confirm the run surfaces
 * in runner's feed, then unfollow and confirm it vanishes. This is the
 * cross-surface invariant: the feed reads exactly the follow set the
 * People tab writes.
 */
test.describe('/social — follow graph drives feed contents', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;
	const title = `E2E follow-drives-feed ${Date.now()}`;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		// runner must NOT follow alex at the start so the run is absent.
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_A.id)
			.eq('followee_id', USER_B.id);
		runId = await insertRun({
			user_id: USER_B.id,
			started_at: new Date(Date.now() - 15 * 60 * 1000).toISOString(),
			distance_m: 8_000,
			duration_s: 2_400,
			is_public: true,
			metadata: { activity_type: 'run', title }
		});
	});

	test.afterEach(async () => {
		if (runId) {
			await deleteRun(runId).catch(() => {});
			runId = null;
		}
		// Restore the seeded runner→alex edge.
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_A.id, followee_id: USER_B.id },
				{ onConflict: 'follower_id,followee_id' }
			);
	});

	test("following Alex surfaces her run in the feed; unfollowing removes it", async ({
		page
	}) => {
		// 1. Feed before follow: alex's run is absent (runner follows nobody
		//    relevant). The empty / no-match branch is fine — we just assert
		//    the planted run is NOT present.
		await page.goto('/social?tab=feed');
		await expect(page.getByText(title)).toHaveCount(0, { timeout: 10_000 });

		// 2. Follow Alex via the People tab.
		await page.goto('/social?tab=people');
		const search = page.getByPlaceholder('Search runners by name');
		await expect(search).toBeVisible({ timeout: 10_000 });
		await search.fill('Alex');
		const alexRow = page.locator('.person-row', { hasText: 'Alex Chen' });
		await expect(alexRow).toBeVisible({ timeout: 5_000 });
		const followBtn = alexRow.locator('.follow-btn');
		await followBtn.click();
		await expect(followBtn).toContainText('Following', { timeout: 5_000 });

		// Wait for the edge to land before reading the feed.
		const admin = getAdminClient();
		await expect(async () => {
			const { data } = await admin
				.from('user_follows')
				.select('follower_id')
				.eq('follower_id', USER_A.id)
				.eq('followee_id', USER_B.id)
				.maybeSingle();
			expect(data).toBeTruthy();
		}).toPass({ timeout: 5_000 });

		// 3. Feed after follow: alex's run now surfaces.
		await page.goto('/social?tab=feed');
		await expect(
			page.locator('article.entry').filter({ hasText: title })
		).toBeVisible({ timeout: 10_000 });

		// 4. Unfollow via People → the edge is removed.
		await page.goto('/social?tab=people');
		await page.getByPlaceholder('Search runners by name').fill('Alex');
		const unfollowBtn = page
			.locator('.person-row', { hasText: 'Alex Chen' })
			.locator('.follow-btn');
		await expect(unfollowBtn).toContainText('Following', { timeout: 5_000 });
		await unfollowBtn.click();
		await expect(unfollowBtn).toContainText('Follow', { timeout: 5_000 });
		await expect(unfollowBtn).not.toContainText('Following');
		await expect(async () => {
			const { data } = await admin
				.from('user_follows')
				.select('follower_id')
				.eq('follower_id', USER_A.id)
				.eq('followee_id', USER_B.id)
				.maybeSingle();
			expect(data).toBeNull();
		}).toPass({ timeout: 5_000 });

		// 5. Feed after unfollow: the run is gone again.
		await page.goto('/social?tab=feed');
		await expect(page.getByText(title)).toHaveCount(0, { timeout: 10_000 });
	});
});
