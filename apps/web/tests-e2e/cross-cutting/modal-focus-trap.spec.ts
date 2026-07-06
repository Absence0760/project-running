import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Accessibility audit 2026-07-02 High (WCAG 2.4.3 Focus Order): the shared
 * Modal primitive saved/restored focus and closed on Escape but did not trap
 * Tab, so a keyboard user could Tab from the last control in an open dialog
 * straight into the obscured page behind it. Every dialog in the app
 * (ConfirmDialog included) inherits the trap from Modal, so pinning it once
 * on the /runs Add-run modal covers the primitive.
 */
test.describe('Modal focus trap', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Tab and Shift+Tab cycle inside the Add-run modal', async ({ page }) => {
		await page.goto('/runs');
		await page.getByRole('button', { name: '+ Add run' }).click();

		const dialog = page.getByRole('dialog');
		await expect(dialog).toBeVisible();

		// Focus lands on the dialog container itself on open; the first Tab
		// enters the dialog's first focusable control (the header close
		// button).
		const closeBtn = dialog.locator('button.modal-close');
		await page.keyboard.press('Tab');
		await expect(closeBtn).toBeFocused();

		// Shift+Tab from the first control wraps to the LAST focusable
		// control instead of escaping into the page behind the dialog.
		await page.keyboard.press('Shift+Tab');
		const wrappedTo = page.locator(':focus');
		await expect(wrappedTo).toBeVisible();
		expect(
			await wrappedTo.evaluate(
				(el) => el.closest('[role="dialog"]') != null,
			),
		).toBe(true);

		// Tab from the last control wraps forward to the first again.
		await page.keyboard.press('Tab');
		await expect(closeBtn).toBeFocused();

		// However far a run of forward Tabs goes, focus never leaves the
		// dialog subtree while it is open.
		for (let i = 0; i < 25; i++) {
			await page.keyboard.press('Tab');
		}
		expect(
			await page.evaluate(() =>
				document.activeElement?.closest('[role="dialog"]') != null,
			),
		).toBe(true);

		// Escape still closes and restores focus to the opener.
		await page.keyboard.press('Escape');
		await expect(dialog).toHaveCount(0);
		await expect(page.getByRole('button', { name: '+ Add run' })).toBeFocused();
	});
});
