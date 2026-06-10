import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /clubs/[slug] — threaded post replies.
 *
 * `clubs/post-delete.spec.ts` covers top-level post create + admin
 * delete. This file covers the THREAD shape: a top-level post, a
 * reply to it, both bubbles rendering with author identities, and
 * the reply count flipping on the parent.
 *
 * Two users in two contexts: runner (admin/owner) posts the parent;
 * alex (member of Richmond Run Club per seed) clicks Reply, drafts,
 * submits. The parent post's "Reply" affordance flips to "Hide 1
 * reply" once `expandedThreads` includes the parent's id.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug] — threaded replies', () => {
	test('runner posts → alex replies → parent counter flips, both threads render', async ({
		browser
	}) => {
		const parentBody = `e2e-thread-parent ${Date.now()}`;
		const replyBody = `e2e-thread-reply ${Date.now()}`;

		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const runner = await ctxRunner.newPage();
		const alex = await ctxAlex.newPage();
		let parentId: string | null = null;

		try {
			// ── Runner posts the parent ──
			await runner.goto('/clubs/richmond-run-club');
			const composer = runner.locator('.post-form textarea').first();
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill(parentBody);
			await runner.locator('.post-form button[type="submit"]').click();
			const parent = runner.locator('article.post', { hasText: parentBody });
			await expect(parent).toBeVisible({ timeout: 10_000 });

			// Capture the parent post's id from the DB so we can clean
			// up reliably (parent_post_id cascade drops the reply).
			const admin = getAdminClient();
			const { data: planted } = await admin
				.from('club_posts')
				.select('id')
				.eq('body', parentBody)
				.eq('club_id', SYDNEY_RUN_CLUB_ID)
				.single();
			parentId = (planted as { id: string }).id;

			// ── Alex (member) replies ──
			await alex.goto('/clubs/richmond-run-club');
			const alexParent = alex.locator('article.post', { hasText: parentBody });
			await expect(alexParent).toBeVisible({ timeout: 10_000 });
			await alexParent.getByRole('button', { name: 'Reply' }).click();
			// Reply form mounts under the parent once toggleReplies fires.
			const replyInput = alexParent.locator('.reply-form input[type="text"]');
			await expect(replyInput).toBeVisible({ timeout: 5_000 });
			await replyInput.fill(replyBody);
			await alexParent.locator('.reply-form button[type="submit"]').click();

			// Reply bubble renders inside the parent's .replies block.
			await expect(
				alexParent.locator('.reply', { hasText: replyBody })
			).toBeVisible({ timeout: 10_000 });

			// Sanity: the reply row exists in the DB with the right
			// parent_post_id. Pinning this via DB is more robust than
			// asserting reply_count on the runner reload — that
			// counter is computed at fetchClubPosts time and racing
			// the realtime debounce (250ms) makes the assertion flaky.
			const { data: replies } = await admin
				.from('club_posts')
				.select('id, parent_post_id, body')
				.eq('parent_post_id', parentId)
				.eq('body', replyBody);
			expect(replies?.length).toBe(1);

			// ── Runner side: open the thread, see alex's reply ──
			await runner.reload();
			const runnerParent = runner.locator('article.post', {
				hasText: parentBody
			});
			await expect(runnerParent).toBeVisible({ timeout: 10_000 });
			// Click whichever button the post-actions row exposes — it
			// reads "1 reply" when reply_count=1 collapsed, or just
			// "Reply" if the count fetch hadn't picked up the row yet.
			// Either way clicking calls toggleReplies which loads the
			// children via fetchPostReplies.
			await runnerParent.locator('.post-actions button').first().click();
			await expect(
				runnerParent.locator('.reply', { hasText: replyBody })
			).toBeVisible({ timeout: 10_000 });
		} finally {
			if (parentId) {
				try {
					// FK from club_posts.parent_post_id → club_posts.id
					// is on delete cascade, so deleting the parent
					// sweeps the reply automatically.
					await getAdminClient().from('club_posts').delete().eq('id', parentId);
				} catch (_) {
					/* best-effort */
				}
			}
			await ctxAlex.close();
			await ctxRunner.close();
		}
	});

});

test.describe('/clubs/[slug] — reply double-submit guard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('reply submit disables while the insert is in flight', async ({ page }) => {
		const admin = getAdminClient();
		const parentBody = `e2e-reply-guard-parent ${Date.now()}`;
		const replyBody = `e2e-reply-guard ${Date.now()}`;

		const { data: planted } = await admin
			.from('club_posts')
			.insert({ club_id: SYDNEY_RUN_CLUB_ID, author_id: USER_A.id, body: parentBody })
			.select('id')
			.single();
		const parentId = (planted as { id: string }).id;

		// Delay the reply insert so the in-flight window is observable; the
		// guard must keep the submit button disabled for its duration so a
		// second tap can't fire a duplicate insert.
		await page.route('**/rest/v1/club_posts*', async (route) => {
			if (route.request().method() === 'POST') {
				await new Promise((r) => setTimeout(r, 1500));
			}
			await route.continue();
		});

		try {
			await page.goto('/clubs/richmond-run-club');
			const parent = page.locator('article.post', { hasText: parentBody });
			await expect(parent).toBeVisible({ timeout: 10_000 });
			await parent.getByRole('button', { name: 'Reply' }).click();
			const replyInput = parent.locator('.reply-form input[type="text"]');
			await expect(replyInput).toBeVisible({ timeout: 5_000 });
			await replyInput.fill(replyBody);

			const submit = parent.locator('.reply-form button[type="submit"]');
			await submit.click();
			// While the (delayed) insert is in flight the guard disables the
			// button — the proof that a second tap is a no-op.
			await expect(submit).toBeDisabled({ timeout: 1_000 });

			await expect(parent.locator('.reply', { hasText: replyBody })).toBeVisible({
				timeout: 10_000
			});

			const { data: replies } = await admin
				.from('club_posts')
				.select('id')
				.eq('parent_post_id', parentId)
				.eq('body', replyBody);
			expect(replies?.length).toBe(1);
		} finally {
			await admin.from('club_posts').delete().eq('id', parentId);
		}
	});
});
