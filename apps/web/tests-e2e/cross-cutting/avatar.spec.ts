import { expect, test } from '@playwright/test';

import { USER_A, USER_B } from '../fixtures/users';

/**
 * Avatar rendering guard.
 *
 * Seeded users carry no `avatar_url`, so every avatar across the app renders
 * the *initial placeholder* (first letter of the display name, uppercased) —
 * the logic-heavy branch the shared <Avatar> component / `initial()` helper
 * must preserve. These assertions are deliberately class-agnostic (they pin
 * the rendered initial within a named container, not `.avatar-sm` etc.) so
 * they stay green across the markup-consolidation refactor: same behaviour
 * before (per-site inline blocks) and after (shared <Avatar>).
 *
 * Names come from seed.sql: USER_A = "Jared Howard", USER_B = "Alex Chen".
 */
test.describe('avatar initial placeholder', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('People row shows the runner\'s initial when there is no avatar image', async ({
		page
	}) => {
		await page.goto('/social?tab=people');
		const search = page.getByPlaceholder('Search runners by name');
		await expect(search).toBeVisible({ timeout: 10_000 });
		await search.fill('Alex');

		const alexRow = page.locator('.person-row', { hasText: 'Alex Chen' });
		await expect(alexRow).toBeVisible({ timeout: 5_000 });
		// The placeholder is the only element in the row whose text is exactly "A".
		await expect(alexRow.getByText('A', { exact: true }).first()).toBeVisible();
	});

	test('Profile hero shows the initial placeholder', async ({ page }) => {
		await page.goto(`/u/${USER_B.id}`);
		await expect(page.getByRole('heading', { name: 'Alex Chen' })).toBeVisible({
			timeout: 10_000
		});
		const hero = page.locator('.profile-head');
		await expect(hero.getByText('A', { exact: true }).first()).toBeVisible();
	});
});
