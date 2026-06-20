import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Auto-hide + admin Unhide surface (/admin/reports, migration 20270212_001).
 *
 * The auto-hide TRIGGER + reputation gate are covered at the DB layer by
 * auto_hide_reports_test.sql. This spec pins the ADMIN UX on top:
 *   - a shadow-hidden target shows the Hidden badge in the queue,
 *   - the detail modal exposes an Unhide action,
 *   - confirming it clears shadow_hidden in the DB and drops the badge.
 *
 * USER_A (runner@test.com) is the seeded app_admin; USER_B (alex) is the
 * reported + hidden target. We plant the pending reports AND set
 * shadow_hidden directly via service-role (the trigger's flip is the
 * pgtap subject; here we assert the admin can SEE + REVERT a hidden state),
 * then tear both down.
 */

const REPORTER_ONE = USER_A.id;
const REPORTER_TWO = 'c3d4e5f6-a7b8-9012-cdef-345678901234'; // morgan
const TARGET_ID = USER_B.id; // alex

const plantedReportIds: string[] = [];

async function plantHiddenTarget(targetId: string) {
	const admin = getAdminClient();
	const { data, error } = await admin
		.from('reports')
		.insert([
			{ reporter_id: REPORTER_ONE, target_kind: 'user', target_id: targetId, reason: 'spam', status: 'pending' },
			{ reporter_id: REPORTER_TWO, target_kind: 'user', target_id: targetId, reason: 'harassment', status: 'pending' },
		])
		.select('id');
	if (error) throw error;
	for (const r of data ?? []) plantedReportIds.push(r.id as string);
	const { error: hideErr } = await admin
		.from('user_profiles')
		.update({ shadow_hidden: true })
		.eq('id', targetId);
	if (hideErr) throw hideErr;
}

test.afterEach(async () => {
	const admin = getAdminClient();
	if (plantedReportIds.length > 0) {
		await admin.from('reports').delete().in('id', plantedReportIds);
		plantedReportIds.length = 0;
	}
	// Always restore visibility so a failed run doesn't leave alex hidden.
	await admin.from('user_profiles').update({ shadow_hidden: false }).eq('id', TARGET_ID);
});

test.describe('auto-hide — admin sees the hidden badge and can unhide', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('hidden target badges in the queue; Unhide restores it', async ({ page }) => {
		await plantHiddenTarget(TARGET_ID);

		await page.goto('/admin/reports');

		const row = page
			.getByTestId('admin-queue-row')
			.filter({ hasText: TARGET_ID.slice(0, 8) });
		await expect(row).toBeVisible();
		await expect(row.getByTestId('admin-hidden-badge')).toBeVisible();

		await row.click();

		const modal = page.getByTestId('admin-detail-modal');
		await expect(modal).toBeVisible();
		await expect(modal.getByTestId('admin-hidden-notice')).toBeVisible();

		await modal.getByTestId('admin-unhide').click();
		// ConfirmDialog → confirm.
		await page.getByTestId('admin-unhide-confirm').getByRole('button', { name: /unhide/i }).click();

		// The hidden notice clears in the open modal.
		await expect(modal.getByTestId('admin-hidden-notice')).toHaveCount(0);

		// And the DB reflects the unhide.
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_profiles')
			.select('shadow_hidden')
			.eq('id', TARGET_ID)
			.single();
		expect(data?.shadow_hidden).toBe(false);
	});
});
