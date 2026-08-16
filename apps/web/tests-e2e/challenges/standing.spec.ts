import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Leaderboard standing summary. A board only says who is where; the signal a
 * participant acts on is how far off the place above is — and their own row can
 * sit well off screen. Seeds a two-entrant public challenge where USER_A (5 km)
 * trails USER_B (12 km) and asserts the card names the rank, the board size, and
 * the 7.00 km gap to the runner ahead. The pure derivation is unit-tested in
 * leaderboard_standing.test.ts; this pins the wiring + formatting end to end.
 */
const CHALLENGE_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000b3';

test.describe('/challenges — leaderboard standing', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const runIds: string[] = [];

	test.beforeAll(async () => {
		const admin = getAdminClient();
		await admin.from('challenges').insert({
			id: CHALLENGE_ID,
			creator_id: USER_A.id,
			club_id: null,
			title: 'Standing e2e challenge',
			metric: 'distance',
			scope: 'individual',
			goal_value: 100000,
			is_public: true,
			starts_at: new Date(Date.now() - 3 * 86400000).toISOString(),
			ends_at: new Date(Date.now() + 3 * 86400000).toISOString()
		});
		await admin.from('challenge_participants').insert([
			{ challenge_id: CHALLENGE_ID, user_id: USER_A.id },
			{ challenge_id: CHALLENGE_ID, user_id: USER_B.id }
		]);
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
					activity_type: 'run',
					source: 'app',
					metadata: { activity_type: 'run' }
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
	});

	test('a trailing entrant sees their rank and the gap to the runner ahead', async ({ page }) => {
		await page.goto(`/challenges/${CHALLENGE_ID}`);
		await expect(
			page.getByRole('heading', { level: 1, name: 'Standing e2e challenge' })
		).toBeVisible({ timeout: 10_000 });

		const standing = page.getByTestId('challenge-standing');
		await expect(standing).toBeVisible({ timeout: 10_000 });
		await expect(standing).toContainText('#2 of 2');
		await expect(standing).toContainText('7.00 km behind Alex Chen');
		await expect(standing).not.toContainText('ahead of');
	});
});
