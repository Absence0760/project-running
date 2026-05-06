import { expect, test } from '@playwright/test';

import { switchRunsToAllTime } from './fixtures/helpers';
import { RUNNER_PUBLIC_RUN_ID } from './fixtures/seeded-data';
import { USER_A, USER_B } from './fixtures/users';

/**
 * Data-flow spec — CRUD round-trips through Supabase.
 *
 * Smoke covers "the page loads;" security covers "you can't see what
 * you shouldn't;" this spec covers "writes actually persist." The
 * regression risks here are:
 *   - A field that doesn't bind correctly (form looks right but
 *     never round-trips).
 *   - An optimistic-update path that updates local state but doesn't
 *     hit Supabase (rolls back silently on reload).
 *   - A delete that removes the row from the list but leaves the
 *     server-side record (or vice versa).
 *
 * Each test creates its own state and cleans up at the end so the
 * spec is idempotent against a re-run without `supabase db reset`.
 * If a test fails partway, the next `supabase db reset` cleans up.
 *
 * Three tests, three describe blocks:
 *   - Create + delete round-trip — full CRUD on a manual-entry run.
 *   - Edit run title persists across reload — exercises updateRunMetadata.
 *   - Cross-user kudos toggle — exercises the run_kudos write path
 *     and the engagement-chain RLS that lets B kudos a runner public
 *     run.
 */

const uniqueTitle = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('Manual run CRUD round-trip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('create via /runs modal → appears in list → delete → gone', async ({
		page
	}) => {
		const title = uniqueTitle('e2e-crud');

		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		// ── Create ──
		await page.getByRole('button', { name: '+ Add run' }).click();

		// RunEditor: started_at is pre-filled to "now"; activity defaults
		// to 'run'; we set distance + duration explicitly so the row
		// passes the runs CHECK constraint (distance > 0).
		await page.locator('input[type="datetime-local"]').first().fill('2026-04-29T08:00');
		await page.locator('input[type="number"]').first().fill('5'); // distance km
		await page.locator('input[type="number"]').nth(1).fill('25'); // duration min
		await page.locator('textarea').fill(title);

		await page.locator('form button[type="submit"]').click();

		// On success the page redirects to /runs/<new-id>. We don't
		// know the ID up-front; capture it from the URL.
		await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
		const newRunId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];

		// ── Verify it landed in the list ──
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(
			page.locator(`.run-card[href$="${newRunId}"]`)
		).toBeVisible({ timeout: 10_000 });

		// ── Delete ──
		await page.goto(`/runs/${newRunId}`);
		await page.waitForLoadState('networkidle');
		await page.getByRole('button', { name: 'Delete' }).first().click();
		// ConfirmDialog opens; the modal's confirm button reads "Delete".
		await page
			.getByRole('button', { name: 'Delete', exact: true })
			.last()
			.click();

		// After delete the page navigates back to /runs.
		await page.waitForURL(/\/runs(\?.*)?$/, { timeout: 10_000 });

		// Verify the row is gone from the list.
		await switchRunsToAllTime(page);
		await expect(
			page.locator(`.run-card[href$="${newRunId}"]`)
		).toHaveCount(0);
	});
});

test.describe('Edit run title persists across reload', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('rename pinned public run, reload, restore', async ({ page }) => {
		const newTitle = uniqueTitle('renamed');
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
});

test.describe('Cross-user kudos toggle', () => {
	// User B (alex) kudos's runner's pinned public run via the share
	// page. /runs/[id] is owner-only — fetchRunById hits the runs
	// table directly and RLS hides cross-user rows. /share/run/[id]
	// goes through the public_runs view + mounts RunSocial when
	// auth.loggedIn, which is the path real visitors take.
	//
	// The pinned run starts with zero kudos by design — see seed.sql §
	// e2e fixtures, the `id != '...'` filter on the cross-user kudos
	// insert.
	test.use({ storageState: USER_B.storageStatePath });

	test('alex kudos runner public run → reload persists → rescind', async ({
		page
	}) => {
		// Stub the clip-public-track EF — same as the smoke + security
		// specs.
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
		const kudosBtn = page.locator('.kudos-btn');
		await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
		await expect(kudosBtn).not.toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('0');

		// Click to give kudos.
		await kudosBtn.click();
		await expect(kudosBtn).toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('1');

		// Reload to confirm the write actually hit Supabase, not just
		// optimistic local state.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.kudos-btn')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.kudos-btn')).toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('1');

		// Rescind so the spec is idempotent across runs.
		await page.locator('.kudos-btn').click();
		await expect(page.locator('.kudos-btn')).not.toHaveClass(/given/);
		await expect(page.locator('.kudos-count')).toHaveText('0');
	});
});
