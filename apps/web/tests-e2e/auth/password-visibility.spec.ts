import { expect, test } from '@playwright/test';

/**
 * /login — password show/hide visibility toggle (issue #225).
 *
 * You type a password blind on the surface where a typo locks you out
 * of a brand-new account. Each obscured field carries a toggle that
 * flips it between type='password' and type='text', with an aria-label
 * that tracks the state.
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
