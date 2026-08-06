import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /nutrition/targets — the calorie + macro targets peer of the Nutrition
 * surface (docs/features/multi_modal.md § Nutrition: "each modality owns its
 * planning assets ... nutrition owns targets/recipes").
 *
 * Before this route the targets were visible on /nutrition as ring
 * denominators but reachable nowhere: the only editor was a card partway down
 * /settings/preferences, and /nutrition's untargeted state named it in prose
 * without linking it. Both specs below pin the reachability, not the
 * arithmetic — nutrition_targets.test.ts owns the numbers.
 *
 * USER_A is seeded with height / DOB / gender / weight, so the derivation
 * renders; USER_B has none of them, so the same route renders the empty state
 * and the CTA that leads out of it.
 */
test.describe('/nutrition/targets — reachable, derived, editable', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// The weight-goal edit writes a universal pref other specs read as a
	// calorie denominator, so put it back however this test ends.
	test.afterEach(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const prefs = { ...((data?.prefs as Record<string, unknown>) ?? {}), nutrition_goal: 'maintain' };
		await admin.from('user_settings').update({ prefs }).eq('user_id', USER_A.id);
	});

	test('header link → derivation + macros + a route back to the Art 9 editor', async ({ page }) => {
		await page.goto('/nutrition');

		// The peer is one click from the day view, and present regardless of data.
		const link = page.getByTestId('nutrition-targets-link');
		await expect(link).toBeVisible();
		await link.click();
		await expect(page).toHaveURL(/\/nutrition\/targets$/);

		// The goal is shown with the terms it was derived from, not just as a
		// denominator: BMR, the activity factor, the goal delta, the base.
		const goal = page.getByTestId('targets-goal');
		await expect(goal).toBeVisible();
		await expect(goal.locator('.goal-total')).toContainText('kcal');
		await expect(goal).toContainText('Resting metabolism');
		await expect(goal).toContainText('Base goal');
		await expect(page.getByTestId('targets-macros')).toBeVisible();

		// Body metrics are shown read-only — the consent-gated editor stays in
		// Settings, and this is the route to it.
		const metrics = page.getByTestId('targets-metrics');
		await expect(metrics).toContainText('178');
		await expect(metrics.locator('input')).toHaveCount(0);
		await page.getByTestId('targets-edit-metrics').click();
		await expect(page).toHaveURL(/\/settings\/preferences#body-metrics$/);
		await expect(page.locator('#body-metrics')).toBeVisible();
		await expect(page.getByTestId('height-cm')).toBeVisible();
	});

	test('changing the weight goal moves the target and persists', async ({ page }) => {
		await page.goto('/nutrition/targets');

		const total = page.getByTestId('targets-goal').locator('.goal-total');
		await expect(total).toContainText('kcal');
		const before = Number((await total.innerText()).replace(/[^0-9]/g, ''));
		expect(before).toBeGreaterThan(0);

		// lose = −500 kcal on the base (GOAL_KCAL_DELTA), so the shown eat-to
		// goal must drop — and it must survive a reload, i.e. it was saved.
		await page.getByTestId('targets-weight-goal').selectOption('lose');
		await expect
			.poll(async () => Number((await total.innerText()).replace(/[^0-9]/g, '')))
			.toBeLessThan(before);

		await page.reload();
		await expect(page.getByTestId('targets-weight-goal')).toHaveValue('lose');
		const after = Number(
			(await page.getByTestId('targets-goal').locator('.goal-total').innerText()).replace(
				/[^0-9]/g,
				'',
			),
		);
		expect(after).toBeLessThan(before);
	});
});

test.describe('/nutrition/targets — no body metrics yet', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('both surfaces route the user to the editor instead of naming it', async ({ page }) => {
		await page.goto('/nutrition');

		// The untargeted rings state carries a button, not just a sentence —
		// the half of the finding mobile closed first.
		const noTargets = page.getByTestId('no-targets');
		await expect(noTargets).toBeVisible();
		await expect(page.getByTestId('add-body-metrics')).toHaveAttribute(
			'href',
			'/settings/preferences#body-metrics',
		);

		// The peer is reachable with no targets set — that user needs it most.
		await page.getByTestId('nutrition-targets-link').click();
		await expect(page).toHaveURL(/\/nutrition\/targets$/);
		await expect(page.getByTestId('targets-empty')).toBeVisible();
		await expect(page.getByTestId('targets-goal')).toHaveCount(0);
		await expect(page.getByTestId('targets-empty-cta')).toHaveAttribute(
			'href',
			'/settings/preferences#body-metrics',
		);

		// The two non-sensitive levers are still editable with no metrics set.
		await expect(page.getByTestId('targets-activity-level')).toBeVisible();
	});
});
