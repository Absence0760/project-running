import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
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

/**
 * Issue #367: /races shipped two hand-rolled dialogs — the "Submit a race"
 * editor and the import-result modal — that reproduced the modal markup by
 * hand and inherited none of the Modal primitive's keyboard behaviour (no
 * focus-on-open, no Escape, no Tab trap). Both now wrap the shared <Modal>,
 * so this pins the three guarantees on each: focus moves in on open, Escape
 * closes, and Tab never escapes the dialog subtree.
 */
test.describe('Modal focus trap — /races dialogs', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const raceName = `E2E Focus Trap Race ${Date.now()}`;
	let listingId: string | null = null;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('race_listings')
			.insert({
				provider: 'manual',
				name: raceName,
				race_date: '2027-11-06',
				distance_m: 21097,
				location_label: 'Richmond, VA',
				is_verified: true
			})
			.select('id')
			.single();
		listingId = (data as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (listingId) await admin.from('race_listings').delete().eq('id', listingId);
	});

	const focusIsInsideDialog = (page: import('@playwright/test').Page) =>
		page.evaluate(() => document.activeElement?.closest('[role="dialog"]') != null);

	test('Submit-a-race dialog: focus-on-open, Tab trapped, Escape closes', async ({ page }) => {
		await page.goto('/races');

		const opener = page.getByTestId('race-submit');
		await opener.click();

		const dialog = page.getByRole('dialog');
		await expect(dialog).toBeVisible();

		// Focus moves into the dialog on open (the shared Modal focuses the
		// dialog container so Escape works without a first click inside).
		expect(await focusIsInsideDialog(page)).toBe(true);

		// First Tab lands on the Modal's header close button.
		await page.keyboard.press('Tab');
		await expect(dialog.locator('button.modal-close')).toBeFocused();

		// However far a run of forward Tabs goes, focus never leaves the dialog.
		for (let i = 0; i < 25; i++) {
			await page.keyboard.press('Tab');
		}
		expect(await focusIsInsideDialog(page)).toBe(true);

		// Escape closes and restores focus to the opener.
		await page.keyboard.press('Escape');
		await expect(dialog).toHaveCount(0);
		await expect(opener).toBeFocused();
	});

	test('Import-result dialog: focus-on-open, Tab trapped, Escape closes', async ({ page }) => {
		await page.goto('/races');

		await page.getByTestId('races-search').fill(raceName);
		const card = page
			.getByTestId('races-results')
			.getByTestId('race-card')
			.filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 10_000 });

		await card.getByTestId('race-import').click();

		const dialog = page.getByRole('dialog');
		await expect(dialog).toBeVisible();
		await expect(dialog).toContainText(raceName);

		expect(await focusIsInsideDialog(page)).toBe(true);

		await page.keyboard.press('Tab');
		await expect(dialog.locator('button.modal-close')).toBeFocused();

		for (let i = 0; i < 25; i++) {
			await page.keyboard.press('Tab');
		}
		expect(await focusIsInsideDialog(page)).toBe(true);

		await page.keyboard.press('Escape');
		await expect(dialog).toHaveCount(0);
	});
});
