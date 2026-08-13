import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /challenges/[id] — a club-vs-club leaderboard must name every competing club,
 * including the ones the viewer is not a member of.
 *
 * The detail page built `clubNames` from `fetchMyClubs()` alone, and the
 * leaderboard fell back to `row.team_club_id` — so every rival team on the
 * board rendered as a raw uuid, which is both meaningless to a reader and an
 * internal identifier on screen. The page now resolves the board's own team
 * ids in one `fetchClubNames` read, and the component's fallback is a
 * localized label rather than the id.
 */
const CHALLENGE_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000b4';
const RIVAL_CLUB_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000c4';
const RIVAL_CLUB_NAME = 'Rival Pack e2e';
const RIVAL_SLUG = 'rival-pack-e2e';

test.describe('/challenges/[id] — club-vs-club team names', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeAll(async () => {
		const admin = getAdminClient();
		// Owned by USER_B, so USER_A is NOT a member — exactly the case that used
		// to render as a uuid. Public, so RLS lets USER_A read the name.
		await admin.from('clubs').insert({
			id: RIVAL_CLUB_ID,
			owner_id: USER_B.id,
			name: RIVAL_CLUB_NAME,
			slug: RIVAL_SLUG,
			is_public: true,
			join_policy: 'open'
		});
		await admin.from('challenges').insert({
			id: CHALLENGE_ID,
			creator_id: USER_B.id,
			club_id: null,
			title: 'Club vs club e2e challenge',
			metric: 'distance',
			scope: 'club_vs_club',
			goal_value: null,
			is_public: true,
			starts_at: new Date(Date.now() - 86400000).toISOString(),
			ends_at: new Date(Date.now() + 86400000).toISOString()
		});
		await admin.from('challenge_participants').insert({
			challenge_id: CHALLENGE_ID,
			user_id: USER_B.id,
			team_club_id: RIVAL_CLUB_ID
		});
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		await admin.from('challenges').delete().eq('id', CHALLENGE_ID);
		await admin.from('clubs').delete().eq('id', RIVAL_CLUB_ID);
	});

	test("a club the viewer isn't in is named, not shown as its uuid", async ({ page }) => {
		await page.goto(`/challenges/${CHALLENGE_ID}`);

		const board = page.getByRole('list', { name: 'Leaderboard' });
		await expect(board).toBeVisible({ timeout: 10_000 });
		await expect(board.getByText(RIVAL_CLUB_NAME)).toBeVisible();
		await expect(board.getByText(RIVAL_CLUB_ID)).toHaveCount(0);
	});
});
