import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
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
});
