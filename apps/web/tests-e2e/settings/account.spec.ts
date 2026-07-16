import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/account — profile + email / password / parkrun number /
 * DOB / HR fields. Covers the display-name round-trip + the
 * change-password validation branches; future depth: parkrun number
 * import button, profile avatar upload, account deletion.
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
		await expect(page.getByLabel('Display Name')).toHaveValue(newName);

		// Restore so the spec is idempotent.
		await page.getByLabel('Display Name').fill(originalName);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
		await page.reload();
		await expect(page.getByLabel('Display Name')).toHaveValue(originalName);
	});

	test('parkrun athlete number save persists across reload', async ({
		page
	}) => {
		// parkrun_number is a text column on user_profiles that the
		// parkrun importer uses to find the user's results page. A
		// regression that dropped the field from the save payload
		// would surface here. Use a placeholder-style value (no real
		// athletes hit by leaking it) and restore.
		await page.goto('/settings/account');
		// Needed: inputValue() snapshots — no auto-retry — so the read
		// would capture the pre-fetch default rather than the user's
		// persisted value.
		await page.waitForLoadState('networkidle');

		const input = page.getByLabel(/parkrun Athlete Number/);
		const before = await input.inputValue();
		const next = `A${Date.now()}`.slice(0, 9);

		await input.fill(next);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await expect(page.getByLabel(/parkrun Athlete Number/)).toHaveValue(next);

		// Restore.
		await page.getByLabel(/parkrun Athlete Number/).fill(before);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
	});

	test('Resting HR save persists across reload', async ({ page }) => {
		// resting_hr_bpm lives in user_settings.prefs, not user_profiles.
		// The Save handler stitches the two writes together; a regression
		// that dropped the prefs branch would let HR slip while
		// display_name persisted.
		await page.goto('/settings/account');
		// Needed: inputValue() snapshots — no auto-retry — so the read
		// would capture the pre-fetch default rather than the user's
		// persisted setting.
		await page.waitForLoadState('networkidle');

		const hr = page.getByLabel(/Resting HR/);
		const before = await hr.inputValue();
		const next = '54';

		await hr.fill(next);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await expect(page.getByLabel(/Resting HR/)).toHaveValue(next);

		await page.getByLabel(/Resting HR/).fill(before);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
	});

	// Change-password validation. This section MINTS a password
	// (updateUser), so it shares checkPasswordPair with /login?signup=1
	// and /auth/reset — see web_app_auth.md § Password confirmation.
	//
	// Only the REJECTION branches are exercised: a successful save would
	// rotate USER_A's password out from under storageStatePath and every
	// other spec that signs in as them. Both cases below return before
	// updateUser is called, which is exactly why they're safe to run
	// against the shared fixture user.
	test.describe('change password — validation', () => {
		test('mismatched entries are rejected', async ({ page }) => {
			await page.goto('/settings/account');
			await page.getByLabel('New Password').fill('longenough1');
			await page.getByLabel('Confirm Password').fill('longenough2');
			await page.getByRole('button', { name: 'Save Password' }).click();

			await expect(page.getByText('Passwords do not match.')).toBeVisible();
		});

		test('a too-short entry reports length, not mismatch', async ({ page }) => {
			await page.goto('/settings/account');
			// Short AND mismatched: length is the user's real problem, so
			// reporting a mismatch would send them round the loop fixing
			// the wrong thing. Pins the precedence through the UI.
			await page.getByLabel('New Password').fill('abc');
			await page.getByLabel('Confirm Password').fill('xyz');
			await page.getByRole('button', { name: 'Save Password' }).click();

			await expect(
				page.getByText('Password must be at least 6 characters.')
			).toBeVisible();
			await expect(page.getByText('Passwords do not match.')).toHaveCount(0);
		});
	});
});
