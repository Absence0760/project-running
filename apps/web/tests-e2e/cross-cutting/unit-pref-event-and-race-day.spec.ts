import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Regression net for two surfaces that hardcoded "km" labels before
 * the unit-pref sweep:
 *
 *   1. RaceDayPanel.svelte (mounted on /plans/[id] when end_date is
 *      within 21 days) — split-list labels were `km {i + 1}` instead
 *      of honouring the user's unit pref. The pacing helpers
 *      (`evenSplitPacing`, `negativeSplitPacing`) also defaulted to
 *      per-km splits.
 *   2. EventEditor.svelte (modal on /clubs/[slug] under the admin
 *      "New event" button) — Distance label was hardcoded "(km)" and
 *      Target pace label was hardcoded "(per km)". An mi-mode runner
 *      filling out the form had no idea they were entering kms.
 *
 * Both surfaces now read `getUnit()` and switch their visible labels.
 * On save the EventEditor still posts metres + sec-per-km (the DB
 * shape is unit-agnostic) — the labelled inputs just present the
 * user's preferred unit.
 *
 * Strategy: plant the unit pref via service-role (no UI dance to
 * flip), navigate the page, assert the right labels surface. Reset
 * the pref in afterEach so this spec is hermetic.
 */

test.describe('Unit pref propagation — EventEditor + RaceDayPanel', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		// Reset to the default (km mode) so other specs don't see a
		// dirty pref leaked from this one. Persist both keys the app
		// reads (preferred_unit in the bag + user_profiles row).
		await setUserSetting(USER_A.id, 'preferred_unit', 'km');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'km' })
			.eq('id', USER_A.id);
	});

	test('EventEditor mi-mode: Distance + Target pace labels both read "mi"', async ({
		page
	}) => {
		// Plant mi pref via both surfaces the app reads (units.svelte.ts
		// reads `preferred_unit` from the bag; the auth-store fan-out
		// also touches user_profiles.preferred_unit on the same path).
		await setUserSetting(USER_A.id, 'preferred_unit', 'mi');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'mi' })
			.eq('id', USER_A.id);

		// Navigate to a club USER_A admins. sydney-run-club is seeded
		// with USER_A as admin.
		await page.goto('/clubs/sydney-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Open the New event modal.
		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// The "Distance" label's optional-suffix span should read "mi",
		// not "km". A regression that reverted to hardcoded "km" would
		// fail here.
		const distanceLabel = modal.locator('label', { hasText: 'Distance' });
		await expect(distanceLabel).toBeVisible();
		await expect(distanceLabel.locator('.optional')).toHaveText('mi');

		// "Target pace" label should say "per mi" not "per km".
		const paceLabel = modal.locator('label', { hasText: 'Target pace' });
		await expect(paceLabel).toBeVisible();
		await expect(paceLabel.locator('.optional')).toHaveText('per mi');
	});

	test('EventEditor km-mode: labels read "km" / "per km" (negative-shape)', async ({
		page
	}) => {
		// Belt-and-braces against a regression that flipped the logic
		// inverted (rendered "mi" when pref was km). The afterEach
		// reset hook is what guarantees this test starts in km mode.
		await setUserSetting(USER_A.id, 'preferred_unit', 'km');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'km' })
			.eq('id', USER_A.id);

		await page.goto('/clubs/sydney-run-club');
		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		const distanceLabel = modal.locator('label', { hasText: 'Distance' });
		await expect(distanceLabel.locator('.optional')).toHaveText('km');
		const paceLabel = modal.locator('label', { hasText: 'Target pace' });
		await expect(paceLabel.locator('.optional')).toHaveText('per km');
	});

	test('RaceDayPanel mi-mode: split list labels read "mi N" not "km N"', async ({
		page
	}) => {
		// Plant a plan whose end_date is ~7 days out — that puts it
		// inside the `showRaceDay` gate (<= 21 days). goal_distance_m
		// + goal_time_seconds together drive predictedSec → pacing
		// table. Use distinct values so the rendered split labels are
		// findable.
		await setUserSetting(USER_A.id, 'preferred_unit', 'mi');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'mi' })
			.eq('id', USER_A.id);

		const startDate = new Date();
		const endDate = new Date(Date.now() + 7 * 24 * 3600 * 1000);
		const startIso = startDate.toISOString().slice(0, 10);
		const endIso = endDate.toISOString().slice(0, 10);

		const planId = crypto.randomUUID();
		try {
			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e race-day mi-mode',
				goal_event: 'distance_10k',
				goal_distance_m: 10_000,
				goal_time_seconds: 3000, // 50:00 → ~8:03/mi
				start_date: startIso,
				end_date: endIso,
				status: 'active',
				days_per_week: 4
			});

			await page.goto(`/plans/${planId}`);

			// The RaceDayPanel mounts. Pacing splits show inside .splits
			// > li > .split-km. The first split's label must read "mi 1"
			// (NOT "km 1"). Other splits follow "mi 2", "mi 3", ...
			// 10k @ 50:00 = ~6.21 miles → ceil = 7 splits.
			const splits = page.locator('.splits .split-km');
			await expect(splits.first()).toBeVisible({ timeout: 10_000 });
			await expect(splits.first()).toHaveText('mi 1');
			// Pin a non-first split too — guards a regression that
			// special-cased the first entry but left the rest as km.
			await expect(splits.nth(1)).toHaveText('mi 2');
			// And the negative shape — no "km N" label leaks through.
			await expect(page.locator('.splits .split-km', { hasText: /km \d+/ }))
				.toHaveCount(0);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});

	test('RaceDayPanel km-mode: split list labels read "km N" (negative-shape)', async ({
		page
	}) => {
		// Same surface, default pref. Pins the negative shape so a
		// regression that always emitted "mi" would fail here.
		await setUserSetting(USER_A.id, 'preferred_unit', 'km');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'km' })
			.eq('id', USER_A.id);

		const endIso = new Date(Date.now() + 7 * 24 * 3600 * 1000)
			.toISOString()
			.slice(0, 10);
		const startIso = new Date().toISOString().slice(0, 10);

		const planId = crypto.randomUUID();
		try {
			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e race-day km-mode',
				goal_event: 'distance_10k',
				goal_distance_m: 10_000,
				goal_time_seconds: 3000,
				start_date: startIso,
				end_date: endIso,
				status: 'active',
				days_per_week: 4
			});

			await page.goto(`/plans/${planId}`);

			const splits = page.locator('.splits .split-km');
			await expect(splits.first()).toBeVisible({ timeout: 10_000 });
			await expect(splits.first()).toHaveText('km 1');
			await expect(splits.nth(1)).toHaveText('km 2');
			await expect(page.locator('.splits .split-km', { hasText: /mi \d+/ }))
				.toHaveCount(0);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
