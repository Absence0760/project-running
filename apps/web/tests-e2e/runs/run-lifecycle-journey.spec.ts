import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { switchRunsToAllTime } from '../fixtures/helpers';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Run-lifecycle journey — the full cradle-to-grave life of a single
 * run, walked through every surface it touches plus a cross-user
 * social loop. Heavier than runs/list.spec.ts's CRUD round-trip and
 * runs/detail.spec.ts's per-field edit because it threads ONE run id
 * through create → list → detail → edit → cross-user engagement →
 * owner-side verification → delete, exercising the seams between
 * those surfaces rather than any single screen.
 *
 *   1. USER_A creates a PUBLIC run via the /runs Add-run modal
 *      (RunEditor → createManualRun). RunEditor has NO title field —
 *      its single <textarea> is the run NOTES, which createManualRun
 *      writes to metadata.notes (never metadata.title). So the unique
 *      text seeded here lands as the run's notes, and the detail-page
 *      <h1> falls back to the run's date until a title is set in step 4.
 *   2. The new run shows up in the /runs list (All-time filter).
 *   3. /runs/[id] mounts: with no metadata.title the <h1> is the run's
 *      date (runDetail line 1203: `{runTitle || formatDate(...)}`), the
 *      seeded notes render in `.run-notes`, and the stat grid renders.
 *   4. USER_A edits the run inline on /runs/[id], setting a real title.
 *      The inline edit form (NOT the create editor) is the only surface
 *      that writes metadata.title (saveEdit → updateRunMetadata). Once
 *      set, the <h1> becomes the title and persists across a reload.
 *   5. USER_C_PRO (second browser context) opens the public run via
 *      /share/run/[id] — the path a real non-owner takes, since
 *      /runs/[id] is owner-only — and gives kudos + posts a comment
 *      through RunSocial.
 *   6. Back as USER_A, /runs/[id] reflects the engagement: the kudos
 *      count reads 1 and the comment body is visible (RunSocial mounts
 *      for the owner too, read-only kudos).
 *   7. USER_A deletes the run from the detail page (trash icon →
 *      ConfirmDialog); it's gone from /runs. The delete cascades
 *      USER_C_PRO's kudos + comment rows.
 *
 * No rate-limit reset needed: createManualRun has no per-user bucket
 * (only create_club / create_route are throttled, see
 * migration 20260907_001 + resetRateLimit's typed bucket arg).
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('run lifecycle journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('create public → list → detail → edit → cross-user kudos+comment → owner sees it → delete', async ({
		page,
		browser
	}) => {
		const admin = getAdminClient();
		// RunEditor's only textarea is the run NOTES field, not a title —
		// createManualRun stores it in metadata.notes. The title is set
		// later (step 4) via the detail-page inline edit form.
		const createNotes = uniqueText('e2e-run-journey-notes');
		const editedTitle = uniqueText('e2e-run-journey-renamed');
		const commentBody = uniqueText('e2e-journey-comment');

		// Captured from the create redirect so every later surface
		// addresses the SAME run; also drives best-effort teardown.
		let runId = '';

		try {
			// ── 1. Create a PUBLIC run via the /runs Add-run modal ──────
			await test.step('USER_A creates a public run via the Add-run modal', async () => {
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(page.locator('.run-card').first()).toBeVisible({
					timeout: 10_000
				});

				await page.getByRole('button', { name: '+ Add run' }).click();

				// RunEditor (modal): started_at prefills to now; activity
				// defaults to 'run'. Set distance + duration so the row
				// clears the runs CHECK (distance > 0), tick the public
				// toggle. The single <textarea> is the NOTES field
				// (RunEditor.svelte) — fill it with the unique text; it
				// lands as metadata.notes and renders in `.run-notes` on
				// the detail page (a title comes later, in step 4).
				await page
					.locator('input[type="datetime-local"]')
					.first()
					.fill('2026-04-29T08:00');
				await page.locator('input[type="number"]').first().fill('5'); // distance km
				await page.locator('input[type="number"]').nth(1).fill('25'); // duration min
				await page.locator('textarea').fill(createNotes);
				await page
					.getByRole('checkbox', { name: /Make this run public/ })
					.check();

				await page.locator('form button[type="submit"]').click();

				// On success createManualRun redirects to /runs/<new-id>.
				await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
				runId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];

				// Settle the client-side INSERT before the service-role read
				// (no Playwright auto-wait on a raw SELECT).
				await page.waitForLoadState('networkidle');
				const { data: row } = await admin
					.from('runs')
					.select('user_id, is_public')
					.eq('id', runId)
					.single();
				expect(row?.user_id).toBe(USER_A.id);
				expect(row?.is_public).toBe(true);
			});

			// ── 2. It appears in the /runs list ─────────────────────────
			await test.step('the run appears in the /runs list', async () => {
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${runId}"]`)
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 3. /runs/[id] mounts with the notes + stats ─────────────
			await test.step('/runs/[id] renders the notes and stats', async () => {
				await page.goto(`/runs/${runId}`);
				// No metadata.title yet, so the <h1> is the date fallback
				// (`{runTitle || formatDate(run.started_at)}`). Assert the
				// level-1 heading simply exists rather than pinning the
				// locale-formatted date string.
				await expect(
					page.getByRole('heading', { level: 1 })
				).toBeVisible({ timeout: 10_000 });
				// The unique seeded text rendered as the run notes
				// (`.run-notes`, fed by metadata.notes).
				await expect(page.locator('.run-notes')).toHaveText(createNotes, {
					timeout: 10_000
				});
				// The detail stat grid renders at least the distance stat
				// (.key-stat-value is the detail-page class; .run-stat-value
				// is the list card's).
				await expect(
					page.locator('.key-stat-value').first()
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 4. Inline-edit sets the title; persists across reload ───
			await test.step('USER_A sets the title inline and it persists', async () => {
				// The detail-page edit affordance is an icon-button with
				// title="Edit" (runDetail.edit; selecting by accessible
				// name is brittle in Chromium). Its form's `input.edit-input`
				// is the TITLE field — saveEdit() writes it to
				// metadata.title via updateRunMetadata, after which the
				// <h1> derives from runTitle instead of the date fallback.
				await page.locator('button[title="Edit"]').first().click();
				const titleInput = page.locator('input.edit-input');
				await expect(titleInput).toBeVisible({ timeout: 5_000 });
				await titleInput.fill(editedTitle);
				await page.getByRole('button', { name: 'Save', exact: true }).click();
				// saveEdit awaits the network write before closing the form.
				await expect(page.locator('input.edit-input')).toHaveCount(0);

				// Reload — confirms a persisted write, not stale local state.
				await page.reload();
				await expect(
					page.getByRole('heading', { name: editedTitle, level: 1 })
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 5. USER_C_PRO engages via /share/run/[id] ───────────────
			await test.step('USER_C_PRO gives kudos + posts a comment', async () => {
				const ctx = await browser.newContext({
					storageState: USER_C_PRO.storageStatePath
				});
				const guestPage = await ctx.newPage();
				try {
					// The pinned public run has no real track in Storage;
					// stub the clip function so the share page mounts fast.
					await guestPage.route(
						'**/functions/v1/clip-public-track',
						(route) =>
							route.fulfill({
								status: 200,
								contentType: 'application/json',
								body: JSON.stringify({ points: [] })
							})
					);

					await guestPage.goto(`/share/run/${runId}`);

					// Kudos: a non-owner viewer's RunSocial enables the button.
					const kudosBtn = guestPage.locator('.kudos-btn');
					await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
					await expect(kudosBtn).not.toHaveClass(/given/);
					await kudosBtn.click();
					await expect(kudosBtn).toHaveClass(/given/);
					await expect(guestPage.locator('.kudos-count')).toHaveText('1');

					// Comment: post via the composer, wait for the round-trip
					// (textarea clears) + the new comment to render.
					const composer = guestPage.locator('form.composer textarea');
					await expect(composer).toBeVisible({ timeout: 10_000 });
					await composer.fill(commentBody);
					await guestPage
						.locator('form.composer button[type="submit"]')
						.click();
					await expect(composer).toHaveValue('', { timeout: 10_000 });
					await expect(
						guestPage.locator('.comment p').first()
					).toHaveText(commentBody);
					await expect(
						guestPage.locator('.comment-count')
					).toContainText('1 comment');
				} finally {
					await ctx.close();
				}
			});

			// ── 6. USER_A sees the engagement on /runs/[id] ─────────────
			await test.step('USER_A sees the kudos + comment on the run detail', async () => {
				await page.goto(`/runs/${runId}`);
				// RunSocial mounts for the owner too (read-only kudos).
				await expect(page.locator('.kudos-count')).toHaveText('1', {
					timeout: 10_000
				});
				await expect(
					page.locator('.comment p').first()
				).toHaveText(commentBody, { timeout: 10_000 });
				// Backend cross-check: exactly one kudos row from USER_C_PRO.
				const { data: kudosRows } = await admin
					.from('run_kudos')
					.select('user_id')
					.eq('run_id', runId);
				expect(kudosRows?.length ?? 0).toBe(1);
				expect(kudosRows?.[0]?.user_id).toBe(USER_C_PRO.id);
			});

			// ── 7. Delete from the detail page; gone from /runs ─────────
			await test.step('USER_A deletes the run; it disappears from /runs', async () => {
				await page.goto(`/runs/${runId}`);
				await page.locator('button[title="Delete"]').click();
				const dialog = page.locator('.modal');
				await expect(dialog).toBeVisible({ timeout: 5_000 });
				await dialog
					.getByRole('button', { name: 'Delete', exact: true })
					.click();

				// confirmDelete() calls deleteRun + goto('/runs').
				await page.waitForURL(/\/runs(\?.*)?$/, { timeout: 10_000 });
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${runId}"]`)
				).toHaveCount(0);

				// Backend: the row is gone (the delete cascades the guest's
				// kudos + comment rows via FK ON DELETE CASCADE).
				const { data: gone } = await admin
					.from('runs')
					.select('id')
					.eq('id', runId)
					.maybeSingle();
				expect(gone).toBeNull();
				runId = ''; // delete succeeded — no teardown needed.
			});
		} finally {
			// Safety net: if the journey failed before the UI delete, the
			// row (and its cascaded engagement) is swept here.
			if (runId) {
				await admin.from('runs').delete().eq('id', runId);
			}
		}
	});
});
