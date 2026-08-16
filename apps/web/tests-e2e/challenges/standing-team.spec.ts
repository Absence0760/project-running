import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Club-vs-club standing attribution. Nothing stops a runner belonging to two
 * clubs that BOTH field a team on one board, so the club they are credited to
 * must come from their own `challenge_participants.team_club_id`, never from
 * whichever of their clubs happens to appear on the board first. USER_A is in
 * both clubs here and joined the challenge under the one they joined LONGER
 * ago — `fetchMyClubs` orders by `joined_at` desc, so a club-membership guess
 * would pick the decoy (which leads the board) and tell them they were winning.
 */
const CHALLENGE_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000b5';
const DECOY_CLUB = 'dddddddd-dddd-dddd-dddd-ddddddddaa01';
const REAL_CLUB = 'dddddddd-dddd-dddd-dddd-ddddddddaa02';

// See standing.spec.ts — filtering the challenge to an activity no other spec
// seeds keeps the asserted gap this spec's own arithmetic.
const FIXTURE_ACTIVITY = 'stroller';

test.describe('/challenges — club-vs-club standing attribution', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const runIds: string[] = [];

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const clubs = await admin.from('clubs').insert([
			{
				id: DECOY_CLUB,
				owner_id: USER_B.id,
				name: 'Standing Decoy Club',
				slug: 'standing-decoy-club',
				is_public: true
			},
			{
				id: REAL_CLUB,
				owner_id: USER_A.id,
				name: 'Standing Real Club',
				slug: 'standing-real-club',
				is_public: true
			}
		]);
		if (clubs.error) throw new Error(`club seed failed: ${clubs.error.message}`);
		// Each club's owner is enrolled by a trigger, so only the cross-membership
		// is seeded here. Backdating it makes the decoy the NEWEST of USER_A's
		// clubs, which is the one a `fetchMyClubs`-ordered guess would pick.
		const members = await admin
			.from('club_members')
			.insert([{ club_id: DECOY_CLUB, user_id: USER_A.id, role: 'member' }]);
		if (members.error) throw new Error(`membership seed failed: ${members.error.message}`);
		const backdated = await admin
			.from('club_members')
			.update({ joined_at: '2026-01-01T00:00:00Z' })
			.eq('club_id', REAL_CLUB)
			.eq('user_id', USER_A.id);
		if (backdated.error) throw new Error(`membership backdate failed: ${backdated.error.message}`);

		const seeded = await admin.from('challenges').insert({
			id: CHALLENGE_ID,
			creator_id: USER_A.id,
			club_id: null,
			title: 'Standing team e2e challenge',
			metric: 'distance',
			scope: 'club_vs_club',
			goal_value: 100000,
			is_public: true,
			activity_type: FIXTURE_ACTIVITY,
			starts_at: new Date(Date.now() - 3 * 86400000).toISOString(),
			ends_at: new Date(Date.now() + 3 * 86400000).toISOString()
		});
		if (seeded.error) throw new Error(`challenge seed failed: ${seeded.error.message}`);
		const joined = await admin.from('challenge_participants').insert([
			{ challenge_id: CHALLENGE_ID, user_id: USER_A.id, team_club_id: REAL_CLUB },
			{ challenge_id: CHALLENGE_ID, user_id: USER_B.id, team_club_id: DECOY_CLUB }
		]);
		if (joined.error) throw new Error(`participant seed failed: ${joined.error.message}`);

		for (const [userId, distance] of [
			[USER_A.id, 5000],
			[USER_B.id, 12000]
		] as const) {
			const ins = await admin
				.from('runs')
				.insert({
					user_id: userId,
					started_at: new Date(Date.now() - 86400000).toISOString(),
					duration_s: 1800,
					distance_m: distance,
					activity_type: FIXTURE_ACTIVITY,
					source: 'app',
					metadata: { activity_type: FIXTURE_ACTIVITY }
				})
				.select('id')
				.single();
			const id = (ins.data as { id: string } | null)?.id;
			if (id) runIds.push(id);
		}
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		for (const id of runIds) await admin.from('runs').delete().eq('id', id);
		await admin.from('challenges').delete().eq('id', CHALLENGE_ID);
		await admin.from('clubs').delete().in('id', [DECOY_CLUB, REAL_CLUB]);
	});

	test('the standing follows the club the runner joined under, not their newest club', async ({
		page
	}) => {
		await page.goto(`/challenges/${CHALLENGE_ID}`);
		await expect(
			page.getByRole('heading', { level: 1, name: 'Standing team e2e challenge' })
		).toBeVisible({ timeout: 10_000 });

		const standing = page.getByTestId('challenge-standing');
		await expect(standing).toBeVisible({ timeout: 10_000 });
		await expect(standing).toContainText('#2 of 2');
		await expect(standing).toContainText('7.00 km behind Standing Decoy Club');
		await expect(standing).not.toContainText('Leading');
	});
});
