import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Admin moderation surface (/admin/reports, migration 20270104_001).
 *
 * USER_A (runner@test.com) is seeded as an app_admin in seed.sql;
 * USER_B (alex@test.com) is not. The DB is the real authorization
 * boundary — these specs pin the UX layer on top of it:
 *
 *   1. An admin sees the queue, opens a target, and resolves it →
 *      the reports leave the queue.
 *   2. A non-admin sees the not-authorized state and the queue RPC
 *      returns nothing to them.
 *
 * Reports are planted via the service-role client (bypasses the
 * submit_report rate limit + duplicate guard) and torn down after.
 */

// Two distinct reporters (runner + morgan) flag a third user (alex).
const REPORTER_ONE = USER_A.id;
const REPORTER_TWO = 'c3d4e5f6-a7b8-9012-cdef-345678901234'; // morgan
const TARGET_ID = USER_B.id; // alex

const plantedReportIds: string[] = [];

async function plantPendingReports(targetId: string) {
	const admin = getAdminClient();
	const { data, error } = await admin
		.from('reports')
		.insert([
			{ reporter_id: REPORTER_ONE, target_kind: 'user', target_id: targetId, reason: 'spam', notes: 'spammy dms', status: 'pending' },
			{ reporter_id: REPORTER_TWO, target_kind: 'user', target_id: targetId, reason: 'harassment', status: 'pending' },
		])
		.select('id');
	if (error) throw error;
	for (const r of data ?? []) plantedReportIds.push(r.id as string);
}

test.afterEach(async () => {
	if (plantedReportIds.length === 0) return;
	const admin = getAdminClient();
	await admin.from('reports').delete().in('id', plantedReportIds);
	plantedReportIds.length = 0;
});

test.describe('admin moderation — admin can triage the queue', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('admin sees the queue, resolves a target → it leaves the queue', async ({ page }) => {
		await plantPendingReports(TARGET_ID);

		await page.goto('/admin/reports');

		const row = page
			.getByTestId('admin-queue-row')
			.filter({ hasText: TARGET_ID.slice(0, 8) });
		await expect(row).toBeVisible();
		await expect(row).toContainText('2'); // two reports

		await row.click();

		const modal = page.getByTestId('admin-detail-modal');
		await expect(modal).toBeVisible();
		// Both individual reports show (reason chips, exact so the
		// "spammy dms" notes line doesn't also match "spam").
		await expect(modal.getByText('spam', { exact: true })).toBeVisible();
		await expect(modal.getByText('harassment', { exact: true })).toBeVisible();

		await modal.getByTestId('admin-resolution-input').fill('warned the user');
		await modal.getByTestId('admin-mark-reviewed').click();

		// ConfirmDialog → confirm.
		await page.getByTestId('admin-resolve-confirm').getByRole('button', { name: /reviewed/i }).click();

		// The target leaves the queue.
		await expect(
			page.getByTestId('admin-queue-row').filter({ hasText: TARGET_ID.slice(0, 8) }),
		).toHaveCount(0);

		// And the DB reflects the resolution.
		const admin = getAdminClient();
		const { data } = await admin
			.from('reports')
			.select('status, reviewed_by, resolution')
			.in('id', plantedReportIds);
		for (const r of data ?? []) {
			expect(r.status).toBe('reviewed');
			expect(r.reviewed_by).toBe(USER_A.id);
			expect(r.resolution).toBe('warned the user');
		}
	});
});

test.describe('admin moderation — non-admin is locked out', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('non-admin sees the not-authorized state and no report data leaks', async ({ page }) => {
		await plantPendingReports(TARGET_ID);

		await page.goto('/admin/reports');

		// Chrome gate (am_i_admin → false) renders the locked-out state.
		await expect(page.getByTestId('admin-not-authorized')).toBeVisible();
		// The queue never renders, and no planted target id leaks into the DOM —
		// the server-side 42501 on fetch_pending_reports is the real boundary
		// (also pinned by admin_moderation_test.sql), so a non-admin sees nothing.
		await expect(page.getByTestId('admin-queue')).toHaveCount(0);
		await expect(page.getByTestId('admin-queue-row')).toHaveCount(0);
		await expect(page.getByText(TARGET_ID.slice(0, 8))).toHaveCount(0);
	});
});
