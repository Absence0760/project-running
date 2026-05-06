import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — owner-only run detail page.
 *
 * Operations covered: render, inline edit Save, inline edit Cancel.
 * The cross-user-isolation case (User A cannot see User B's private
 * run) is in cross-cutting/auth-walls.spec.ts. The kudos / comment
 * surfaces are reachable from /share/run/ for non-owners — those
 * tests live under cross-user/ and share/.
 *
 * Future depth here: photos upload + delete, segment-effort chip
 * generation, share-link copy, manual workout-mark-done from a plan.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/runs/[id]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('mounts with the seeded run title as h1', async ({ page }) => {
		// Use the pinned runner public run so this test is deterministic.
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		// Run-detail fetches the row + (lazily) the track via Storage.
		// networkidle guarantees those settle before we assert.
		await page.waitForLoadState('networkidle');

		// Title is the metadata.title we seeded. If the run loaded, the
		// h1 reflects it. We don't assert the map mounts — the seeded
		// run has no track in Storage so RunMap never renders. The
		// inline-edit tests below cover track-less runs adequately.
		await expect(
			page.getByRole('heading', { name: 'E2E demo public run', level: 1 })
		).toBeVisible();
	});

	test('inline edit title — save persists across reload, restore', async ({
		page
	}) => {
		const newTitle = uniqueText('renamed');
		const originalTitle = 'E2E demo public run';

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Open the inline editor. The Edit button is an .icon-btn with
		// title="Edit"; selecting by accessible name is more brittle
		// because the title attribute isn't always exposed as the
		// accessible name in Chromium. Use the exact title.
		await page.locator('button[title="Edit"]').first().click();

		// editTitle prefills with the current title — clear + replace.
		const titleInput = page.locator('input.edit-input');
		await titleInput.fill(newTitle);
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		// `saveEdit` awaits the network call before flipping
		// `editing = false`; wait for the form to close so the reload
		// below sees a persisted state, not in-flight optimistic UI.
		await expect(page.locator('input.edit-input')).toHaveCount(0);

		// Reload to confirm persistence — not a stale local state.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(
			page.getByRole('heading', { name: newTitle, level: 1 })
		).toBeVisible();

		// Restore so the spec is idempotent.
		await page.locator('button[title="Edit"]').first().click();
		await page.locator('input.edit-input').fill(originalTitle);
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('input.edit-input')).toHaveCount(0);
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();
	});

	test('inline edit notes — save persists across reload, restore', async ({
		page
	}) => {
		// Companion to the title test: same updateRunMetadata path,
		// different field. The metadata jsonb merge has independent
		// risks per key — a save that drops the notes field would
		// pass the title test but fail this one.
		const newNotes = uniqueText('e2e-notes');

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// The pinned public run has no seeded notes — the .run-notes
		// paragraph is absent. Open the editor.
		await page.locator('button[title="Edit"]').first().click();
		const notesArea = page.locator('textarea.edit-textarea');
		await expect(notesArea).toBeVisible();
		await notesArea.fill(newNotes);
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('input.edit-input')).toHaveCount(0);

		// Reload — notes must persist via the metadata jsonb.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('p.run-notes')).toHaveText(newNotes, {
			timeout: 10_000
		});

		// Restore to empty notes so the seed shape is preserved.
		await page.locator('button[title="Edit"]').first().click();
		await page.locator('textarea.edit-textarea').fill('');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('input.edit-input')).toHaveCount(0);
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('p.run-notes')).toHaveCount(0);
	});

	test('inline edit title — Cancel reverts unsaved changes', async ({
		page
	}) => {
		// Companion to the Save test above. Catches a regression where
		// Cancel accidentally writes (e.g. a refactor wiring Save and
		// Cancel to the same handler).
		const originalTitle = 'E2E demo public run';
		const draft = uniqueText('e2e-cancel-draft');

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Confirm starting state.
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible({ timeout: 10_000 });

		await page.locator('button[title="Edit"]').first().click();
		await page.locator('input.edit-input').fill(draft);
		await page.getByRole('button', { name: 'Cancel', exact: true }).click();

		// Editor closes immediately and the heading reads the original
		// title — no save fired.
		await expect(page.locator('input.edit-input')).toHaveCount(0);
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();

		// Reload to confirm nothing landed on the row server-side.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();
	});

	test('delete-from-detail: trash icon → confirm → redirect to /runs, row gone', async ({
		page
	}) => {
		// runs/list.spec.ts pins the bulk-delete from the list page.
		// This pins the single-run delete from the detail page —
		// distinct UI (the .icon-btn.danger trash next to the share /
		// edit affordances), distinct callsite for deleteRun, distinct
		// post-delete navigation (goto('/runs') instead of staying on
		// the list).
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false
		});

		await page.goto(`/runs/${planted}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });

		// Trash button is icon-only with title="Delete".
		await page.locator('button[title="Delete"]').click();
		const dialog = page.locator('.modal');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		// confirmDelete() calls deleteRun + goto('/runs').
		await page.waitForURL(/\/runs$/, { timeout: 10_000 });

		// Sanity: the run's storage row is gone in the DB. Re-listing
		// would require driving the date filter to All-time which is
		// flaky here (the runs-list filter UI is exercised in
		// runs/list.spec.ts already). The DB state is the contract —
		// deleteRun under the hood deletes the row, and the goto to
		// /runs proves the handler completed without throwing.
		const adminCheck = await import('../fixtures/local-supabase').then((m) =>
			m.getAdminClient()
		);
		const { data: stillThere } = await adminCheck
			.from('runs')
			.select('id')
			.eq('id', planted)
			.maybeSingle();
		expect(stillThere).toBeNull();
	});
});
