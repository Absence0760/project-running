import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Training-consistency card on /dashboard (backlog #11, advanced analytics
 * polish).
 *
 * The card reports how many of the last 12 calendar weeks the runner trained,
 * the trailing active-week streak, and whether weekly volume is steady or
 * spiky (pure logic in lib/training/consistency.ts, unit-tested separately).
 * This e2e pins the SURFACE: a runner with runs spread across several distinct
 * weeks sees the card with an "N/12" active-weeks readout and a current-streak
 * stat; a runner with only a single week of activity never sees it (the
 * < 2-active-weeks self-hide).
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('dashboard training-consistency card', () => {
	let consistent: SagaUser;
	let oneWeek: SagaUser;

	test.beforeAll(async () => {
		[consistent, oneWeek] = await createSagaUsers(2, {
			displayNames: ['Consistent Runner', 'One-Week Runner'],
		});

		// Runs spread ~one week apart across four distinct calendar weeks so
		// weeksActive is comfortably >= 2 regardless of the week-start pref.
		for (const daysBack of [1, 8, 15, 22]) {
			await insertRun({
				user_id: consistent.id,
				started_at: new Date(Date.now() - daysBack * 86_400_000).toISOString(),
				distance_m: 8_000,
				duration_s: 2_400,
				source: 'app',
			});
		}

		// Two runs, both in the current week → only ONE active week → the card
		// must stay hidden (< 2 active weeks).
		for (const daysBack of [0, 1]) {
			await insertRun({
				user_id: oneWeek.id,
				started_at: new Date(Date.now() - daysBack * 86_400_000).toISOString(),
				distance_m: 5_000,
				duration_s: 1_500,
				source: 'app',
			});
		}
	});

	test.afterAll(async () => {
		await deleteSagaUsers([consistent, oneWeek].filter(Boolean));
	});

	test('renders the card with an N/12 active-weeks readout and a streak stat', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: consistent.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');

			const card = page.getByTestId('consistency-card');
			await expect(card).toBeVisible({ timeout: 15_000 });

			// Active-weeks readout is denominated in the 12-week window.
			await expect(page.getByTestId('consistency-active')).toContainText('/12');

			// The current-week-streak stat renders a numeric value.
			await expect(page.getByTestId('consistency-current-streak')).toHaveText(/^\d+$/);
		} finally {
			await ctx.close();
		}
	});

	test('hides the card for a runner with only a single active week', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: oneWeek.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await page.waitForLoadState('networkidle');
			await expect(page.getByTestId('consistency-card')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
