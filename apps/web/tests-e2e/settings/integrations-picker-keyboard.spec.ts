import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/integrations — both bulk-import pickers must be reachable
 * without a mouse.
 *
 * The Strava and Garmin cards each wrapped a `hidden` file input in a
 * `<label>`. A hidden input is out of the tab order and a `<label>` is not a
 * control, so neither picker had a focusable element at all: clicking the
 * label was the only way to start a bulk import. Both are now the
 * button-plus-off-screen-input pattern the account page's Restore control
 * already used, so each exposes one real button and keeps exactly one file
 * input for the import specs to drive.
 */
test.describe('/settings/integrations — bulk-import pickers are keyboard-reachable', () => {
	test.use({ storageState: USER_A.storageStatePath });

	for (const label of ['Choose Strava export zip', 'Choose Garmin export'] as const) {
		test(`"${label}" opens the file chooser from the keyboard`, async ({ page }) => {
			await page.goto('/settings/integrations');

			// A <label> has no button role, so resolving one at all is half
			// the fix.
			const button = page.getByRole('button', { name: label });
			await expect(button).toBeVisible({ timeout: 10_000 });

			await button.focus();
			await expect(button).toBeFocused();

			// Enter on the focused control must reach the input — the whole
			// path a keyboard or screen-reader user takes.
			const chooser = page.waitForEvent('filechooser', { timeout: 10_000 });
			await page.keyboard.press('Enter');
			expect(await chooser).toBeTruthy();
		});
	}

	test('each bulk-import card still exposes exactly one file input', async ({ page }) => {
		await page.goto('/settings/integrations');

		const cards = page.locator('section.bulk-import');
		await expect(cards).toHaveCount(2, { timeout: 10_000 });
		for (let i = 0; i < 2; i++) {
			await expect(cards.nth(i).locator('input[type="file"]')).toHaveCount(1);
		}
	});
});
