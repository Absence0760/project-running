import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * The shared unsaved-changes navigation guard (UnsavedChangesGuard.svelte).
 *
 * Web is the canonical feature surface (decisions.md § 24) but shipped § 478's
 * pop-time discard guard on mobile only, so a half-filled web form was lost to
 * a back gesture or a nav link with no prompt. These cover the contract that
 * ADR carries over: dirtiness is probed at navigation time, a clean form never
 * prompts, cancelling keeps the typed input, and confirming lands on the
 * destination the user asked for — for an in-app link and for browser Back,
 * which take different paths through SvelteKit's router.
 */
test.describe('unsaved-changes guard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a clean form leaves without prompting', async ({ page }) => {
		await page.goto('/clubs/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Create a club' })).toBeVisible({
			timeout: 15_000,
		});

		await page.getByRole('link', { name: /Back to clubs/ }).click();
		await page.waitForURL(/\/social/, { timeout: 10_000 });
		await expect(page.getByTestId('unsaved-changes-dialog')).toHaveCount(0);
	});

	test('an in-app link out of a dirty form prompts, and cancelling keeps the input', async ({
		page,
	}) => {
		await page.goto('/clubs/new');
		const name = page.locator('input[type="text"]').first();
		await name.waitFor({ timeout: 15_000 });
		await name.fill('e2e guard draft');

		await page.getByRole('link', { name: /Back to clubs/ }).click();
		const dialog = page.getByTestId('unsaved-changes-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });

		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);
		await expect(page).toHaveURL(/\/clubs\/new/);
		await expect(name).toHaveValue('e2e guard draft');

		await page.getByRole('link', { name: /Back to clubs/ }).click();
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Discard' }).click();
		await page.waitForURL(/\/social/, { timeout: 10_000 });
	});

	test('browser Back out of a dirty form prompts, and discarding lands on the previous page', async ({
		page,
	}) => {
		await page.goto('/gym/routines');
		const newLink = page.getByTestId('routine-new');
		await newLink.waitFor({ timeout: 15_000 });
		await newLink.click();
		await page.waitForURL(/\/gym\/routines\/new/, { timeout: 10_000 });

		const title = page.locator('input.text-input').first();
		await title.waitFor({ timeout: 10_000 });
		await title.fill('e2e guard routine');

		await page.goBack();
		const dialog = page.getByTestId('unsaved-changes-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		// A cancelled popstate is undone by SvelteKit, so the URL must still be
		// the form's — a guard that let the address bar run ahead of the page
		// would leave the two disagreeing.
		await expect(page).toHaveURL(/\/gym\/routines\/new/);

		await dialog.getByRole('button', { name: 'Discard' }).click();
		await page.waitForURL(/\/gym\/routines$/, { timeout: 10_000 });
	});
});
