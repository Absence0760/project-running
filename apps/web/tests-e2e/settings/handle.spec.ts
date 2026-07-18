import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/account — public @username (handle) claim (issue #465).
 * Covers the claim → persist round-trip and the format-error path. The
 * write goes through the set_my_handle SECURITY DEFINER RPC (the only
 * owner write path), so a regression that dropped the field or lost the
 * error mapping surfaces here. Uniqueness collision is pinned at the
 * pgtap layer (search_user_profiles_handle_test.sql) — it needs a second
 * account the shared seed user doesn't have.
 */

test.describe('/settings/account — @username', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('claim a username — save persists across reload, then clears', async ({
		page
	}) => {
		const handle = `e2e_${Date.now()}`.slice(0, 30);

		await page.goto('/settings/account');
		const input = page.getByTestId('handle-input');
		await expect(input).toBeVisible();

		await input.fill(handle);
		await page.getByTestId('handle-save').click();
		await expect(page.getByTestId('handle-save')).toHaveText(/Saved/, {
			timeout: 5_000
		});

		await page.reload();
		await expect(page.getByTestId('handle-input')).toHaveValue(handle);

		// Clear it so the shared seed user is left as we found it.
		await page.getByTestId('handle-input').fill('');
		await page.getByTestId('handle-save').click();
		await expect(page.getByTestId('handle-save')).toHaveText(/Saved/, {
			timeout: 5_000
		});
		await page.reload();
		await expect(page.getByTestId('handle-input')).toHaveValue('');
	});

	test('an invalid username shows the format error and does not persist', async ({
		page
	}) => {
		await page.goto('/settings/account');
		await page.getByTestId('handle-input').fill('Bad Name!');
		await page.getByTestId('handle-save').click();

		await expect(page.getByTestId('handle-error')).toBeVisible();
		await page.reload();
		// Rejected → nothing was written.
		await expect(page.getByTestId('handle-input')).toHaveValue('');
	});
});
