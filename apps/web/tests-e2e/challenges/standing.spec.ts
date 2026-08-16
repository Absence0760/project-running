import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Leaderboard standing summary. A board only says who is where; the signal a
 * participant acts on is how far off the place above is — and their own row can
 * sit well off screen. Two seeded two-entrant public challenges: one where
 * USER_A (5 km) trails USER_B (12 km), one where the two are level. The pure
 * derivation is unit-tested in leaderboard_standing.test.ts; this pins the
 * wiring, the formatting, and the tied-for-the-lead branch end to end.
 */
const TRAILING_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000b3';
const TIED_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000b4';

// The assertions name an exact gap, so the aggregate must see THIS spec's runs
// and nothing else. Every other challenges spec seeds plain `run` rows over an
// overlapping window; filtering the challenge to an activity nobody else seeds
// isolates the board instead of making the expected number a running total.
const FIXTURE_ACTIVITY = 'stroller';

const WINDOW = {
	activity_type: FIXTURE_ACTIVITY,
	starts_at: new Date(Date.now() - 3 * 86400000).toISOString(),
	ends_at: new Date(Date.now() + 3 * 86400000).toISOString()
};

test.describe('/challenges — leaderboard standing', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const runIds: string[] = [];

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const seeded = await admin.from('challenges').insert([
			{
				id: TRAILING_ID,
				creator_id: USER_A.id,
				club_id: null,
				title: 'Standing e2e challenge',
				metric: 'distance',
				scope: 'individual',
				goal_value: 100000,
				is_public: true,
				...WINDOW
			},
			{
				id: TIED_ID,
				creator_id: USER_A.id,
				club_id: null,
				title: 'Standing tie e2e challenge',
				metric: 'activity_count',
				scope: 'individual',
				goal_value: 10,
				is_public: true,
				...WINDOW
			}
		]);
		if (seeded.error) throw new Error(`challenge seed failed: ${seeded.error.message}`);
		const joined = await admin.from('challenge_participants').insert([
			{ challenge_id: TRAILING_ID, user_id: USER_A.id },
			{ challenge_id: TRAILING_ID, user_id: USER_B.id },
			{ challenge_id: TIED_ID, user_id: USER_A.id },
			{ challenge_id: TIED_ID, user_id: USER_B.id }
		]);
		if (joined.error) throw new Error(`participant seed failed: ${joined.error.message}`);
		// One in-window run each. On the distance board they differ (5 km vs
		// 12 km); on the activity_count board a run is a run, so the same two
		// rows are a tie.
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
		await admin.from('challenges').delete().in('id', [TRAILING_ID, TIED_ID]);
	});

	test('a trailing entrant sees their rank and the gap to the runner ahead', async ({ page }) => {
		await page.goto(`/challenges/${TRAILING_ID}`);
		await expect(
			page.getByRole('heading', { level: 1, name: 'Standing e2e challenge' })
		).toBeVisible({ timeout: 10_000 });

		const standing = page.getByTestId('challenge-standing');
		await expect(standing).toBeVisible({ timeout: 10_000 });
		await expect(standing).toContainText('#2 of 2');
		await expect(standing).toContainText('7.00 km behind Alex Chen');
		await expect(standing).not.toContainText('ahead of');
	});

	test('tied for the lead reports the tie, never a bare "Leading"', async ({ page }) => {
		await page.goto(`/challenges/${TIED_ID}`);
		await expect(
			page.getByRole('heading', { level: 1, name: 'Standing tie e2e challenge' })
		).toBeVisible({ timeout: 10_000 });

		const standing = page.getByTestId('challenge-standing');
		await expect(standing).toBeVisible({ timeout: 10_000 });
		await expect(standing).toContainText('#1 of 2');
		await expect(standing).toContainText('Tied with 1 other');
		await expect(standing).not.toContainText('Leading');
	});
});
