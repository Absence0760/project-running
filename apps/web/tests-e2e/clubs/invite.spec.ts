import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/join/[token] — invite-link redemption for invite-only clubs.
 *
 * Friends of Jared is seeded with `join_policy = 'invite'` and a
 * stable invite_token. A signed-in user landing on the redemption
 * URL hits the join_club_by_token RPC and gets bumped to the club
 * page as an active member. This pins the only entry point into a
 * private club for non-owners.
 *
 * Morgan isn't seeded into any club, so a successful redemption is a
 * pure +1 to that membership.
 */

const FRIENDS_OF_JARED_ID = 'c3333333-0000-0000-0000-000000000003';
const FRIENDS_OF_JARED_TOKEN = 'c3fr13nd50fj4r3dc1ubtoken000000';

test.describe('/clubs/join/[token] — invite redemption', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.afterEach(async () => {
		try {
			await getAdminClient()
				.from('club_members')
				.delete()
				.eq('club_id', FRIENDS_OF_JARED_ID)
				.eq('user_id', USER_C_PRO.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('signed-in morgan visits a Friends-of-Jared invite URL → joins → lands on the club page', async ({
		page
	}) => {
		await page.goto(`/clubs/join/${FRIENDS_OF_JARED_TOKEN}`);

		// onMount calls joinClubByToken → goto(`/clubs/<slug>`); we
		// don't dwell on the "Joining…" intermediate state because it
		// races. Wait for the destination URL.
		await page.waitForURL(/\/clubs\/friends-of-jared$/, {
			timeout: 15_000
		});

		// Membership took effect — composer mounts (private club, only
		// members + admins see the body of the page at all).
		await expect(
			page.getByRole('heading', { level: 1, name: 'Friends of Jared' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.post-form textarea').first())
			.toBeVisible({ timeout: 10_000 });
	});
});
