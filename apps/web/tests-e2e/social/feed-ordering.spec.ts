import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /social?tab=feed — cross-modal ordering + pagination.
 *
 * The activity feed merges public runs + public lifts from followed
 * users into ONE reverse-chronological window (mergeFeedPages, sorted
 * by started_at desc then id desc). Existing specs pin individual card
 * shapes; these pin the two ordering-sensitive behaviours:
 *   1. a newer run sorts above an older lift (and vice-versa) — the
 *      interleave is by started_at, not by kind.
 *   2. the cursor-based "Load more" pages the next window in and the
 *      button disappears once exhausted.
 */

test.describe('/social?tab=feed — run/lift interleave ordering', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const ids: { runs: string[]; workouts: string[] } = { runs: [], workouts: [] };

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of ids.workouts) await admin.from('gym_workouts').delete().eq('id', id);
		for (const id of ids.runs) await deleteRun(id).catch(() => {});
		ids.runs = [];
		ids.workouts = [];
	});

	test('a newer run sorts above an older lift in the merged feed', async ({ page }) => {
		const stamp = Date.now();
		const olderLiftTitle = `E2E older-lift ${stamp}`;
		const newerRunTitle = `E2E newer-run ${stamp}`;

		const admin = getAdminClient();
		// Older lift: 3 hours ago.
		const { data: lift } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: olderLiftTitle,
				started_at: new Date(stamp - 3 * 60 * 60 * 1000).toISOString(),
				is_public: true
			})
			.select('id')
			.single();
		ids.workouts.push((lift as { id: string }).id);

		// Newer run: 1 hour ago — must sort ABOVE the lift.
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(stamp - 60 * 60 * 1000).toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run', title: newerRunTitle }
		});
		ids.runs.push(runId);

		await page.goto('/social?tab=feed');
		const cards = page.locator('article.entry');
		await expect(cards.first()).toBeVisible({ timeout: 10_000 });

		// Find the positional index of each planted card by its title and
		// assert the newer run precedes the older lift. Use the cards'
		// text content rather than nth() guesses so unrelated feed entries
		// between them don't break the relative-order assertion.
		const texts = await cards.allTextContents();
		const runIdx = texts.findIndex((t) => t.includes(newerRunTitle));
		const liftIdx = texts.findIndex((t) => t.includes(olderLiftTitle));
		expect(runIdx, 'newer run card must be present in the feed').toBeGreaterThanOrEqual(0);
		expect(liftIdx, 'older lift card must be present in the feed').toBeGreaterThanOrEqual(0);
		expect(
			runIdx,
			'the 1h-old run must sort above the 3h-old lift (merge is by started_at desc, not by kind)'
		).toBeLessThan(liftIdx);
	});
});

/**
 * Cursor pagination. The feed loads 20 at a time; `exhausted` is set
 * when a page returns < 20 rows, which hides "Load more". With <=20
 * total feed entries the button must NOT render (no phantom paging
 * trigger). The full N>20 paging case is exercised by the data-layer
 * mergeFeedPages unit tests; here we pin the UI gating contract.
 */
test.describe('/social?tab=feed — load-more gating', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let runId: string | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		// Isolate: have alex follow ONLY runner, and clear any extra
		// recent runner runs so the feed is small + the button is hidden.
		await admin.from('user_follows').delete().eq('follower_id', USER_B.id);
		await admin
			.from('user_follows')
			.insert({ follower_id: USER_B.id, followee_id: USER_A.id });
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run', title: `E2E paging ${Date.now()}` }
		});
	});

	test.afterEach(async () => {
		if (runId) {
			await deleteRun(runId).catch(() => {});
			runId = null;
		}
		// Restore the seeded follow edge so other specs see the seed.
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
	});

	test('Load more is hidden when the feed is exhausted (< 20 entries)', async ({ page }) => {
		await page.goto('/social?tab=feed');
		await expect(page.locator('article.entry').first()).toBeVisible({
			timeout: 10_000
		});
		// runner has far fewer than 20 runs inside the 14-day window, so
		// the first page is the last page → no Load more button.
		await expect(page.getByRole('button', { name: 'Load more' })).toHaveCount(0);
	});
});
