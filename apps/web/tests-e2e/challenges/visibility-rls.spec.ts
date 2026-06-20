import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Visibility RLS negative (challenges.md): a private, non-public challenge that
 * USER_A created (open, no club) is invisible to USER_B — fetchChallengeById
 * returns null and the detail page shows the not-found copy. Mirrors
 * private-rls-negative.spec.ts for clubs.
 */
const CHALLENGE_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000a1';

test.describe('challenges visibility RLS', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeAll(async () => {
		await getAdminClient()
			.from('challenges')
			.insert({
				id: CHALLENGE_ID,
				creator_id: USER_A.id,
				club_id: null,
				title: 'Private e2e challenge',
				metric: 'distance',
				scope: 'individual',
				goal_value: 100000,
				is_public: false,
				starts_at: new Date(Date.now() - 86400000).toISOString(),
				ends_at: new Date(Date.now() + 30 * 86400000).toISOString()
			});
	});

	test.afterAll(async () => {
		await getAdminClient().from('challenges').delete().eq('id', CHALLENGE_ID);
	});

	test('a non-member cannot see a private challenge', async ({ page }) => {
		await page.goto(`/challenges/${CHALLENGE_ID}`);
		await expect(page.getByText("This challenge isn't available.")).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { level: 1, name: 'Private e2e challenge' })).toHaveCount(
			0
		);
	});
});
