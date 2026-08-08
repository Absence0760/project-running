import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] Templates tab — Unpublish is a destructive action.
 *
 * The admin Unpublish button fired `setPlanIsTemplate(id, false, null)` on one
 * click: no confirm, no in-flight guard, no busy state. It withdraws the plan
 * from every member's Templates tab, and the sibling "Remove" button for club
 * routes twenty lines above already routed through ConfirmDialog — so this was
 * an inconsistency inside one page, not a considered exception.
 */
const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug] — unpublish a club plan template', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let templateId: string | null = null;
	let templateName = '';

	test.beforeEach(async () => {
		const admin = getAdminClient();
		templateName = `E2E Unpublish Template ${Date.now()}`;
		const { data, error } = await admin
			.from('training_plans')
			.insert({
				user_id: USER_A.id,
				club_id: SYDNEY_RUN_CLUB_ID,
				is_template: true,
				name: templateName,
				goal_event: 'distance_10k',
				goal_distance_m: 10000,
				// training_plans_template_status forbids 'active' on a template,
				// and training_plans_status_check allows only
				// active/completed/abandoned — so 'completed' is the seed value.
				status: 'completed',
				days_per_week: 4,
				start_date: '2026-01-05',
				end_date: '2026-03-01',
			})
			.select('id')
			.single();
		if (error || !data) throw error ?? new Error('seed template failed');
		templateId = data.id as string;
	});

	test.afterEach(async () => {
		if (!templateId) return;
		await getAdminClient().from('training_plans').delete().eq('id', templateId);
		templateId = null;
	});

	async function isStillTemplate(): Promise<boolean> {
		const { data } = await getAdminClient()
			.from('training_plans')
			.select('is_template')
			.eq('id', templateId!)
			.single();
		return (data as { is_template: boolean } | null)?.is_template === true;
	}

	async function clubId(): Promise<string | null> {
		const { data } = await getAdminClient()
			.from('training_plans')
			.select('club_id')
			.eq('id', templateId!)
			.single();
		return (data as { club_id: string | null } | null)?.club_id ?? null;
	}

	test('cancelling the confirm leaves the template published', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Templates/ }).click();

		const row = page.locator('.template-row', { hasText: templateName });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await row.getByTestId('template-unpublish').click();
		const dialog = page.locator('.modal', { hasText: 'Unpublish this template?' });
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);

		expect(await isStillTemplate()).toBe(true);
	});

	test('confirming unpublishes it', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Templates/ }).click();

		const row = page.locator('.template-row', { hasText: templateName });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await row.getByTestId('template-unpublish').click();
		const dialog = page.locator('.modal', { hasText: 'Unpublish this template?' });
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Unpublish' }).click();
		await expect(dialog).toHaveCount(0);

		await expect.poll(isStillTemplate, { timeout: 10_000 }).toBe(false);
		// The club must be released too. Both RLS WITH CHECKs require a
		// club-owned row to be a template, so leaving club_id set made the
		// update satisfy neither policy — it 403'd and the button silently
		// never worked at all.
		expect(await clubId()).toBeNull();
	});
});
