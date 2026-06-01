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

	test('Run activity filter retains the planted run (counterpart to the Cycle empty state)', async ({
		page
	}) => {
		// The existing Cycle test pins the empty-state branch; pin the
		// happy-path side so a regression that inverted the filter
		// (e.g. matched the wrong activity_type) would surface as the
		// planted Run vanishing under the Run filter.
		await page.goto('/social?tab=feed');
		await expect(page.locator('article').first()).toBeVisible({ timeout: 10_000 });
		await page.getByRole('button', { name: 'Run' }).click();
		// At least one article still renders + it shows the runner.
		await expect(page.locator('article').first()).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText(/Jared/).first()).toBeVisible();
	});

	test('window hint advertises "Last 14 days"', async ({ page }) => {
		// FEED_WINDOW_DAYS (data.ts:3020) drives the 14-day cutoff
		// AND the visible window-hint label. They must stay in lockstep
		// — if a future change bumps the constant to 30 the hint should
		// follow. Pin the literal "14 days" so a one-sided edit fails
		// loud. (The cutoff is exercised by the
		// "15-day-old run not in feed" test below.)
		await page.goto('/social?tab=feed');
		await expect(page.locator('.window-hint')).toContainText('Last 14 days', {
			timeout: 10_000
		});
	});

	test('run older than the 14-day window does not appear in the feed', async ({
		page
	}) => {
		// FEED_WINDOW_DAYS is 14. A regression that widened the cutoff
		// (or dropped the filter altogether) would let stale activity
		// leak into the feed long after the runner expected it to fall
		// off. Plant a 15-days-ago run with an identifiable distance,
		// then assert the feed does NOT show that signature.
		const admin = getAdminClient();
		const STALE_DISTANCE = 12345; // unmistakable signature
		const { data: row, error } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 15 * 24 * 60 * 60 * 1000).toISOString(),
				duration_s: 3600,
				distance_m: STALE_DISTANCE,
				source: 'app',
				is_public: true,
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();
		if (error) throw error;
		const staleId = (row as { id: string }).id;
		try {
			await page.goto('/social?tab=feed');
			await expect(page.locator('article').first()).toBeVisible({
				timeout: 10_000
			});
			// The fresh (1h ago) run from beforeEach must be visible,
			// the 15-day-old one with the signature distance must not.
			// `12.35 km` is what the 1-decimal formatter emits for 12345m.
			await expect(page.getByText(/12\.35\s*km/i)).toHaveCount(0, {
				timeout: 5_000
			});
		} finally {
			await admin.from('runs').delete().eq('id', staleId);
		}
	});

	test('feed card shows the run title when present', async ({ page }) => {
		// persona round-5 (runner-very-social): the title/caption is the
		// social hook. A titled run must surface that title on its feed
		// card, not just the author + stats. Plant a run with a unique
		// title and assert it renders.
		const admin = getAdminClient();
		const TITLE = `5am PR attempt ${Date.now()}`;
		const { data: row, error } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
				duration_s: 1500,
				distance_m: 6000,
				source: 'app',
				is_public: true,
				metadata: { activity_type: 'run', title: TITLE }
			})
			.select('id')
			.single();
		if (error) throw error;
		const titledId = (row as { id: string }).id;
		try {
			await page.goto('/social?tab=feed');
			await expect(page.locator('article').first()).toBeVisible({
				timeout: 10_000
			});
			await expect(page.locator('.entry-title', { hasText: TITLE })).toBeVisible({
				timeout: 10_000
			});
		} finally {
			await admin.from('runs').delete().eq('id', titledId);
		}
	});

	test('untitled run renders no empty title element', async ({ page }) => {
		// The beforeEach plants a run with NO title. Assert the feed shows
		// at least one card but renders zero `.entry-title` nodes, so an
		// untitled run doesn't leave an empty heading on the card.
		await page.goto('/social?tab=feed');
		await expect(page.locator('article').first()).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('.entry-title')).toHaveCount(0);
	});

	test('private run from a followed user does not appear', async ({ page }) => {
		// `fetchFollowingFeed` filters `is_public = true`. A regression
		// that loosened the visibility predicate (or routed through the
		// owner-side path by mistake) would expose private activity to
		// every follower — a privacy regression with real teeth. Plant
		// a private run with a unique distance + assert it doesn't
		// surface.
		const admin = getAdminClient();
		const PRIVATE_DISTANCE = 23456;
		const { data: row, error } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
				duration_s: 1500,
				distance_m: PRIVATE_DISTANCE,
				source: 'app',
				is_public: false, // ← the gate
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();
		if (error) throw error;
		const privateId = (row as { id: string }).id;
		try {
			await page.goto('/social?tab=feed');
			await expect(page.locator('article').first()).toBeVisible({
				timeout: 10_000
			});
			// `23.46 km` is the formatter signature.
			await expect(page.getByText(/23\.46\s*km/i)).toHaveCount(0, {
				timeout: 5_000
			});
		} finally {
			await admin.from('runs').delete().eq('id', privateId);
		}
	});
});
