import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/account — profile + email / password / parkrun number /
 * DOB / HR fields. Currently covers the display-name round-trip;
 * future depth: parkrun number import button, password change flow,
 * profile avatar upload, account deletion.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/settings/account', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('display name update — save persists across reload, restore', async ({
		page
	}) => {
		// Profile saves write to user_profiles.display_name (visible
		// across the app — feed, kudos, comments, /u/[id]). The
		// regression risk is that a save returns 200 but RLS blocks
		// the update silently, or the optimistic local state masks a
		// failed write. Reload-then-assert covers both.
		const newName = uniqueText('e2e-name');
		const originalName = 'Jared Howard';

		await page.goto('/settings/account');
		await page.waitForLoadState('networkidle');

		const nameInput = page.getByLabel('Display Name');
		await expect(nameInput).toHaveValue(originalName);
		await nameInput.fill(newName);

		await page.getByRole('button', { name: /Save Profile/ }).click();
		// `handleSave` flips the button label to "Saved!" once the
		// upsert resolves — wait for that before reloading so the
		// reload sees a persisted value, not in-flight optimistic UI.
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.getByLabel('Display Name')).toHaveValue(newName);

		// Restore so the spec is idempotent.
		await page.getByLabel('Display Name').fill(originalName);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.getByLabel('Display Name')).toHaveValue(originalName);
	});
});
