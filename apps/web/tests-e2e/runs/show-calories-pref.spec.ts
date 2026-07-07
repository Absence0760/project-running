import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * hunt-newrunner: the run-detail calorie cell renders off a silent 70 kg
 * default with no way to hide it — discouraging for a weight-conscious
 * runner. The universal `show_calories` pref (default ON) now gates the
 * cell; this pins both sides of the gate.
 */
test.describe('show_calories preference', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;
	let savedShowCalories: unknown;

	test.beforeAll(async () => {
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-03-03T08:00:00Z',
			distance_m: 5000,
			duration_s: 1500
		});
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (runId) await admin.from('runs').delete().eq('id', runId);
		// Restore the pref to its pre-test state.
		const { data } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const prefs = { ...((data?.prefs ?? {}) as Record<string, unknown>) };
		if (savedShowCalories === undefined) delete prefs.show_calories;
		else prefs.show_calories = savedShowCalories;
		await admin.from('user_settings').update({ prefs }).eq('user_id', USER_A.id);
	});

	test('calorie stat shows by default and hides when show_calories=false', async ({ page }) => {
		await page.goto(`/runs/${runId}`);
		// Default on: the estimate cell renders (est label — no body weight set).
		await expect(page.getByText(/Calories kcal/)).toBeVisible({ timeout: 10_000 });

		// Flip the universal pref off server-side.
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const prefs = { ...((data?.prefs ?? {}) as Record<string, unknown>) };
		savedShowCalories = prefs.show_calories;
		prefs.show_calories = false;
		await admin.from('user_settings').update({ prefs }).eq('user_id', USER_A.id);

		// Drop the client-side settings cache so the reload reads the server
		// value rather than the cache-first snapshot.
		await page.evaluate(() => {
			for (const k of Object.keys(localStorage)) {
				if (k.startsWith('settings_cache')) localStorage.removeItem(k);
			}
		});
		await page.reload();
		await expect(page.getByText('5.00', { exact: false }).first()).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByText(/Calories kcal/)).toHaveCount(0);
	});
});
