import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * /plans wizard — the opening-week ramp note (lib/training/plan_ramp.ts).
 *
 * `generatePlan` sizes weeks off the goal race alone, so the preview used to
 * offer a runner averaging 20 km a week a marathon plan opening at 38 km with
 * nothing said. The note grades that opening ask against the runner's
 * trailing-28-day average through the coach roster's ACWR bands.
 *
 * The band arithmetic is unit-tested; this pins the wiring — the volume read,
 * the helper, the verdict-to-copy mapping, and that the note recomputes live
 * as the wizard's inputs change.
 *
 * The seeded runs are additive, so the "under" case is robust against
 * whatever history the account already carries: extra volume only pushes the
 * chronic base UP, which drives the ratio further into the under band. The
 * "high" case is the opposite — pre-existing volume works against it — so it
 * reads the account's actual 28-day total first and fails loudly on a
 * precondition rather than cryptically on the verdict.
 */
test.describe('/plans wizard — opening week vs recent volume', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const DAY_MS = 24 * 3600 * 1000;

	const openWizard = async (page: Page) => {
		await page.goto('/plans');
		await page.getByRole('button', { name: /New plan/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		return modal;
	};

	/// Total non-cycling metres the account already has inside the 28-day
	/// chronic window, so a test can reason about the base it is adding to.
	const existingWindowMetres = async (): Promise<number> => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('runs')
			.select('distance_m, activity_type')
			.eq('user_id', USER_B.id)
			.gte('started_at', new Date(Date.now() - 28 * DAY_MS).toISOString());
		return (data ?? [])
			.filter((r) => r.activity_type !== 'cycle')
			.reduce((sum, r) => sum + (r.distance_m ?? 0), 0);
	};

	test('a 5K plan under an established base reads as under-cooked', async ({ page }) => {
		const runIds: string[] = [];
		try {
			// One 30 km run in each of the four trailing windows: the
			// active-weeks gate passes and the chronic base is at least
			// 30 km/week. A 5K plan at the wizard's default 4 days PEAKS at
			// 20 km — a ratio of at most 0.67, inside the under band — and
			// opens at 14 km, nowhere near the safety arm.
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

			await expect(modal.getByText('Plan vs. your recent training')).toBeVisible({
				timeout: 10_000,
			});
			await expect(
				modal.getByText(/A longer goal race or more training days/),
			).toBeVisible();
		} finally {
			for (const id of runIds) await deleteRun(id);
		}
	});

	test('a marathon plan over a thin base warns about the opening week', async ({ page }) => {
		const runIds: string[] = [];
		try {
			// A marathon at 7 days/week with no fitness anchor opens at 31 km.
			// For that to land in the high band (ratio >= 1.5) the chronic
			// average must be at most ~20.6 km/week, i.e. at most ~82.6 km
			// inside the window — including the 6 km planted below.
			const existing = await existingWindowMetres();
			expect(
				existing,
				'USER_B is carrying more than ~76 km of runs inside the 28-day window ' +
					'(likely leftovers from another spec) — the planted thin base can no ' +
					'longer produce a high-band opening week',
			).toBeLessThan(76_000);

			// Three short runs across three windows: enough history for the
			// check to speak at all, little enough that the base stays thin.
			for (const daysAgo of [2, 9, 16]) {
				runIds.push(
					await insertRun({
						user_id: USER_B.id,
						started_at: new Date(Date.now() - daysAgo * DAY_MS).toISOString(),
						duration_s: 720,
						distance_m: 2000,
					}),
				);
			}

			const modal = await openWizard(page);
			await modal.getByLabel('Goal race').selectOption('distance_full');
			// The days select binds numbers, so pick by position (3,4,5,6,7)
			// rather than by a value string Svelte may not mirror to the DOM.
			await modal.getByLabel('Days per week').selectOption({ index: 4 });

			await expect(
				modal.getByText(/Fewer training days, a shorter goal race/),
			).toBeVisible({ timeout: 10_000 });
		} finally {
			for (const id of runIds) await deleteRun(id);
		}
	});
});
