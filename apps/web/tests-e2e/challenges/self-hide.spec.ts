import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B } from '../fixtures/users';

/**
 * Self-hide contract (challenges.md): a user in NO live challenge sees no
 * challenges strip on /dashboard, and an empty My-challenges section on
 * /challenges. USER_B is not joined to any challenge in the base seed.
 */
test.describe('challenges self-hide', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(async () => {
		// Ensure USER_B is in no challenge (defensive — other specs may leave
		// state if they fail mid-run).
		await getAdminClient().from('challenge_participants').delete().eq('user_id', USER_B.id);
	});

	test('dashboard shows no challenges strip when the user is in none', async ({ page }) => {
		await page.goto('/dashboard');
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
		// The self-hiding strip renders nothing when myActiveChallenges is empty.
		await expect(
			page.locator('section.challenges-strip', { hasText: 'My challenges' })
		).toHaveCount(0);
	});

	test('challenges page shows the empty My-challenges state', async ({ page }) => {
		await page.goto('/challenges');
		await expect(page.getByRole('heading', { level: 1, name: /Challenges/ })).toBeVisible({
			timeout: 10_000
		});
		// My challenges section renders its empty copy.
		await expect(page.getByText('No challenges yet.')).toBeVisible({ timeout: 10_000 });
	});
});
