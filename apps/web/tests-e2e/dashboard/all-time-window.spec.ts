import { expect, test, type Page } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * The period drilldown's all-time tab must roll up the runner's REAL
 * history, not /dashboard's ~2-year fetch window.
 *
 * #332 bounded the dashboard run fetch to DASHBOARD_RUNS_WINDOW_DAYS (730)
 * and served the Total-runs / Longest-run cards from a separate lifetime
 * aggregate. The same bounded set was still handed to <PeriodSummary>,
 * which offers an "all time" tab — so clicking the "Longest run / all
 * time" card opened a modal whose totals disagreed with the very card that
 * opened it, short by everything older than the window (issue #664).
 *
 * The plant is deliberately minimal and unambiguous: one recent run and
 * one run ~3 years old that is also the runner's LONGEST. Inside the
 * window the all-time roll-up can only see the recent run; the fix makes
 * it load the full history on demand.
 */

const METRES_PER_KM = 1000;
const DAY_MS = 86_400_000;

const RECENT_RUN = { distance_m: 6_000, duration_s: 1_800 };
// ~3 years back — comfortably outside the 730-day dashboard window, and
// the longest run this runner has ever done.
const ANCIENT_RUN = { distance_m: 21_097, duration_s: 7_200 };
const ANCIENT_DAYS_AGO = 1_100;

const allDistance = RECENT_RUN.distance_m + ANCIENT_RUN.distance_m;
const allCount = 2;

function kmLabel(metres: number): string {
	return `${(metres / METRES_PER_KM).toFixed(2)} km`;
}

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

async function modalStatValue(page: Page, label: string): Promise<string> {
	const card = page
		.locator('.modal .stats .stat-card')
		.filter({ has: page.locator('.stat-label', { hasText: new RegExp(`^${label}$`) }) });
	await expect(card).toBeVisible({ timeout: 15_000 });
	return ((await card.locator('.stat-value').textContent()) ?? '').trim();
}

test.describe('dashboard all-time drilldown vs the fetch window', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Deep History Runner'] });
		await insertRun({
			user_id: user.id,
			started_at: new Date(Date.now() - 2 * DAY_MS).toISOString(),
			distance_m: RECENT_RUN.distance_m,
			duration_s: RECENT_RUN.duration_s,
		});
		await insertRun({
			user_id: user.id,
			started_at: new Date(Date.now() - ANCIENT_DAYS_AGO * DAY_MS).toISOString(),
			distance_m: ANCIENT_RUN.distance_m,
			duration_s: ANCIENT_RUN.duration_s,
		});
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('the all-time summary counts a run older than the dashboard window', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			await page.goto('/dashboard');

			// The lifetime aggregate cards see both runs — they always did.
			const longestCard = page
				.locator('.stat-grid .stat-card')
				.filter({ has: page.locator('.stat-label', { hasText: 'Longest Run' }) })
				.first();
			await expect(longestCard.locator('.stat-value')).toHaveText(
				kmLabel(ANCIENT_RUN.distance_m),
				{ timeout: 15_000 }
			);

			// Drilling into that card opened an all-time modal that only saw
			// the windowed set — 1 run / 6 km, contradicting the card.
			await page.getByRole('button', { name: /Longest Run/ }).first().click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 10_000 });
			await expect(modal.locator('.type-toggle .toggle-btn.active')).toHaveText('all time');

			expect(await modalStatValue(page, 'Runs')).toBe(String(allCount));
			expect(await modalStatValue(page, 'Distance')).toBe(kmLabel(allDistance));
			// The out-of-window run is listed, not merely counted.
			await expect(
				modal.locator('.run-list .run-row .run-dist', {
					hasText: kmLabel(ANCIENT_RUN.distance_m)
				})
			).toBeVisible();
			await expect(modal.locator('.run-list .run-row')).toHaveCount(allCount);
		} finally {
			await ctx.close();
		}
	});

	test('the week tab is still answered straight from the windowed prop set', async ({
		browser
	}) => {
		// The lazy load must stay scoped to periods the bounded set cannot
		// cover — putting a full-history scan on the common drilldown path
		// is exactly what #332 removed. The recent run is inside this week,
		// so the week roll-up comes from the prop set with no re-fetch.
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			await page.goto('/dashboard');
			const weekCard = page.getByRole('button', { name: /This Week/ }).first();
			await expect(weekCard).toBeVisible({ timeout: 15_000 });
			await weekCard.click();

			const modal = page.locator('.modal');
			await expect(modal.getByRole('button', { name: 'Week' })).toBeVisible({
				timeout: 10_000
			});
			expect(await modalStatValue(page, 'Runs')).toBe('1');
			expect(await modalStatValue(page, 'Distance')).toBe(kmLabel(RECENT_RUN.distance_m));
		} finally {
			await ctx.close();
		}
	});
});
