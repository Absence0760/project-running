import { expect, test } from '@playwright/test';

import { USER_A } from './fixtures/users';

/**
 * The activity feed (recent public runs from people the viewer
 * follows) used to live at /feed as a top-level tab. It now lives
 * as a self-only "Feed" tab on the runner's own profile —
 * /u/[me]?tab=feed. The old /feed URL stays alive as a thin
 * redirect for the sitemap, the bell-popover CTA, and external
 * deep links.
 */

const FEED_URL = `/u/${USER_A.id}?tab=feed`;

test.describe('Feed (lives under /u/[me]?tab=feed)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/feed redirects to the profile Feed tab', async ({ page }) => {
		// The old top-level /feed URL is a thin client-side redirect to
		// /u/[me]?tab=feed. Anyone landing on /feed (sitemap, email
		// links, the bell-popover CTA, mobile push deep links) ends up
		// on the right surface.
		await page.goto('/feed');
		await expect(page).toHaveURL(/\/u\/[a-f0-9-]+\?tab=feed/, {
			timeout: 10_000
		});
	});

	test('activity-type filter narrows feed to matching runs (Cycle = empty)', async ({
		page
	}) => {
		// fetchFollowingFeed accepts an activityType filter that maps
		// to `metadata->>activity_type=<val>`. The seeded follows
		// (alex + morgan) only have `activity_type='run'` rows;
		// filtering to Cycle should collapse the feed to "No matches"
		// empty state. Pins both the filter wiring AND the empty-
		// state branch (we hit the "filters too narrow" variant, not
		// the "no follows" variant).
		await page.goto(FEED_URL);
		await page.waitForLoadState('networkidle');

		// Click the Cycle activity button (aria-label="Cycle").
		await page.getByRole('button', { name: 'Cycle', exact: true }).click();

		// "No matches" empty state should appear (no cycle runs).
		await expect(
			page.getByRole('heading', { name: 'No matches' })
		).toBeVisible({ timeout: 10_000 });

		// Click Clear filters → returns to default (All) → entries
		// reappear. (`Clear filters` is a button inside the empty
		// state.)
		await page.getByRole('button', { name: 'Clear filters' }).click();
		await expect(
			page.getByText(/Alex Chen|Morgan Lee/).first()
		).toBeVisible({ timeout: 10_000 });
	});

	test('User A sees a non-empty feed (seeded follows have public runs)', async ({
		page
	}) => {
		// Runner follows alex (USER_B) + morgan (USER_C_PRO). The seed
		// gives each ~12-13 recent public runs all within the
		// FEED_WINDOW_DAYS=14 window from 2026-04-27, so the feed is
		// expected to render at least a handful of entries — never
		// the empty state. Empty would mean either the follow graph
		// dropped, the public_runs view broke, or the date window
		// regressed.
		await page.goto(FEED_URL);
		await page.waitForLoadState('networkidle');

		// Should NOT see any of the empty-state headings.
		await expect(page.getByRole('heading', { name: 'Your feed is empty' })).toHaveCount(0);
		await expect(page.getByRole('heading', { name: 'No recent activity' })).toHaveCount(0);

		// Should see at least one entry — feed cards are rendered as
		// buttons that open a RunShareView modal. The seeded authors
		// "Alex Chen" + "Morgan Lee" appear inline as the entry author
		// label; assert at least one is visible.
		const authorLabels = page.getByText(/Alex Chen|Morgan Lee/);
		await expect(authorLabels.first()).toBeVisible({ timeout: 10_000 });
	});

	test('activity-type "Run" filter still shows entries (default activity)', async ({
		page
	}) => {
		await page.goto(FEED_URL);
		await page.getByRole('button', { name: 'Run', exact: true }).first().click();
		await expect(page.getByText(/Alex Chen|Morgan Lee/).first())
			.toBeVisible({ timeout: 10_000 });
	});

	test('feed window-hint label is visible (last 14 days)', async ({ page }) => {
		await page.goto(FEED_URL);
		// The toolbar shows a small window hint — match the literal
		// "14 days" string which is part of the FEED_WINDOW_DAYS label.
		await expect(page.getByText(/14 days/i).first())
			.toBeVisible({ timeout: 10_000 });
	});
});
