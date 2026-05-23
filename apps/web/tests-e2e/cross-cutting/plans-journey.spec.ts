import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Plans journey — mark 2 workouts done in a row, then revert 1, and
 * watch BOTH the day-grid `.day.completed` count and the hero
 * progress ring `.pct` value stay in sync at every step.
 *
 * Same shape as cross-cutting/dashboard-journey.spec.ts: snapshot →
 * mutate → verify → mutate → verify → revert. Pins the
 * `markWorkoutCompleted` → `load()` → re-render pipeline against the
 * cumulative case (one mark, then another, then unmark) — the
 * batch-14 day-cell test only covered a single mark.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('plans journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		// Clear every manually_completed=true row on the plan. The
		// seed has zero (its one completion is via completed_run_id),
		// so this scoops up exactly the workouts the test marked.
		const admin = getAdminClient();
		const { data: weeks } = await admin
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SYDNEY_HALF_PLAN_ID);
		const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
		if (weekIds.length === 0) return;
		await admin
			.from('plan_workouts')
			.update({ manually_completed: false })
			.in('week_id', weekIds)
			.eq('manually_completed', true);
	});

	test('mark 2 workouts done in sequence, revert 1 — pct + day-grid stay in lockstep', async ({
		page
	}) => {
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.getByRole('heading', { level: 1, name: /Richmond Half 2026/ }))
			.toBeVisible({ timeout: 10_000 });

		const pct = page.locator('.pct');
		const completedCount = page.locator('.day.completed');

		const readPct = async (): Promise<number> => {
			const txt = (await pct.textContent()) ?? '';
			const m = txt.match(/(\d+)/);
			return m ? parseInt(m[1], 10) : -1;
		};

		// ── Snapshot ───────────────────────────────────────────────
		const initialCompleted = await completedCount.count();
		expect(initialCompleted).toBe(1);
		const initialPct = await readPct();
		expect(initialPct).toBeGreaterThanOrEqual(0);

		// ── Mark workout 1 done ────────────────────────────────────
		await test.step('mark first non-rest, non-completed workout done', async () => {
			await page
				.locator('.day:not(.rest):not(.completed) .day-link')
				.first()
				.click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByRole('button', { name: 'Mark as done' }).click();
			await expect(modal).toHaveCount(0);
		});

		await expect(completedCount).toHaveCount(initialCompleted + 1, { timeout: 10_000 });
		await expect.poll(readPct, { timeout: 10_000 }).toBeGreaterThan(initialPct);
		const afterFirstPct = await readPct();

		// ── Mark workout 2 done ────────────────────────────────────
		await test.step('mark a second non-rest, non-completed workout done', async () => {
			await page
				.locator('.day:not(.rest):not(.completed) .day-link')
				.first()
				.click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByRole('button', { name: 'Mark as done' }).click();
			await expect(modal).toHaveCount(0);
		});

		await expect(completedCount).toHaveCount(initialCompleted + 2, { timeout: 10_000 });
		await expect.poll(readPct, { timeout: 10_000 }).toBeGreaterThan(afterFirstPct);
		const afterSecondPct = await readPct();

		// ── Revert one via UI ──────────────────────────────────────
		// Tricky bit: the seed completion is via `completed_run_id`
		// (a real run linked); its modal disables "Mark not done"
		// with the title "A run is linked — unlink it from the
		// workout detail page first." So the seed completed cell
		// can NOT be reverted from the editor. The two cells the
		// test marked use `manually_completed=true` and CAN.
		//
		// Pick the completed cell whose editor exposes an enabled
		// "Mark not done" button. Walking from .last() backward (the
		// test marks are later than the seed completion in week
		// order, but day-of-week within a week varies — safest to
		// just iterate).
		await test.step('revert one of the test-marked workouts via the editor', async () => {
			const completedDays = page.locator('.day.completed:not(.rest) .day-link');
			const total = await completedDays.count();
			let reverted = false;
			for (let i = total - 1; i >= 0; i--) {
				await completedDays.nth(i).click();
				const modal = page.locator('.modal');
				await expect(modal).toBeVisible({ timeout: 5_000 });
				const btn = modal.getByRole('button', { name: 'Mark not done' });
				if (await btn.isEnabled()) {
					await btn.click();
					await expect(modal).toHaveCount(0);
					reverted = true;
					break;
				}
				// Linked-run cell — close modal and try the next.
				await page.locator('.modal-close').click();
				await expect(modal).toHaveCount(0);
			}
			expect(reverted, 'no manually-completed cell found to revert')
				.toBe(true);
		});

		await expect(completedCount).toHaveCount(initialCompleted + 1, { timeout: 10_000 });
		// pct dropped from afterSecondPct back toward afterFirstPct,
		// but stays >= initialPct (one of the two test-marks remains).
		await expect
			.poll(readPct, { timeout: 10_000 })
			.toBeLessThan(afterSecondPct);
		expect(await readPct()).toBeGreaterThanOrEqual(initialPct);
	});
});
