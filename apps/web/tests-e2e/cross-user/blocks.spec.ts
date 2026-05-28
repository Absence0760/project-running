import { expect, test } from '@playwright/test';

import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Cross-user block flows. USER_C_PRO (morgan) clicks the Block button
 * on USER_A (runner)'s profile, the ConfirmDialog gates the action,
 * the icon-only button flips aria-pressed, and clicking it again
 * unblocks without a confirm (un-blocking is non-destructive).
 *
 * This is the user-facing end of the user_blocks primitive (migration
 * 20261012_001 + persona-hunt Round 3 finding W1). The backend gates
 * (RLS on follows / kudos / comments, public_profile_by_id hiding the
 * row) have pgtap coverage in supabase/tests/user_blocks_test.sql;
 * here we pin the UI round-trip so a future refactor that drops the
 * button or stops calling block_user / unblock_user shows up loudly.
 *
 * Cleans up after itself by unblocking, so the seeded state is left
 * untouched for downstream specs that touch this user pair.
 */

test.describe('cross-user blocks', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test('morgan blocks runner via confirm, then unblock restores the un-pressed state', async ({
		page,
	}) => {
		await page.goto(`/u/${USER_A.id}`);

		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		const blockBtn = page.locator('button.btn-block');
		await expect(blockBtn).toBeVisible({ timeout: 10_000 });
		await expect(blockBtn).toHaveAttribute('aria-pressed', 'false');
		await expect(blockBtn).toHaveAttribute('aria-label', 'Block this profile');

		// Click opens the ConfirmDialog rather than firing block_user
		// immediately — the destructive direction (drains follow rows
		// on both sides) needs a confirm.
		await blockBtn.click();
		const confirmBtn = page.getByRole('button', { name: 'Block', exact: true });
		await expect(confirmBtn).toBeVisible({ timeout: 5_000 });
		await confirmBtn.click();

		// After block: aria-pressed flips true, aria-label becomes the
		// unblock copy. The page itself doesn't go away — the share-
		// page contract (public_profile_by_id returning empty for the
		// blocked target) is tested at the DB layer; here we pin the
		// UI toggle.
		await expect(blockBtn).toHaveAttribute('aria-pressed', 'true', { timeout: 5_000 });
		await expect(blockBtn).toHaveAttribute('aria-label', 'Unblock this profile');

		// Click again to unblock — no confirm, restores immediately.
		await blockBtn.click();
		await expect(blockBtn).toHaveAttribute('aria-pressed', 'false', { timeout: 5_000 });
		await expect(blockBtn).toHaveAttribute('aria-label', 'Block this profile');
	});

	test('clicking Block then Cancel leaves the un-blocked state intact', async ({
		page,
	}) => {
		// Pins the confirm-dialog gate: a stray Block click followed
		// by Cancel must not record a block (regression risk if a
		// refactor wired the button onclick directly to block_user
		// without the showBlockConfirm intermediate).
		await page.goto(`/u/${USER_A.id}`);
		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		const blockBtn = page.locator('button.btn-block');
		await blockBtn.click();
		const cancelBtn = page.getByRole('button', { name: 'Cancel', exact: true });
		await expect(cancelBtn).toBeVisible({ timeout: 5_000 });
		await cancelBtn.click();

		await expect(blockBtn).toHaveAttribute('aria-pressed', 'false');
	});
});
