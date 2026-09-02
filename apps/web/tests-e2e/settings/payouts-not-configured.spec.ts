import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/payouts — what a host reads when Connect onboarding refuses.
 *
 * The page already intends two different answers: a build with no Stripe
 * Connect keys gets a calm INFO toast ("Payments aren't configured on this
 * build yet.") and stays usable, while a real failure gets a red error. It
 * chooses between them by pattern-matching the thrown message for
 * `not_configured` / `503`.
 *
 * `clubs/event-paid-register.spec.ts` walks this button but only asserts the
 * page does not navigate away, so which of the two answers appeared was
 * never checked — and it was the wrong one. `supabase.functions.invoke`
 * reports every non-2xx as a `FunctionsHttpError` whose message is the fixed
 * "Edge Function returned a non-2xx status code"; the function's own
 * `{ error: 'stripe_not_configured' }` envelope rides on `context`. So the
 * message the pattern is applied to never contained either token, the
 * not-configured branch was unreachable, and the operator got a red error
 * carrying the internal sentence instead.
 *
 * The function is stubbed at the network layer: the two branches are
 * distinguished by the envelope, which is the thing under test.
 */
test.describe('/settings/payouts — onboarding refusals', () => {
	test.use({ storageState: USER_A.storageStatePath });

	async function clickSetupWith(
		page: import('@playwright/test').Page,
		status: number,
		body: unknown,
	): Promise<void> {
		await page.route('**/functions/v1/events-connect-onboard', async (route) => {
			await route.fulfill({
				status,
				contentType: 'application/json',
				body: JSON.stringify(body),
			});
		});
		await page.goto('/settings/payouts');
		const setup = page.getByRole('button', { name: /Set up payments/i });
		await expect(setup).toBeVisible({ timeout: 15_000 });
		await setup.click();
	}

	test('a build with no Stripe keys says so calmly, and never leaks the invoke internals', async ({
		page,
	}) => {
		await clickSetupWith(page, 503, { error: 'stripe_not_configured' });

		const toast = page.locator('.toast').first();
		await expect(toast).toBeVisible({ timeout: 10_000 });
		await expect(toast).toContainText("Payments aren't configured on this build yet.");
		await expect(toast).toHaveClass(/toast-info/);
		await expect(page.locator('.toast')).not.toContainText(/non-2xx|Edge Function/);
		await expect(page).toHaveURL(/\/settings\/payouts/);
	});

	test('a genuine failure still reads as an error, with a code rather than the invoke internals', async ({
		page,
	}) => {
		await clickSetupWith(page, 500, { error: 'stripe_account_create_failed' });

		const toast = page.locator('.toast').first();
		await expect(toast).toBeVisible({ timeout: 10_000 });
		await expect(toast).toHaveClass(/toast-error/);
		await expect(toast).toContainText('stripe_account_create_failed');
		await expect(page.locator('.toast')).not.toContainText(/non-2xx|Edge Function/);
	});

	test('the setup button is released so the host can retry or read the page', async ({ page }) => {
		await clickSetupWith(page, 503, { error: 'stripe_not_configured' });
		await expect(page.getByRole('button', { name: /Set up payments/i })).toBeEnabled({
			timeout: 10_000,
		});
	});
});
