import { expect, test } from '@playwright/test';

import { switchRunsToAllTime } from './fixtures/helpers';
import { RUNNER_PUBLIC_RUN_ID } from './fixtures/seeded-data';
import { USER_A, USER_B } from './fixtures/users';

/**
 * Happy-path spec — complete user journeys that exercise the most-
 * trafficked flows end-to-end.
 *
 * Smoke covers "the page loads;" security covers "you can't see what
 * you shouldn't;" data-flow covers "writes round-trip." This spec
 * covers "the user actually accomplishes a thing" — the multi-step
 * flows where a regression won't show up in any single-page check.
 *
 * Four describe blocks:
 *   - Filter runs by activity type — toolbar narrows the list.
 *   - Cross-user comment + delete on a public run.
 *   - Open the "This Week" period-summary modal from /dashboard.
 *   - Update display name in /settings/account, persists across
 *     reload, restored at end.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('Filter runs by activity type', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Walk filter narrows the list to the single seeded walk', async ({
		page
	}) => {
		// seed.sql gives runner exactly one walk + one hike alongside
		// 26 runs. Selecting Walk on the toolbar must collapse the list
		// to that single row — proves the activity-type filter both
		// exists in the UI and queries the right metadata key
		// (jsonb `metadata->>activity_type`, not a column).
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		// Sanity: more than one card is visible before filtering.
		const beforeCount = await page.locator('.run-card').count();
		expect(beforeCount).toBeGreaterThan(2);

		// The activity-type group is a button group with aria-label
		// "Activity type"; each button has aria-label set to the label
		// (Run / Walk / Cycle / Hike / All). Walk is unique, so role +
		// name is the most stable selector.
		await page.getByRole('button', { name: 'Walk', exact: true }).click();

		// Exactly one walk row in the seed.
		await expect(page.locator('.run-card')).toHaveCount(1);
	});
});

test.describe('Cross-user comment + delete', () => {
	// User B (alex) leaves a comment on runner's pinned public run via
	// /share/run/. /runs/[id] is owner-only — fetchRunById hits the
	// runs table directly and RLS hides cross-user rows. /share/run/
	// goes through the public_runs view + mounts RunSocial when
	// auth.loggedIn, which is the path real visitors take.
	//
	// The pinned run starts with zero comments by design — the
	// `id != '...'` filter on the cross-user comment seed exempts it.
	test.use({ storageState: USER_B.storageStatePath });

	test('alex comments on runner public run → reload persists → delete', async ({
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
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.comment p').first()).toHaveText(body, {
			timeout: 10_000
		});

		// Delete (rescind), so the spec is idempotent across runs.
		await page.getByRole('button', { name: 'Delete comment' }).first().click();
		await expect(page.locator('.comment')).toHaveCount(0);
		await expect(page.locator('.comment-count')).toContainText('0 comments');
	});
});

test.describe('Period summary modal', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('clicking "This Week" stat tile opens the period summary modal', async ({
		page
	}) => {
		// The dashboard's "This Week" stat card is a button (rather
		// than a static tile) so the user can drill into the period.
		// On click it sets `periodModal = { type: 'week', date: now }`
		// which mounts the shared <PeriodSummary> inside a Modal with
		// title "Period summary".
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		// The stat card may render with a 0 km value if "this week"
		// (real wall-clock) doesn't intersect any seeded run — that's
		// fine, we're testing modal-open, not the contents.
		const thisWeekCard = page.getByRole('button', { name: /This Week/ }).first();
		await expect(thisWeekCard).toBeVisible();
		await thisWeekCard.click();

		// The Modal shell from app.css uses .modal-backdrop + .modal,
		// with the title rendered in .modal-header h2. Asserting the
		// header text is the most stable signal that the right modal
		// opened (not e.g. the goal editor).
		await expect(
			page.locator('.modal-header h2', { hasText: 'Period summary' })
		).toBeVisible({ timeout: 5_000 });

		// PeriodSummary's own week/month toggle is inside the modal;
		// its presence confirms the body mounted, not just the shell.
		await expect(
			page.locator('.modal').getByRole('button', { name: 'Week' })
		).toBeVisible();
	});
});

test.describe('Display name update', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('rename, reload, verify persistence, restore', async ({ page }) => {
		// Profile saves write to user_profiles.display_name (visible
		// across the app — feed, kudos, comments, /u/[id]). The
		// regression risk is that a save returns 200 but RLS blocks
		// the update silently, or the optimistic local state masks a
		// failed write. Reload-then-assert covers both.
		const newName = uniqueText('e2e-name');
		const originalName = 'Jared Howard';

		await page.goto('/settings/account');
		await page.waitForLoadState('networkidle');

		const nameInput = page.getByLabel('Display Name');
		await expect(nameInput).toHaveValue(originalName);
		await nameInput.fill(newName);

		await page.getByRole('button', { name: /Save Profile/ }).click();
		// `handleSave` flips the button label to "Saved!" once the
		// upsert resolves — wait for that before reloading so the
		// reload sees a persisted value, not in-flight optimistic UI.
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.getByLabel('Display Name')).toHaveValue(newName);

		// Restore so the spec is idempotent.
		await page.getByLabel('Display Name').fill(originalName);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.getByLabel('Display Name')).toHaveValue(originalName);
	});
});
