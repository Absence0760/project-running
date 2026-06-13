import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/exercise — the per-exercise progression drill-down
 * (lib/gym/exercise_history.ts, decisions §63, multi_modal.md § Gym). Where
 * /gym/records shows each exercise's current best, this shows the trajectory:
 * a session-by-session history with the headline est.-1RM delta and a PR badge
 * on sessions that set a new estimated 1RM.
 *
 * Drives it end to end: log two sessions of the same exercise at increasing
 * weight, open the records card's link, and confirm both sessions show with
 * the heavier one carrying an est.-1RM PR. Unique exercise name per run so
 * assertions and cleanup never collide with prior rows in the shared seed DB.
 */
test.describe('/gym/exercise — per-exercise progression', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('two sessions → records card link → progression with a PR on the heavier', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const exercise = `E2E Press ${stamp}`;
		const workoutIds: string[] = [];

		// Log two sessions of the same exercise: 100 kg then 110 kg.
		for (const weight of ['100', '110']) {
			await page.goto('/gym');
			await page.getByTestId('gym-log').click();
			await page.getByPlaceholder('e.g. Push day').fill(`${exercise} ${weight}`);
			await page.getByPlaceholder('Exercise name').first().fill(exercise);
			const setRow = page.locator('.set-row').first();
			await setRow.locator('input[type="number"]').nth(0).fill('5');
			await setRow.locator('input[type="number"]').nth(1).fill(weight);
			await page.getByRole('button', { name: 'Save workout' }).click();
			await expect(page.locator('.workout-row', { hasText: `${exercise} ${weight}` })).toBeVisible({
				timeout: 10_000,
			});
		}

		const { data: created } = await admin
			.from('gym_workouts')
			.select('id')
			.eq('user_id', USER_A.id)
			.like('title', `${exercise}%`);
		for (const w of created ?? []) workoutIds.push(w.id as string);
		expect(workoutIds.length).toBe(2);

		try {
			// From records, click into this exercise's progression.
			await page.goto('/gym/records');
			const card = page.locator('.record-card', { hasText: exercise });
			await expect(card).toBeVisible({ timeout: 10_000 });
			await card.click();
			await expect(page).toHaveURL(/\/gym\/exercise\?name=/);

			// Both sessions present; the heaviest set line is shown.
			const rows = page.locator('.session-row');
			await expect(rows).toHaveCount(2);
			await expect(page.locator('.session-row', { hasText: '110 kg × 5' })).toBeVisible();

			// Exactly the PR sessions carry a badge: first-ever session (100) and
			// the new-best session (110) — both beat the running best at the time.
			await expect(page.locator('.session-row .pr-badge')).toHaveCount(2);

			// A session row links back to its workout.
			await expect(rows.first().locator('a.row-link')).toHaveAttribute(
				'href',
				new RegExp(`/gym/(${workoutIds.join('|')})`),
			);
		} finally {
			for (const id of workoutIds) await admin.from('gym_workouts').delete().eq('id', id);
		}
	});

	test('a failed history load shows an error + retry, and retry recovers', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/rpc/gym_exercise_set_history**', async (route) => {
			if (failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/gym/exercise?name=E2E%20Nonexistent%20Lift');
		// Error state, not the empty "no history" card masquerading as a failure.
		await expect(page.locator('.error-banner')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Retry' }).click();
		// Retry re-fetches (now unblocked) → the real empty-or-progression state renders.
		await expect(page.locator('.error-banner')).toHaveCount(0, { timeout: 10_000 });
	});
});
