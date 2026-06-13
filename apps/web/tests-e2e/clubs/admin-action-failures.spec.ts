import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] — admin destructive/regenerate actions must surface a
 * failure (toast) instead of swallowing it. USER_A admins the seeded
 * "tempo-tuesday" club. Pins the confirmRegenerate try/catch fix (the
 * same swallow-fix class as confirmDeleteClub/Post/Event).
 */
const TEMPO_TUESDAY_ID = 'c2222222-0000-0000-0000-000000000002';

test.describe('/clubs/[slug] admin action failures', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		// Seed an invite token so the admin invite panel (and its Rotate
		// button) renders — tempo-tuesday is join_policy='request' with a
		// null token by default, which hides the panel.
		await getAdminClient()
			.from('clubs')
			.update({ invite_token: 'e2eregenfail000000000000000000aa' })
			.eq('id', TEMPO_TUESDAY_ID);
	});

	test.afterEach(async () => {
		await getAdminClient()
			.from('clubs')
			.update({ invite_token: null })
			.eq('id', TEMPO_TUESDAY_ID);
	});

	test('a failed invite-link rotation surfaces an error toast', async ({ page }) => {
		// regenerateInviteToken PATCHes clubs.invite_token — force it to fail.
		await page.route('**/rest/v1/clubs**', async (route) => {
			if (route.request().method() === 'PATCH') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/clubs/tempo-tuesday');
		await expect(
			page.getByRole('heading', { level: 1, name: 'UVA Tempo Tuesday' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Rotate' }).click();
		await page
			.locator('.modal', { hasText: 'Regenerate' })
			.getByRole('button', { name: 'Regenerate' })
			.click();

		await expect(page.locator('.toast-error')).toBeVisible({ timeout: 5_000 });
	});
});
