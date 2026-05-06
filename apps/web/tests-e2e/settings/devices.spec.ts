import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/devices — per-device prefs registry. Each session gets a
 * `device_id` minted into localStorage. The matching
 * `user_device_settings` row is auto-provisioned by `loadSettings`
 * on first read — i.e. the *first time* the user opens any settings
 * tab — not at sign-in. So this test visits /settings/preferences
 * first to trigger the upsert before drilling into /settings/devices.
 *
 * Future depth: per-device override add → clear round-trip, remove
 * (non-current) device row, reset-this-device path (would invalidate
 * the storage state — handle via ephemeral session like the sign-out
 * test).
 */

test.describe('/settings/devices', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('current browser shows up with a "This device" badge', async ({
		page
	}) => {
		// Trigger the device-row auto-provision by opening any
		// loadSettings-backed tab first. /settings/preferences's
		// onMount calls loadSettings → inserts the missing row.
		await page.goto('/settings/preferences');
		await expect(
			page.getByRole('heading', { name: 'Units & Display' })
		).toBeVisible({ timeout: 10_000 });

		await page.goto('/settings/devices');

		// onMount polls auth.loading then queries user_device_settings.
		// The .device-list is the container (vs. the empty state).
		// Wait for at least one row.
		const rows = page.locator('.device');
		await expect(rows.first()).toBeVisible({ timeout: 10_000 });

		// Exactly one of the device rows is the active session and
		// renders the "This device" badge inside `.current-badge`.
		await expect(page.locator('.current-badge', { hasText: 'This device' }))
			.toBeVisible();

		// The current row's remove-button title swaps from "Remove
		// device" to the reset-this-device hint — pin that wiring too.
		// Targeting via title= (the button's only descendant is a
		// material-symbol icon; accessible name comes from the title
		// attr on this button, but icon-ligature text noise makes the
		// `name` matcher unreliable here).
		const currentRow = page.locator('.device.current');
		await expect(currentRow).toHaveCount(1);
		await expect(
			currentRow.locator('button[title^="Reset this device"]')
		).toBeVisible();
	});
});
