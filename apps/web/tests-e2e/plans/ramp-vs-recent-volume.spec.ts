import { expect, test, type BrowserContext, type Page } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { USER_B } from '../fixtures/users';

/**
 * /plans wizard — the opening-week ramp note (lib/training/plan_ramp.ts).
 *
 * `generatePlan` sizes weeks off the goal race alone, so the preview used to
 * offer a runner averaging 20 km a week a marathon plan opening at 38 km with
 * nothing said. The note grades the plan against the runner's trailing-28-day
 * average through the coach roster's ACWR bands — too-big off the opening
 * week, too-light off the peak week.
 *
 * The band arithmetic is unit-tested; this pins the wiring — the volume read,
 * the helper, the verdict-to-copy mapping.
 *
 * **Each test owns its 28-day window, by different means.** The verdict is a
 * ratio against the account's ambient volume, so a test that merely hopes the
 * account is quiet is a test that passes or fails on which specs ran before
 * it. The "under" case is additive-safe and can therefore stay on a seeded
 * user; the "high" case is not, and mints its own.
 *
 * Both assert the note's LABEL before its body, so a generator change that
 * moves a verdict fails as "rendered with different copy" rather than as a
 * bare "element not found".
 */

const DAY_MS = 24 * 3600 * 1000;
const RAMP_LABEL = 'Plan vs. your recent training';

const openWizard = async (page: Page) => {
	await page.goto('/plans');
	await page.getByRole('button', { name: /New plan/ }).first().click();
	const modal = page.locator('.modal');
	await expect(modal).toBeVisible({ timeout: 5_000 });
	return modal;
};

test.describe('/plans wizard — a plan that never reaches the runner', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('a 5K plan under an established base reads as under-cooked', async ({ page }) => {
		const runIds: string[] = [];
		try {
			// One 30 km run in each of the four trailing windows. A 5K plan at
			// the wizard's default 4 days PEAKS at 20 km, so the under band
			// (ratio < 0.8) needs a chronic base above 25 km/week — and the
			// 120 km planted here is 30 km/week on its own, before any of the
			// account's existing volume is counted.
			//
			// That is what makes this test safe on a shared seeded user: every
			// ambient run only ADDS to the chronic base, which drives the ratio
			// further under, never back toward the band edge. (For the record,
			// seed.sql plants alex 12 runs at `NOW() - n * 14 hours`, 79,578 m
			// in total — a permanent 19.9 km/week baseline that lands wholly
			// inside the window on any database, however freshly reset.)
			for (const daysAgo of [2, 9, 16, 23]) {
				runIds.push(
					await insertRun({
						user_id: USER_B.id,
						started_at: new Date(Date.now() - daysAgo * DAY_MS).toISOString(),
						duration_s: 9000,
						distance_m: 30_000,
					}),
				);
			}

			const modal = await openWizard(page);
			await modal.getByLabel('Goal race').selectOption('distance_5k');

			await expect(modal.getByText(RAMP_LABEL)).toBeVisible({ timeout: 10_000 });
			await expect(modal.getByText(/A longer goal race or more training days/)).toBeVisible();
		} finally {
			for (const id of runIds) await deleteRun(id);
		}
	});
});

test.describe('/plans wizard — a plan that opens above the runner', () => {
	// A seeded user cannot host this case. The high band needs the plan's
	// opening week at >= 1.5x the chronic base, so ambient volume works
	// AGAINST the verdict, and seed.sql alone already gives alex a 19.9
	// km/week base — the first cut of this test asserted a ceiling on that
	// ambient volume and was red on a fresh database, not merely a busy one.
	// A saga user's 28-day window is empty by construction, so the base is
	// exactly what this test plants and no precondition is needed at all.
	let users: SagaUser[] = [];
	let runner: SagaUser;

	test.beforeAll(async () => {
		users = await createSagaUsers(1, { displayNames: ['Saga Ramp Runner'] });
		[runner] = users;
		// 10 km in each of the four trailing windows: a chronic base of exactly
		// 10 km/week, and four active windows so the history gate passes.
		for (const daysAgo of [2, 9, 16, 23]) {
			await insertRun({
				user_id: runner.id,
				started_at: new Date(Date.now() - daysAgo * DAY_MS).toISOString(),
				duration_s: 3300,
				distance_m: 10_000,
			});
		}
	});

	test.afterAll(async () => {
		// deleteSagaUsers sweeps runs + training_plans before the auth.users
		// delete, so the planted runs need no separate teardown.
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('a marathon plan over a 10 km/week base warns about the opening week', async ({
		browser,
	}) => {
		const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:7777';
		const context: BrowserContext = await browser.newContext({
			baseURL,
			storageState: runner.storageStatePath,
		});
		try {
			const page = await context.newPage();
			const modal = await openWizard(page);
			// Marathon at the wizard's default 4 days, no goal time: a 23 km
			// opening week against a 10 km/week base is a ratio of 2.3, well
			// inside the high band (>= 1.5) rather than balanced on its edge.
			await modal.getByLabel('Goal race').selectOption('distance_full');

			await expect(modal.getByText(RAMP_LABEL)).toBeVisible({ timeout: 10_000 });
			await expect(
				modal.getByText(/Fewer training days, a shorter goal race/),
			).toBeVisible();
		} finally {
			await context.close();
		}
	});
});
