import { expect, test } from '@playwright/test';

import { USER_A } from './fixtures/users';

/**
 * The activity feed (recent public runs from people the viewer follows)
 * lives as the default tab under /social. /feed and /u/[me]?tab=feed are
 * kept alive as thin redirects so the sitemap, the bell-popover CTA, and
 * external deep links keep resolving.
 */

const FEED_URL = '/social?tab=feed';

test.describe('Feed (lives under /social?tab=feed)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/feed redirects to /social?tab=feed', async ({ page }) => {
		await page.goto('/feed');
		await expect(page).toHaveURL(/\/social\?tab=feed/, { timeout: 10_000 });
	});

	test('/u/[me]?tab=feed (legacy) also redirects to /social?tab=feed', async ({ page }) => {
		await page.goto(`/u/${USER_A.id}?tab=feed`);
		await expect(page).toHaveURL(/\/social\?tab=feed/, { timeout: 10_000 });
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
