import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	deleteRun,
	insertComment,
	insertKudos,
	insertRun
} from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /runs/[id] — owner-side engagement panel.
 *
 * The cross-user kudos / comments specs cover the WRITER side from the
 * /share/run/[id] page. This pins the READER side from the canonical
 * /runs/[id] detail surface, where RunSocial mounts for the owner with
 * the kudos count + comment list visible (composer + reply controls
 * are gated, but the owner can read engagement and delete comments on
 * their own run).
 *
 * Plant a fresh run + kudos + comment via service-role so the assert
 * works against a known shape (no dependency on which seeded run
 * happens to be the engagement target — that one rotates by date).
 */

test.describe('/runs/[id] — owner-side engagement panel', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				// FK from run_kudos / run_comments → runs cascades on
				// delete, so removing the run sweeps the engagement.
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('owner views own /runs/[id] with seeded kudos + comment from another user', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		await insertKudos(runId, USER_B.id);
		await insertComment({
			run_id: runId,
			author_id: USER_B.id,
			body: 'e2e-owner-social — nice splits!'
		});

		await page.goto(`/runs/${runId}`);

		const social = page.locator('.run-social');
		await expect(social).toBeVisible({ timeout: 10_000 });

		// Kudos count surfaces in the kudos-row.
		await expect(social.locator('.kudos-count')).toHaveText('1');
		// The owner's own kudos button is disabled (you can't kudos
		// your own run) — pin the gating so a regression that flips
		// the disabled state shows up here.
		await expect(social.locator('.kudos-btn')).toBeDisabled();

		// Comment list rendered the planted comment.
		await expect(
			social.locator('article.comment', { hasText: 'e2e-owner-social — nice splits!' })
		).toBeVisible({ timeout: 5_000 });

		// Owner can delete the comment via the per-row × button (the
		// `auth.user?.id === comment.author_id || isOwn` guard exposes
		// the icon-btn). Click it; row disappears.
		await social.getByRole('button', { name: 'Delete comment' }).click();
		await expect(
			social.locator('article.comment', { hasText: 'e2e-owner-social' })
		).toHaveCount(0, { timeout: 5_000 });
	});

	test('owner posts a comment on own run via composer → DB row created with author = owner', async ({
		page
	}) => {
		// The composer is rendered to any logged-in user (only kudos is
		// owner-disabled — see the prior test). Pin that the owner can
		// reply to their own run via the composer and the DB row lands
		// with author_id = owner. A regression that conflated isOwn with
		// "no composer at all" would land here.
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 6_000,
			duration_s: 1_800,
			is_public: true
		});

		const body = `e2e-owner-self-comment ${Date.now()}`;
		await page.goto(`/runs/${runId}`);

		const social = page.locator('.run-social');
		await expect(social).toBeVisible({ timeout: 10_000 });

		const composer = social.locator('form.composer');
		await expect(composer).toBeVisible();
		await composer.locator('textarea').fill(body);
		await composer.getByRole('button', { name: /^Post$/ }).click();

		// New comment article appears in the list.
		await expect(
			social.locator('article.comment', { hasText: body })
		).toBeVisible({ timeout: 10_000 });

		// Backend assertion: author_id is the owner, run_id is right.
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('run_comments')
			.select('id, run_id, author_id, body')
			.eq('run_id', runId)
			.eq('author_id', USER_A.id)
			.single();
		expect(row?.body).toBe(body);
	});
});
