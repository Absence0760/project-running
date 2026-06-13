import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /plans — the abandon/delete ConfirmDialog reliability contract.
 *
 * Pins two fixes from a UX-hunt round:
 *   1. ConfirmDialog disables its confirm button while the async
 *      `onconfirm` is in flight, so a fast double-click can't fire the
 *      (non-idempotent) status mutation twice.
 *   2. plans/+page.svelte's handleConfirmAction surfaces a failure as an
 *      error toast and keeps the dialog open, instead of swallowing it +
 *      closing as if the plan were abandoned.
 *
 * Both tests INTERCEPT the PATCH so the shared seed plan is never
 * actually mutated (other specs depend on "Richmond Half 2026" staying
 * active).
 */
test.describe('/plans abandon confirm', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const PATCH = '**/rest/v1/training_plans**';

	async function openAbandonDialog(page: import('@playwright/test').Page) {
		await page.goto('/plans');
		const card = page.locator('.card', { hasText: 'Richmond Half 2026' });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await card.getByRole('button', { name: 'Abandon' }).click();
		const dialog = page.locator('.modal', { hasText: 'Abandon plan' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		return dialog;
	}

	test('a failed abandon surfaces an error toast and keeps the dialog open', async ({
		page
	}) => {
		await page.route(PATCH, async (route) => {
			if (route.request().method() === 'PATCH') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' })
				});
				return;
			}
			await route.fallback();
		});

		const dialog = await openAbandonDialog(page);
		await dialog.getByRole('button', { name: 'Abandon' }).click();

		// Failure is surfaced (not swallowed)...
		await expect(page.locator('.toast-error')).toBeVisible({ timeout: 5_000 });
		// ...and the dialog stays open so the user can retry or cancel.
		await expect(dialog).toBeVisible();
	});

	test('double-clicking confirm fires the mutation only once', async ({ page }) => {
		let patchCount = 0;
		await page.route(PATCH, async (route) => {
			if (route.request().method() === 'PATCH') {
				patchCount += 1;
				// Hold the response so the button stays in-flight across
				// the second synchronous click.
				await new Promise((r) => setTimeout(r, 400));
				await route.fulfill({ status: 204, body: '' });
				return;
			}
			await route.fallback();
		});

		const dialog = await openAbandonDialog(page);
		const confirm = dialog.locator('button.btn-danger');

		// Two native clicks in the same task: the busy guard set on the
		// first call must make the second a no-op before Svelte even
		// paints the disabled attribute.
		await confirm.evaluate((el: HTMLButtonElement) => {
			el.click();
			el.click();
		});

		await expect(dialog).toHaveCount(0, { timeout: 5_000 });
		expect(patchCount).toBe(1);
	});
});
