import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_B } from '../fixtures/users';

/**
 * Cross-user comment flows on /share/run/[id]. The pinned public run
 * starts with zero comments by design (the `id != '...'` filter in
 * seed.sql exempts it from the cross-user-engagement seeds).
 *
 * Future depth: long-comment truncation + "see more" toggle, edit-
 * own-comment, run-owner deletes a non-owner comment, comment count
 * visible to anon viewers, comment-reply kudos.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('cross-user comments', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('alex posts top-level comment, reload persists, delete', async ({
		page
	}) => {
		const body = uniqueText('e2e-comment');

		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Wait for the auth-gated RunSocial to mount.
		const composer = page.locator('form.composer textarea');
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.comment-count')).toContainText('0 comments');

		// Post the comment.
		await composer.fill(body);
		await page.locator('form.composer button[type="submit"]').click();

		// `submitComment` awaits postRunComment and re-loads — once the
		// composer textarea clears we know the round-trip resolved.
		await expect(composer).toHaveValue('', { timeout: 10_000 });
		await expect(page.locator('.comment p').first()).toHaveText(body);
		await expect(page.locator('.comment-count')).toContainText('1 comment');

		// Reload to confirm the write actually hit Supabase, not just
		// optimistic local state.
		await page.reload();
		await expect(page.locator('.comment p').first()).toHaveText(body, {
			timeout: 10_000
		});

		// Delete (rescind), so the spec is idempotent across runs.
		await page.getByRole('button', { name: 'Delete comment' }).first().click();
		await expect(page.locator('.comment')).toHaveCount(0);
		await expect(page.locator('.comment-count')).toContainText('0 comments');
	});

	test('alex posts comment + replies to it (nested write); parent delete cascades', async ({
		page
	}) => {
		// `parent_comment_id` references run_comments(id) ON DELETE
		// CASCADE (migration 20260522_001), so deleting the parent
		// removes the reply too. Nested write goes through the same
		// `postRunComment` helper with `parent_comment_id` set —
		// regression risk is a UI form binding that drops the parent
		// id, leaving the reply orphaned at the top level.
		const parentBody = uniqueText('e2e-parent');
		const replyBody = uniqueText('e2e-reply');

		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Post the parent comment.
		const composer = page.locator('form.composer textarea');
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill(parentBody);
		await page.locator('form.composer button[type="submit"]').click();
		await expect(composer).toHaveValue('', { timeout: 10_000 });

		// Locate the new comment by its body — `.comment` article with
		// the matching <p>. The Reply trigger is a `.link-btn` inside
		// the same article.
		const parentArticle = page
			.locator('article.comment')
			.filter({ has: page.locator('p', { hasText: parentBody }) });
		await expect(parentArticle).toBeVisible();

		// Click "Reply" inside that article to open the inline form.
		await parentArticle.getByRole('button', { name: 'Reply', exact: true }).click();
		const replyInput = parentArticle.locator('form.reply-form input');
		await expect(replyInput).toBeVisible();
		await replyInput.fill(replyBody);
		await parentArticle
			.locator('form.reply-form button[type="submit"]')
			.click();

		// After submit: reply appears under .replies inside the parent
		// article, and the form closes.
		await expect(replyInput).toHaveCount(0, { timeout: 10_000 });
		const replyP = parentArticle.locator('.replies .reply p', {
			hasText: replyBody
		});
		await expect(replyP).toBeVisible();

		// Cleanup: deleting the parent cascades the reply.
		await parentArticle
			.getByRole('button', { name: 'Delete comment' })
			.click();
		await expect(
			page.locator('article.comment', {
				has: page.locator('p', { hasText: parentBody })
			})
		).toHaveCount(0, { timeout: 5_000 });
	});
});
