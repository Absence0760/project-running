import { expect, test } from '@playwright/test';

import { getAdminClient } from '../../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../../fixtures/seeded-data';
import { clearNotifications } from '../../fixtures/simulate';
import { USER_A, USER_B } from '../../fixtures/users';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/**
 * Cross-user comment saga: USER_B (alex) posts a top-level comment on
 * USER_A's public run via the /share/run/[id] composer. The
 * `notify_run_comment` trigger fans out to USER_A. The inbox at
 * /u/[me]?tab=notifications surfaces the row with the comment preview
 * + a click-through to the run detail page where the comment is
 * visible.
 *
 * The bell-popover surface is pinned in cross-user/notifications.spec.ts.
 * This saga differs by exercising the *UI* writer path (composer
 * submission) and the full inbox page render with preview text.
 */

test.describe('saga: alex comments runner → runner inbox row + bell + click-through to comment', () => {
	test.describe.configure({ timeout: 90_000 });

	const commentBody = `alex e2e comment ${Date.now()}`;

	test.beforeEach(async () => {
		await clearNotifications(USER_A.id);
	});

	test.afterEach(async () => {
		// The UI test deletes its own comment via the trash button; this
		// safety net catches a mid-test failure that leaves the row.
		const admin = getAdminClient();
		await admin
			.from('run_comments')
			.delete()
			.eq('run_id', RUNNER_PUBLIC_RUN_ID)
			.eq('author_id', USER_B.id)
			.eq('body', commentBody);
		await clearNotifications(USER_A.id);
	});

	test('inbox row carries the comment preview + click navigates to the run', async ({
		browser
	}) => {
		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		await ctxAlex.addInitScript(setConsentAccepted);
		await ctxRunner.addInitScript(setConsentAccepted);
		const alex = await ctxAlex.newPage();
		const runner = await ctxRunner.newPage();

		try {
			await alex.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			await alex.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const composer = alex.locator('form.composer textarea');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill(commentBody);
			await alex.locator('form.composer button[type="submit"]').click();
			await expect(composer).toHaveValue('', { timeout: 10_000 });

			await runner.goto(`/u/${USER_A.id}?tab=notifications`);
			await expect(runner.getByRole('heading', { level: 1 })).toBeVisible({
				timeout: 10_000
			});

			const row = runner
				.locator('.item-wrap')
				.filter({ hasText: /Alex Chen commented on your 9\.0 km/ });
			await expect(row).toBeVisible({ timeout: 10_000 });
			await expect(row).toHaveClass(/unread/);
			await expect(row.locator('.excerpt')).toContainText(commentBody);

			const badge = runner.locator('.bell-wrap .badge');
			await expect(badge).toBeVisible({ timeout: 5_000 });
			await expect(badge).toHaveText('1');

			await row.locator('.item-main').click();
			await runner.waitForURL(`**/runs/${RUNNER_PUBLIC_RUN_ID}`, {
				timeout: 10_000
			});
			// Owner-only /runs/[id] renders the comment under .comment p.
			await expect(
				runner.locator('.comment p').filter({ hasText: commentBody })
			).toBeVisible({ timeout: 10_000 });
		} finally {
			// Alex cleans up the comment so the seed state survives.
			await alex.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const deleteBtn = alex
				.locator('article.comment')
				.filter({ has: alex.locator('p', { hasText: commentBody }) })
				.getByRole('button', { name: 'Delete comment' });
			if (await deleteBtn.count()) {
				await deleteBtn.click();
			}
			await ctxAlex.close();
			await ctxRunner.close();
		}
	});
});
