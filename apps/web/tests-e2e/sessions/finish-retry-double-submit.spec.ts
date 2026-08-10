import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /sessions/[id] — the "couldn't save your session" retry must log the session
 * once, however many times it is pressed.
 *
 * `failedFinish` only clears on a SUCCESSFUL save, so the retry banner stays
 * mounted for the whole in-flight retry. With no guard on `onSessionFinish`,
 * a second press started a second `createGymWorkout` insert: the runner ended
 * up with the same session logged twice in Train → Gym, double-counted into
 * exercise calories, the nutrition budget and the training-load curve, and had
 * to find and delete the duplicate by hand.
 *
 * The fix guards the mutation itself (not just the button), so this spec
 * dispatches the clicks directly rather than going through Playwright's
 * actionability checks — a `disabled` attribute alone would not prove it.
 */

test.describe('/sessions/[id] — save-retry double submit', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdPlanIds: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const planId of createdPlanIds.splice(0)) {
			const { data } = await admin
				.from('gym_workouts')
				.select('id, metadata')
				.eq('user_id', USER_A.id);
			for (const row of (data ?? []) as { id: string; metadata: Record<string, unknown> }[]) {
				if (row.metadata?.session_plan_id === planId) {
					await admin.from('gym_workouts').delete().eq('id', row.id);
				}
			}
			await admin.from('session_plans').delete().eq('id', planId);
		}
	});

	async function seedOneStepPlan(): Promise<{ id: string; title: string }> {
		const admin = getAdminClient();
		const title = `e2e-retry ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline: 'yoga' })
			.select('id')
			.single();
		if (error) throw error;
		const id = data!.id as string;
		createdPlanIds.push(id);
		await admin.from('session_plan_items').insert({
			plan_id: id,
			position: 0,
			movement_name: 'Downward dog',
			kind: 'reps',
			reps: 5,
			per_side: false
		});
		return { id, title };
	}

	test('pressing Retry twice logs the session once', async ({ page }) => {
		const plan = await seedOneStepPlan();

		let workoutPosts = 0;
		await page.route('**/rest/v1/gym_workouts*', async (route) => {
			if (route.request().method() !== 'POST') {
				await route.continue();
				return;
			}
			workoutPosts += 1;
			if (workoutPosts === 1) {
				// Fail the first save so the retry banner appears.
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated session save failure' })
				});
				return;
			}
			// Hold the retry open long enough for a second press to land.
			await new Promise((r) => setTimeout(r, 1500));
			await route.continue();
		});

		await page.goto(`/sessions/${plan.id}`);
		await expect(page.getByRole('heading', { name: plan.title })).toBeVisible({
			timeout: 10_000
		});
		await page.getByTestId('session-start').click();
		await expect(page.getByTestId('session-runner')).toBeVisible();
		await page.getByTestId('session-done').click();

		const banner = page.getByTestId('session-save-failed');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		expect(workoutPosts).toBe(1);

		const retry = page.getByTestId('session-retry-save');
		await retry.dispatchEvent('click');
		await retry.dispatchEvent('click');

		// Both presses have had time to reach the network, and the retry is
		// still in flight behind the 1500 ms hold above.
		await page.waitForTimeout(600);
		// One failed insert + exactly one retry insert — never two retries.
		expect(workoutPosts).toBe(2);
		// The control also reads as busy for as long as the save is running.
		await expect(retry).toBeDisabled();

		// The retry succeeds, so the banner clears.
		await expect(banner).toHaveCount(0, { timeout: 20_000 });

		const admin = getAdminClient();
		const { data } = await admin
			.from('gym_workouts')
			.select('id, metadata')
			.eq('user_id', USER_A.id);
		const logged = ((data ?? []) as { id: string; metadata: Record<string, unknown> }[]).filter(
			(w) => w.metadata?.session_plan_id === plan.id
		);
		expect(logged).toHaveLength(1);
	});
});
