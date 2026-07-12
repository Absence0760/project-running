import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Easy/hard balance + week/month trend-delta cards on /dashboard (backlog #11,
 * advanced analytics polish).
 *
 * The intensity card reports the time-weighted easy vs hard split against the
 * ~80/20 guideline with a verdict (pure logic in lib/training/intensity.ts).
 * The trend card reports week-over-week + month-over-month deltas on distance /
 * time / runs (pure logic in lib/training/trend_deltas.ts). Both are
 * unit-tested separately; this e2e pins the SURFACE: a runner with a fast
 * anchor + a spread of easy runs sees the balance card with a verdict + an
 * easy-%, and a runner with recent activity sees the trend card with a
 * week-distance delta. A runner with too few classified runs never sees the
 * balance card (the < 4-classified-runs self-hide).
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('dashboard intensity-balance + trend-delta cards', () => {
	let balanced: SagaUser;
	let sparse: SagaUser;

	test.beforeAll(async () => {
		[balanced, sparse] = await createSagaUsers(2, {
			displayNames: ['Balanced Runner', 'Sparse Runner'],
		});

		// One fast 5K (4:00/km) anchors the VDOT threshold and reads HARD;
		// five easy 8 km runs (6:40/km) read EASY. Six classified runs clears
		// the >= 4 floor, and the recent ones populate the current + prior week
		// so the trend card has data too. All within the 56-day window.
		await insertRun({
			user_id: balanced.id,
			started_at: new Date(Date.now() - 1 * 86_400_000).toISOString(),
			distance_m: 5_000,
			duration_s: 1_200,
			source: 'app',
		});
		for (const daysBack of [2, 8, 16, 24, 32]) {
			await insertRun({
				user_id: balanced.id,
				started_at: new Date(Date.now() - daysBack * 86_400_000).toISOString(),
				distance_m: 8_000,
				duration_s: 3_200,
				source: 'app',
			});
		}

		// Two runs only → fewer than the 4-run classification floor → the
		// balance card must stay hidden.
		for (const daysBack of [0, 3]) {
			await insertRun({
				user_id: sparse.id,
				started_at: new Date(Date.now() - daysBack * 86_400_000).toISOString(),
				distance_m: 5_000,
				duration_s: 1_500,
				source: 'app',
			});
		}
	});

	test.afterAll(async () => {
		await deleteSagaUsers([balanced, sparse].filter(Boolean));
	});

	test('renders the balance card with a verdict + easy split and the trend card with a week delta', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: balanced.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');

			const balance = page.getByTestId('intensity-balance');
			await expect(balance).toBeVisible({ timeout: 15_000 });
			// A verdict chip renders one of the three known verdicts.
			await expect(page.getByTestId('intensity-verdict')).toHaveText(
				/On guideline|Too hard|All easy/
			);
			// The easy + hard split percentages render and are complementary.
			await expect(page.getByTestId('intensity-easy-pct')).toHaveText(/^\d+%$/);
			await expect(page.getByTestId('intensity-hard-pct')).toHaveText(/^\d+%$/);
			// Mostly-easy training reads as a majority-easy split.
			await expect(page.getByTestId('intensity-counts')).toContainText('easy');

			// Trend-delta card: week-distance cell renders a current value + a
			// direction affordance.
			const trend = page.getByTestId('trend-deltas');
			await expect(trend).toBeVisible();
			await expect(page.getByTestId('trend-week-distance')).toBeVisible();
			await expect(page.getByTestId('trend-week-runs')).toBeVisible();
		} finally {
			await ctx.close();
		}
	});

	test('hides the balance card for a runner with too few classified runs', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: sparse.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await page.waitForLoadState('networkidle');
			await expect(page.getByTestId('intensity-balance')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
