import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * E2 — report affordance on club posts + runs.
 *
 * submit_report now accepts target_kind in ('club_post','run') as well as
 * the existing user/club/route/comment (migration 20270115_001). This
 * spec pins the WEB affordances:
 *
 *   * a non-author viewer sees a "Report this post" flag on a club post,
 *     the author does not, and the flag opens the "Report this post" dialog;
 *   * a logged-in non-owner sees a "Report run" action on a public run's
 *     share view, and it opens the "Report this run" dialog.
 *
 * Richmond Run Club (seed slug `richmond-run-club`) is owned by USER_A;
 * USER_B (alex) is a member. So USER_B authors a post that USER_A can
 * report; USER_B viewing their own post sees no flag.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('E2 — report affordance on club posts + runs', () => {
	test('club post: flag shows for non-author, hidden for author, opens dialog', async ({
		browser
	}) => {
		const body = `e2e-report-post ${Date.now()}`;
		const ctxAuthor = await browser.newContext({ storageState: USER_B.storageStatePath });
		const ctxViewer = await browser.newContext({ storageState: USER_A.storageStatePath });
		const author = await ctxAuthor.newPage();
		const viewer = await ctxViewer.newPage();
		let postId: string | null = null;

		try {
			await author.goto('/clubs/richmond-run-club');
			const composer = author.locator('.post-form textarea').first();
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill(body);
			await author.locator('.post-form button[type="submit"]').click();
			const ownPost = author.locator('article.post', { hasText: body });
			await expect(ownPost).toBeVisible({ timeout: 10_000 });

			// Author must NOT see the report flag on their own post.
			await expect(ownPost.getByRole('button', { name: 'Report this post' })).toHaveCount(0);

			const admin = getAdminClient();
			const { data: planted } = await admin
				.from('club_posts')
				.select('id')
				.eq('body', body)
				.eq('club_id', RICHMOND_CLUB_ID)
				.single();
			postId = (planted as { id: string }).id;

			// Non-author viewer sees the flag and it opens the report dialog.
			await viewer.goto('/clubs/richmond-run-club');
			const otherPost = viewer.locator('article.post', { hasText: body });
			await expect(otherPost).toBeVisible({ timeout: 10_000 });
			const flag = otherPost.getByRole('button', { name: 'Report this post' });
			await expect(flag).toBeVisible({ timeout: 5_000 });
			await flag.click();
			const dialog = viewer.locator('.modal', { hasText: /Report this post/ });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await expect(dialog.getByRole('button', { name: 'Submit report' })).toBeVisible();
		} finally {
			if (postId) {
				const admin = getAdminClient();
				await admin.from('club_posts').delete().eq('id', postId);
			}
			await ctxAuthor.close();
			await ctxViewer.close();
		}
	});

	test('run share view: non-owner sees Report run, opens dialog', async ({ browser }) => {
		const ctxViewer = await browser.newContext({ storageState: USER_B.storageStatePath });
		const viewer = await ctxViewer.newPage();
		let runId: string | null = null;

		try {
			// USER_A owns a public run; USER_B (a different signed-in user)
			// views the share surface and can report it.
			runId = await insertRun({
				user_id: USER_A.id,
				distance_m: 5_000,
				duration_s: 1_500,
				is_public: true
			});

			await viewer.goto(`/share/run/${runId}`);
			const flag = viewer.getByRole('button', { name: 'Report run' });
			await expect(flag).toBeVisible({ timeout: 10_000 });
			await flag.click();
			const dialog = viewer.locator('.modal', { hasText: /Report this run/ });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await expect(dialog.getByRole('button', { name: 'Submit report' })).toBeVisible();
		} finally {
			if (runId) {
				try {
					await deleteRun(runId);
				} catch (_) {
					/* best-effort */
				}
			}
			await ctxViewer.close();
		}
	});
});
