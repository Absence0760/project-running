import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Accessibility guard for the per-comment report/delete icon buttons in
 * RunSocial. Both controls share the `.icon-btn` rule, which was raised
 * to a >=44x44 CSS px hit area (Material tap-target / WCAG 2.2 SC 2.5.8)
 * to match the mobile twin (commit 5b030321). This pins that the
 * clickable box actually measures at least 44x44, so a low-dexterity
 * runner on the web app can't fat-finger a report/delete.
 *
 * USER_B (alex) posts a comment on USER_A's public run, then USER_A —
 * the run OWNER — views it. On someone else's comment the run owner sees
 * BOTH the report flag (not the author) AND the delete close button
 * (owns the run), so a single comment surfaces both `.icon-btn` uses.
 */

const MIN_TAP = 44;

test.describe('comment report/delete icon buttons meet the 44px tap-target minimum', () => {
	test.describe.configure({ timeout: 90_000 });

	const commentBody = `a11y-tap-target ${Date.now()}-${Math.random()
		.toString(36)
		.slice(2, 6)}`;

	test.afterEach(async () => {
		// Backstop the in-test UI delete in case of a mid-test failure.
		const admin = getAdminClient();
		await admin
			.from('run_comments')
			.delete()
			.eq('run_id', RUNNER_PUBLIC_RUN_ID)
			.eq('author_id', USER_B.id)
			.eq('body', commentBody);
	});

	test('report flag + delete close are each at least 44x44', async ({
		browser
	}) => {
		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const alex = await ctxAlex.newPage();
		const runner = await ctxRunner.newPage();

		try {
			// Alex posts the comment on runner's public run.
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

			// Runner (the run owner) views the comment — sees both icons.
			await runner.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
			const article = runner
				.locator('article.comment')
				.filter({ has: runner.locator('p', { hasText: commentBody }) });
			await expect(article).toBeVisible({ timeout: 10_000 });

			const reportBtn = article.getByRole('button', {
				name: 'Report comment'
			});
			const deleteBtn = article.getByRole('button', {
				name: 'Delete comment'
			});
			await expect(reportBtn).toBeVisible();
			await expect(deleteBtn).toBeVisible();

			const reportBox = await reportBtn.boundingBox();
			const deleteBox = await deleteBtn.boundingBox();
			expect(reportBox).not.toBeNull();
			expect(deleteBox).not.toBeNull();
			expect(reportBox!.width).toBeGreaterThanOrEqual(MIN_TAP);
			expect(reportBox!.height).toBeGreaterThanOrEqual(MIN_TAP);
			expect(deleteBox!.width).toBeGreaterThanOrEqual(MIN_TAP);
			expect(deleteBox!.height).toBeGreaterThanOrEqual(MIN_TAP);

			// Owner cleans up the comment so the seed state survives. The
			// per-row close opens a ConfirmDialog (mis-tap guard); confirm it.
			await deleteBtn.click();
			const confirm = runner.locator('.modal', {
				hasText: 'Delete this comment?'
			});
			await expect(confirm).toBeVisible({ timeout: 5_000 });
			await confirm.getByRole('button', { name: 'Delete comment' }).click();
			await expect(article).toHaveCount(0, { timeout: 5_000 });
		} finally {
			await ctxAlex.close();
			await ctxRunner.close();
		}
	});
});
