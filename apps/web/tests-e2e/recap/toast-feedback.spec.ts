import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * The recap pages must report copy / publish outcomes through the app's
 * toast system, never a blocking native alert(). Pins the alert()→showToast
 * conversion on both the year and month recap surfaces.
 */
const CURRENT_YEAR = new Date().getFullYear();

test.describe('/recap — feedback uses toasts, not native alert()', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('clipboard-text fallback shows a success toast and never a native dialog', async ({
		page,
		context
	}) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: 'http://localhost:7777'
		});

		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
			// Force the SVG→PNG rasterise to throw so the text/clipboard fallback runs.
			HTMLCanvasElement.prototype.getContext = () => null as never;
		});

		const dialogs: string[] = [];
		page.on('dialog', async (dialog) => {
			dialogs.push(dialog.message());
			await dialog.dismiss();
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: 'Share recap' }).click();

		const toast = page.locator('.toast-success', { hasText: 'Recap copied to clipboard.' });
		await expect(toast).toBeVisible({ timeout: 5_000 });

		expect(dialogs).toHaveLength(0);
		const clipText = await page.evaluate(() => navigator.clipboard.readText());
		expect(clipText).toContain(`My ${CURRENT_YEAR} in running`);
	});

	test('a failed publish surfaces an error toast, not a native dialog', async ({ page }) => {
		await page.route('**/rest/v1/public_recaps**', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated failure' })
			});
		});

		const dialogs: string[] = [];
		page.on('dialog', async (dialog) => {
			dialogs.push(dialog.message());
			await dialog.dismiss();
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: 'Publish & copy link' }).click();

		await expect(page.locator('.toast-error')).toBeVisible({ timeout: 5_000 });
		expect(dialogs).toHaveLength(0);
	});

	test('monthly recap clipboard fallback also uses a success toast', async ({ page, context }) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: 'http://localhost:7777'
		});

		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
			HTMLCanvasElement.prototype.getContext = () => null as never;
		});

		const dialogs: string[] = [];
		page.on('dialog', async (dialog) => {
			dialogs.push(dialog.message());
			await dialog.dismiss();
		});

		await page.goto(`/recap/${CURRENT_YEAR}/1`);
		// January may be empty for the seed user; only exercise the share path
		// when the populated card (and its Share button) actually rendered.
		const shareButton = page.getByRole('button', { name: 'Share recap' });
		const populated = await shareButton.isVisible({ timeout: 10_000 }).catch(() => false);
		test.skip(!populated, 'seed user has no runs in this month — no share affordance');

		await shareButton.click();

		await expect(
			page.locator('.toast-success', { hasText: 'Recap copied to clipboard.' })
		).toBeVisible({ timeout: 5_000 });
		expect(dialogs).toHaveLength(0);
	});
});
