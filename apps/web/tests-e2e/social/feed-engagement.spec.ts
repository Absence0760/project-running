import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertComment, insertKudos, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /social?tab=feed — in-feed engagement (the SocialFeed `.kudos-pill`
 * + comment-count footer). The cross-user specs pin the `.kudos-btn`
 * on /share/run + the RunSocial composer; this pins the SEPARATE feed
 * surface, which has its own optimistic toggle (`toggleKudos` in
 * SocialFeed.svelte) reading engagement via `fetchEngagementSummaries`
 * (the GROUP-BY `run_engagement_counts` RPC), not `fetchKudosForRun`.
 *
 * A regression in the feed's optimistic path or the engagement-summary
 * RPC wiring (e.g. a count off-by-one, a viewer_has_kudos that doesn't
 * survive reload, a comment-count that reads zero) surfaces here and
 * nowhere else.
 */

test.describe('/social?tab=feed — kudos pill + comment count', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let runId: string | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		// USER_B (alex) follows USER_A (runner) so runner's public run
		// lands in alex's feed.
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
	});

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort; kudos/comments cascade on run delete */
			}
			runId = null;
		}
	});

	test('feed kudos pill toggles, count increments/decrements, and the give survives reload', async ({
		page
	}) => {
		// Plant a fresh public run with a unique title so the card is
		// addressable in a feed that may carry other entries.
		const title = `E2E feed-kudos ${Date.now()}`;
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run', title }
		});

		await page.goto('/social?tab=feed');
		const card = page.locator('article.entry').filter({ hasText: title });
		await expect(card).toBeVisible({ timeout: 10_000 });

		const pill = card.locator('.kudos-pill');
		await expect(pill).not.toHaveClass(/given/);
		// Run starts at zero kudos (planted fresh, no engagement seed).
		await expect(pill).toContainText('0');

		// Give kudos → optimistic flip to given + count 1.
		await pill.click();
		await expect(pill).toHaveClass(/given/, { timeout: 5_000 });
		await expect(pill).toContainText('1');

		// The optimistic flip must reflect a real DB write — poll the
		// run_kudos row, then reload and assert the given state + count
		// survive (proves it wasn't a paint-only flip).
		const admin = getAdminClient();
		await expect(async () => {
			const { count } = await admin
				.from('run_kudos')
				.select('*', { count: 'exact', head: true })
				.eq('run_id', runId!)
				.eq('user_id', USER_B.id);
			expect(count).toBe(1);
		}).toPass({ timeout: 5_000 });

		await page.reload();
		const cardAfter = page.locator('article.entry').filter({ hasText: title });
		await expect(cardAfter.locator('.kudos-pill')).toHaveClass(/given/, {
			timeout: 10_000
		});
		await expect(cardAfter.locator('.kudos-pill')).toContainText('1');

		// Rescind → flips back + count 0 + the row is gone server-side.
		await cardAfter.locator('.kudos-pill').click();
		await expect(cardAfter.locator('.kudos-pill')).not.toHaveClass(/given/, {
			timeout: 5_000
		});
		await expect(cardAfter.locator('.kudos-pill')).toContainText('0');
		await expect(async () => {
			const { count } = await admin
				.from('run_kudos')
				.select('*', { count: 'exact', head: true })
				.eq('run_id', runId!)
				.eq('user_id', USER_B.id);
			expect(count).toBe(0);
		}).toPass({ timeout: 5_000 });
	});

	test('feed card reflects a pre-existing kudos count from another user + the viewer has not kudosed', async ({
		page
	}) => {
		// A run kudosed by a third party (morgan) but NOT the viewer
		// (alex) must show count 1 with the pill in the NOT-given state.
		// This pins the engagement-summary read: kudos_count comes from
		// the GROUP-BY RPC (all users), viewer_has_kudos from the narrow
		// per-viewer lookup — a regression conflating the two would show
		// the pill as given here.
		const title = `E2E feed-foreign-kudos ${Date.now()}`;
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 12 * 60 * 1000).toISOString(),
			distance_m: 6_000,
			duration_s: 1_800,
			is_public: true,
			metadata: { activity_type: 'run', title }
		});
		await insertKudos(runId, USER_C_PRO.id);

		await page.goto('/social?tab=feed');
		const card = page.locator('article.entry').filter({ hasText: title });
		await expect(card).toBeVisible({ timeout: 10_000 });
		const pill = card.locator('.kudos-pill');
		await expect(pill).toContainText('1');
		await expect(pill).not.toHaveClass(/given/);
	});

	test('feed comment-pill shows the comment count for a run with comments', async ({
		page
	}) => {
		// The feed footer's comment-pill renders eng.comment_count from
		// the same engagement summary. Plant two comments + assert the
		// pill reads 2. A regression that dropped comment_count from the
		// RPC projection would read 0 here.
		const title = `E2E feed-comments ${Date.now()}`;
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 14 * 60 * 1000).toISOString(),
			distance_m: 7_000,
			duration_s: 2_100,
			is_public: true,
			metadata: { activity_type: 'run', title }
		});
		await insertComment({ run_id: runId, author_id: USER_C_PRO.id, body: 'first' });
		await insertComment({ run_id: runId, author_id: USER_A.id, body: 'second' });

		await page.goto('/social?tab=feed');
		const card = page.locator('article.entry').filter({ hasText: title });
		await expect(card).toBeVisible({ timeout: 10_000 });
		// The comment-pill links to /runs/<id> and shows the count.
		const commentPill = card.locator('.comment-pill');
		await expect(commentPill).toContainText('2', { timeout: 10_000 });
		await expect(commentPill).toHaveAttribute('href', new RegExp(`/runs/${runId}`));
	});
});

/**
 * Feed load-failure path. `fetchFollowingActivityFeed` resolves the
 * followee set then reads `public_runs` + `gym_workouts`. The
 * component's `load()` wraps the call in a try/catch that surfaces an
 * error TOAST (socialFeed.loadFeedError) — distinct from the empty
 * state. A regression that swallowed the failure (no toast, blank
 * feed) would be indistinguishable from "nobody you follow ran" and
 * is exactly the silent-failure anti-pattern the project forbids.
 */
test.describe('/social?tab=feed — load failure surfaces an error toast', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
	});

	test('a failed public_runs read shows the load-failed toast, not a silent blank feed', async ({
		page
	}) => {
		// Fail the feed's run read (public_runs) so fetchFollowingFeed
		// throws inside load(). Intercept must register before navigation.
		await page.route('**/rest/v1/public_runs*', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated feed failure' })
			});
		});

		await page.goto('/social?tab=feed');

		// The error toast (role="alert") carries the loadFeedError copy.
		await expect(
			page.locator('.toast-error', { hasText: /Could not load feed/ })
		).toBeVisible({ timeout: 10_000 });
	});
});

/**
 * Empty-state branching. SocialFeed renders three distinct empties:
 *   - follows-nobody → "Your feed is empty" + a Find people CTA.
 *   - filtered-to-nothing → "No matches" + Clear filters (covered in
 *     feed.spec.ts; the clearFilters action is pinned here).
 * USER_C_PRO (morgan) is seeded following nobody, so she hits the
 * first branch deterministically.
 */
test.describe('/social?tab=feed — empty states', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.beforeEach(async () => {
		// Guarantee morgan follows nobody — other specs may plant edges.
		const admin = getAdminClient();
		await admin.from('user_follows').delete().eq('follower_id', USER_C_PRO.id);
	});

	test('viewer following nobody sees the "Your feed is empty" card + Find people CTA', async ({
		page
	}) => {
		await page.goto('/social?tab=feed');
		await expect(
			page.getByRole('heading', { name: 'Your feed is empty' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('link', { name: /Find people/ })
		).toHaveAttribute('href', '/social?tab=people');
	});
});

/**
 * The "No matches" filter empty + its Clear-filters recovery. feed.spec
 * pins the Cycle→empty transition; this pins the recovery action: from
 * the no-match empty, "Clear filters" resets activityFilter to 'all'
 * and the planted run reappears.
 */
test.describe('/social?tab=feed — clear-filters recovery', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let runId: string | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 8 * 60 * 1000).toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run' }
		});
	});

	test.afterEach(async () => {
		if (runId) {
			await deleteRun(runId).catch(() => {});
			runId = null;
		}
	});

	test('Cycle filter → no matches → Clear filters restores the Run feed', async ({
		page
	}) => {
		await page.goto('/social?tab=feed');
		await expect(page.locator('article.entry').first()).toBeVisible({
			timeout: 10_000
		});
		await page.getByRole('button', { name: 'Cycle' }).click();
		await expect(
			page.getByRole('heading', { name: 'No matches' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Clear filters' }).click();
		// Back on 'all' the planted run card returns.
		await expect(page.locator('article.entry').first()).toBeVisible({
			timeout: 10_000
		});
		// The All chip is the active one again.
		await expect(page.getByRole('button', { name: 'All' })).toHaveAttribute(
			'aria-pressed',
			'true'
		);
	});
});
