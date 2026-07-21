import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /login — password show/hide visibility toggle (issue #487, #225).
 *
 * You type a password blind on the surface where a typo locks you out
 * of a brand-new account. Each obscured field carries a toggle that
 * flips it between type='password' and type='text', with an aria-label
 * that tracks the state.
 *
 * The same shared PasswordInput backs the /login sign-in + sign-up
 * fields AND the /settings/account change-password fields, so the
 * change-password surface is pinned here too (issue #487 extended the
 * toggle to every password-minting field for consistency).
 */

test.describe('/login password visibility toggle', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('toggle reveals and re-hides the typed password', async ({ page }) => {
		await page.goto('/login');
		const pw = page.locator('#login-password');
		await pw.fill('hunter2secret');
		await expect(pw).toHaveAttribute('type', 'password');

		const show = page.getByRole('button', { name: 'Show password' });
		await show.click();
		await expect(pw).toHaveAttribute('type', 'text');
		await expect(pw).toHaveValue('hunter2secret');

		const hide = page.getByRole('button', { name: 'Hide password' });
		await expect(hide).toHaveAttribute('aria-pressed', 'true');
		await hide.click();
		await expect(pw).toHaveAttribute('type', 'password');
	});

	test('sign-up mode: password and confirm toggles are independent', async ({
		page
	}) => {
		await page.goto('/login?signup=1');
		const pw = page.locator('#login-password');
		const confirm = page.locator('#login-confirm-password');
		await expect(confirm).toBeVisible();

		// Reveal only the confirm field — the password field stays hidden.
		await page.getByRole('button', { name: 'Show password' }).nth(1).click();
		await expect(confirm).toHaveAttribute('type', 'text');
		await expect(pw).toHaveAttribute('type', 'password');
	});
});

test.describe('/settings/account change-password visibility toggle', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Revealing text never calls updateUser, so this is safe against the
	// shared USER_A fixture (same reason the change-password validation
	// specs in settings/account.spec.ts are safe).
	test('New Password field reveals and re-hides via the toggle', async ({
		page
	}) => {
		await page.goto('/settings/account');
		const pw = page.getByLabel('New Password');
		await pw.fill('longenough1');
		await expect(pw).toHaveAttribute('type', 'password');

		// Scoped to its own label rather than an index — the section grew a
		// Current Password field ahead of this one (issue #381).
		const field = page.locator('label').filter({ hasText: 'New Password' });
		await field.getByRole('button', { name: 'Show password' }).click();
		await expect(pw).toHaveAttribute('type', 'text');
		await expect(pw).toHaveValue('longenough1');

		await field.getByRole('button', { name: 'Hide password' }).click();
		await expect(pw).toHaveAttribute('type', 'password');
	});
});
