import { expect, test } from '@playwright/test';

import { USER_A } from './fixtures/users';

/**
 * /feed — activity feed of recent public runs from people the viewer
 * follows. Cursor-paginated on (started_at, id), filtered by the
 * 14-day FEED_WINDOW. Empty state has three flavours (no follows,
 * filters too narrow, no recent activity) that should each be
 * exercised here as the file deepens.
 */

test.describe('/feed', () => {
	test.use({ storageState: USER_A.storageStatePath });

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
		await page.goto('/feed');
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
});
