import { expect, test } from '@playwright/test';

import { deleteRun, insertComment, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * RunSocial comment thread — report affordance (persona round-5 woman).
 *
 * Each comment from another user now carries a small flag action that
 * opens the shared ReportDialog with target_kind 'comment'. The viewer's
 * OWN comments must NOT show the affordance (the backend rejects
 * self-report anyway, but the UI hides it).
 *
 * Scope note: the submit_report RPC accepting target_kind='comment' is a
 * backend change owned separately; this spec pins the WEB affordance —
 * that the flag renders on a non-owned comment, is hidden on the
 * viewer's own, and opens the "Report this comment" dialog. The full
 * submit-and-assert-DB round-trip lands with the backend migration.
 */

test.describe('RunSocial — comment report affordance', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort — run_comments cascades on run delete */
			}
			runId = null;
		}
	});

	test('flag shows on another user comment, hidden on own, opens the report dialog', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		// USER_B's comment — reportable by the viewer (USER_A).
		await insertComment({
			run_id: runId,
			author_id: USER_B.id,
			body: 'e2e-report-target — other runner comment'
		});
		// USER_A's own comment — affordance must be hidden.
		await insertComment({
			run_id: runId,
			author_id: USER_A.id,
			body: 'e2e-report-own — my own comment'
		});

		await page.goto(`/runs/${runId}`);
		const social = page.locator('.run-social');
		await expect(social).toBeVisible({ timeout: 10_000 });

		const otherComment = social.locator('article.comment', {
			hasText: 'e2e-report-target'
		});
		const ownComment = social.locator('article.comment', {
			hasText: 'e2e-report-own'
		});
		await expect(otherComment).toBeVisible({ timeout: 5_000 });
		await expect(ownComment).toBeVisible();

		// Affordance present on the other user's comment, absent on own.
		await expect(otherComment.getByRole('button', { name: 'Report comment' })).toBeVisible();
		await expect(ownComment.getByRole('button', { name: 'Report comment' })).toHaveCount(0);

		// Clicking it opens the shared report dialog scoped to a comment.
		await otherComment.getByRole('button', { name: 'Report comment' }).click();
		const dialog = page.locator('.modal', { hasText: /Report this comment/ });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await expect(dialog.getByRole('button', { name: 'Submit report' })).toBeVisible();
	});
});
