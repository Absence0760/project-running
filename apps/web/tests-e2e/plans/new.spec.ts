import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan, setPlanStatus } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /plans/new — the standalone wizard route.
 *
 * The /plans modal-hosted wizard is covered by plans/create.spec.ts.
 * This file pins the standalone /plans/new path: page chrome, the
 * editable week-by-week preview (click a week → tweak a workout →
 * save → workout persisted), and cancel-with-discarded-state.
 *
 * Both surfaces mount the same PlanEditor component but the
 * standalone route adds the polished header + back-link + a template
 * cloner; a regression on the wrapper page can break those without
 * breaking the modal flow.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('/plans/new — standalone wizard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedPlanId: string | null = null;

	test.afterEach(async () => {
		if (plantedPlanId) {
			try {
				await deletePlan(plantedPlanId);
			} catch (_) {
				/* best-effort */
			}
			plantedPlanId = null;
		}
		try {
			await setPlanStatus(SEED_PLAN_ID, 'active');
		} catch (_) {
			/* best-effort */
		}
	});

	test('page chrome renders: kicker + h1 + tagline + back-link', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Build a training plan' }))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.kicker')).toHaveText(/New plan/i);
		await expect(page.locator('.tagline')).toContainText(/Pick a goal race/i);
		await expect(page.getByRole('link', { name: /Back to plans/ })).toBeVisible();
		await expect(page.locator('.plan-editor')).toBeVisible({ timeout: 5_000 });
	});

	test('fill wizard → Replace-plan confirm → land on /plans/<new-id>; DB invariants honoured', async ({
		page
	}) => {
		const name = `e2e-new-plan ${Date.now()}`;

		await page.goto('/plans/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Build a training plan' }))
			.toBeVisible({ timeout: 10_000 });

		const editor = page.locator('.plan-editor');
		await editor.getByPlaceholder('Autumn half marathon').fill(name);
		await editor.locator('select').first().selectOption('distance_half');

		const start = new Date(Date.now() + 21 * 24 * 3600 * 1000);
		const isoDate = start.toISOString().slice(0, 10);
		await editor.locator('input[type="date"]').first().fill(isoDate);

		const submit = editor.getByRole('button', { name: /Create plan/ });
		await expect(submit).toBeEnabled({ timeout: 5_000 });
		await submit.click();

		const replace = page.locator('.modal.modal-narrow', {
			hasText: /Replace your active plan/
		});
		await expect(replace).toBeVisible({ timeout: 5_000 });
		await expect(replace).toContainText('Richmond Half 2026');
		await replace.getByRole('button', { name: 'Replace plan' }).click();

		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
		plantedPlanId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];

		await expect(page.getByRole('heading', { level: 1, name }))
			.toBeVisible({ timeout: 10_000 });

		const admin = getAdminClient();
		const { data: newRow } = await admin
			.from('training_plans')
			.select('id, name, status, is_template')
			.eq('id', plantedPlanId)
			.single();
		expect(newRow).not.toBeNull();
		expect(newRow!.name).toBe(name);
		expect(newRow!.status).toBe('active');
		expect(newRow!.is_template).toBe(false);

		const { data: oldRow } = await admin
			.from('training_plans')
			.select('status')
			.eq('id', SEED_PLAN_ID)
			.single();
		expect(oldRow!.status).toBe('completed');
	});

	test('edit a week before save → workout distance persists on detail page', async ({ page }) => {
		const name = `e2e-edit-week ${Date.now()}`;

		await page.goto('/plans/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Build a training plan' }))
			.toBeVisible({ timeout: 10_000 });

		const editor = page.locator('.plan-editor');
		await editor.getByPlaceholder('Autumn half marathon').fill(name);
		await editor.locator('select').first().selectOption('distance_5k');

		const start = new Date(Date.now() + 14 * 24 * 3600 * 1000);
		await editor.locator('input[type="date"]').first().fill(start.toISOString().slice(0, 10));

		await expect(editor.locator('.weeks .week-item').first()).toBeVisible({ timeout: 5_000 });

		// Expand week 1 — the .week-row button toggles `expandedWeek`.
		const firstWeek = editor.locator('.week-item').first();
		await firstWeek.locator('.week-row').click();
		await expect(firstWeek.locator('.week-editor')).toBeVisible({ timeout: 5_000 });

		// Find the first non-rest workout (its distance input is enabled)
		// and pin a distinctive value. Distance unit on the seed user is
		// km, so 9.5 km is what the editor binds + what fmtKm(2) renders
		// to "9.50 km" on /plans/[id]/workouts/[wid].
		const distanceInputs = firstWeek.locator('input[type="number"]');
		const count = await distanceInputs.count();
		let edited = false;
		for (let i = 0; i < count; i++) {
			const inp = distanceInputs.nth(i);
			if (await inp.isDisabled()) continue;
			await inp.fill('9.5');
			edited = true;
			break;
		}
		expect(edited).toBe(true);

		const submit = editor.getByRole('button', { name: /Create plan/ });
		await expect(submit).toBeEnabled();
		await submit.click();

		const replace = page.locator('.modal.modal-narrow', {
			hasText: /Replace your active plan/
		});
		await expect(replace).toBeVisible({ timeout: 5_000 });
		await replace.getByRole('button', { name: 'Replace plan' }).click();

		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
		plantedPlanId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];

		const admin = getAdminClient();
		const weekIds =
			(
				await admin
					.from('plan_weeks')
					.select('id')
					.eq('plan_id', plantedPlanId)
			).data?.map((w) => w.id) ?? [];
		const { data: persisted } = await admin
			.from('plan_workouts')
			.select('id, target_distance_m, kind')
			.in('week_id', weekIds)
			.eq('target_distance_m', 9500);
		expect((persisted ?? []).length).toBeGreaterThan(0);
	});

	test('cancel mid-wizard via back-link discards the in-flight plan', async ({ page }) => {
		const name = `e2e-cancel ${Date.now()}`;

		await page.goto('/plans/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Build a training plan' }))
			.toBeVisible({ timeout: 10_000 });

		await page.locator('.plan-editor').getByPlaceholder('Autumn half marathon').fill(name);

		await page.getByRole('link', { name: /Back to plans/ }).click();
		await page.waitForURL(/\/plans(\?|$)/, { timeout: 5_000 });

		const admin = getAdminClient();
		const { data: leaked } = await admin
			.from('training_plans')
			.select('id')
			.eq('user_id', USER_A.id)
			.eq('name', name);
		expect(leaked ?? []).toHaveLength(0);
	});
});
