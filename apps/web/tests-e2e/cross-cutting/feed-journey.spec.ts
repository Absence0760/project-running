import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Feed journey — alex (USER_B) starts following only runner (USER_A,
 * per seed); the feed shows runner's recent public runs. Walk:
 *   1. /feed has entries from runner (initial seed state).
 *   2. /u/<runner-id> Following → click → unfollow.
 *   3. /feed shows the "Your feed is empty" state (alex now follows
 *      nobody — `followsAnyone` flips false).
 *   4. /u/<runner-id> Follow → click → re-follow.
 *   5. /feed has entries again.
 *
 * Pins the user_follows ↔ /feed render contract end-to-end. The
 * batch-2 cross-user/follows.spec.ts pins the toggle + counter;
 * this test pins the downstream feed visibility.
 *
 * The seed has runner ↔ alex bidirectional, so unfollowing here
 * leaves alex with zero follows. AfterAll guarantees the follow
 * state is restored (the test itself re-follows; afterEach is a
 * defensive backstop).
 */

test.describe('feed journey', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let plantedRunId: string | null = null;

	test.beforeEach(async () => {
		// Two seed dependencies that drift in this test:
		// 1. The follow edge alex→runner can be left toggled-off by a
		//    prior run that bailed mid-walk.
		// 2. The /feed window is the last 14 days, but seed runs are
		//    pinned to fixed dates that fall out of the window as the
		//    clock advances. Plant a runner-authored public run in the
		//    last hour so the window query always returns at least one
		//    entry for the "initial: feed has entries" step.
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

	test('alex unfollows runner → /feed empty → re-follow → /feed has entries again', async ({
		page
	}) => {
		// ── Initial: alex's feed has runner's runs ─────────────────
		await test.step('feed has at least one runner-authored entry', async () => {
			await page.goto('/feed');
			// Author chip on a feed card surfaces the display name. seed
			// runner's display_name is "Jared Howard" — match against
			// "Jared" prefix to stay tight to the seed.
			await expect(page.getByText(/Jared/).first()).toBeVisible({
				timeout: 10_000
			});
			// Empty-state heading must NOT be present.
			await expect(
				page.getByRole('heading', { name: 'Your feed is empty' })
			).toHaveCount(0);
		});

		// ── Unfollow runner ────────────────────────────────────────
		await test.step('unfollow runner via /u/<runner-id>', async () => {
			await page.goto(`/u/${USER_A.id}`);
			const followBtn = page.locator('.btn-follow');
			await expect(followBtn).toBeVisible({ timeout: 10_000 });
			// Pre-click: button reads "Following" (alex follows runner).
			await expect(followBtn).toContainText('Following');
			// Capture runner's follower count and wait for it to
			// decrement after the click — that's a stronger signal
			// the unfollowUser DB write committed than the local
			// button-text flip (which is set after the await but
			// before the followee's profile re-fetches).
			const followerCount = page
				.locator('button.count', { hasText: 'Followers' })
				.locator('.count-num');
			const before = parseInt((await followerCount.textContent()) ?? '0', 10);
			await followBtn.click();
			await expect(followBtn).toContainText('Follow');
			await expect(followerCount).toHaveText(String(Math.max(before - 1, 0)));
		});

		// ── Feed empty ─────────────────────────────────────────────
		await test.step('/feed shows the followsAnyone=false empty state', async () => {
			await page.goto('/feed');
			await expect(
				page.getByRole('heading', { name: 'Your feed is empty' })
			).toBeVisible({ timeout: 10_000 });
		});

		// ── Re-follow runner ───────────────────────────────────────
		await test.step('re-follow runner via /u/<runner-id>', async () => {
			await page.goto(`/u/${USER_A.id}`);
			const followBtn = page.locator('.btn-follow');
			await expect(followBtn).toBeVisible({ timeout: 10_000 });
			await expect(followBtn).toContainText('Follow');
			await followBtn.click();
			await expect(followBtn).toContainText('Following');
		});

		// ── Feed has entries again ────────────────────────────────
		await test.step('/feed has runner-authored entries again', async () => {
			await page.goto('/feed');
			await expect(page.getByText(/Jared/).first()).toBeVisible({
				timeout: 10_000
			});
			await expect(
				page.getByRole('heading', { name: 'Your feed is empty' })
			).toHaveCount(0);
		});
	});
});

/**
 * Feed map-thumbnail regression (persona-hunt R5, very-social Critical).
 *
 * `public_runs` dropped `track_url` (20260924_001), but SocialFeed still
 * gated the map preview on `entry.track_url`, so it was permanently
 * undefined and NO feed card ever rendered a map. 20261105_001 re-added a
 * boolean `has_track`; the feed now gates on that and the non-owner clip
 * path fetches by runId. Plant a followee public run carrying a track_url
 * (→ has_track=true) and assert the card renders the `.entry-map` slot.
 * The track bytes aren't uploaded, so RunTrackPreview shows its
 * placeholder inside the slot — but the slot rendering is the gate the
 * bug broke. Hermetic: plants + deletes its own run via the admin client.
 */
test.describe('feed map thumbnail', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let trackRunId: string | null = null;

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
				started_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
				duration_s: 2100,
				distance_m: 6200,
				source: 'app',
				is_public: true,
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();
		if (error) throw error;
		trackRunId = (row as { id: string }).id;
		// track_url must match the canonical {user_id}/{run_id}.json.gz shape
		// (runs_track_url_path_shape CHECK, migration 20260621_001). Setting it
		// makes has_track=true on public_runs; the bytes aren't uploaded.
		const { error: upErr } = await admin
			.from('runs')
			.update({ track_url: `${USER_A.id}/${trackRunId}.json.gz` })
			.eq('id', trackRunId);
		if (upErr) throw upErr;
	});

	test.afterEach(async () => {
		if (trackRunId) {
			await getAdminClient().from('runs').delete().eq('id', trackRunId);
			trackRunId = null;
		}
	});

	test('a followee run with a track renders the feed map slot', async ({ page }) => {
		await page.goto('/feed');
		// At least one card surfaces the .entry-map slot now that the gate
		// is has_track (pre-fix: gated on the dropped track_url → always 0).
		await expect(page.locator('.entry-map').first()).toBeVisible({ timeout: 10_000 });
	});
});
