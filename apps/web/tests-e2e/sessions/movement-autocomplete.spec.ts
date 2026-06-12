import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Session planner P3 (session_planner.md) — movement-name autocomplete in the
 * editor, sourced from the user's prior session_plan_items movement names
 * (mirrors the gym exercise-name datalist). Seeds a plan with a distinctive
 * movement, opens the New-session editor, and asserts the datalist carries the
 * prior movement so the free-text input offers it as a suggestion.
 */

test.describe('/sessions — movement-name autocomplete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let seedPlanId: string | null = null;
	const movement = `E2E Pose ${Date.now()}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title: `autocomplete src ${Date.now()}` })
			.select('id')
			.single();
		seedPlanId = (data as { id: string }).id;
		await admin
			.from('session_plan_items')
			.insert({ plan_id: seedPlanId, position: 0, movement_name: movement, kind: 'hold', duration_s: 30 });
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (seedPlanId) await admin.from('session_plans').delete().eq('id', seedPlanId);
	});

	test('the editor datalist offers a prior movement name', async ({ page }) => {
		await page.goto('/sessions');
		await page.getByRole('button', { name: 'New session' }).click();
		const modal = page.locator('.modal', { hasText: 'New session' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// The movement input is wired to the suggestions datalist, and the
		// datalist is populated from the user's prior session_plan_items.
		await expect(modal.getByLabel('Movement').first()).toHaveAttribute(
			'list',
			'session-movement-suggestions'
		);
		const option = page.locator(
			`#session-movement-suggestions option[value="${movement}"]`
		);
		await expect(option).toHaveCount(1, { timeout: 5_000 });
	});
});
