import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * On-pace hint (challenges.md § On-pace projection). A joined, mid-window goal
 * challenge whose logged value sits below the even-pace line renders the
 * "Behind pace" verdict + the daily rate still needed to finish on the progress
 * bar. Seeds a window 60 % elapsed (6 days in, 4 to go) with a goal of 100 km
 * and a single 20 km in-window run for USER_A (expected ≈ 60 km at this point →
 * behind). The pure projection is unit-tested in challenge_progress.test.ts;
 * this pins the UI wiring end to end.
 */
const CHALLENGE_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000b2';

test.describe('/challenges — on-pace hint', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		await admin.from('challenges').insert({
			id: CHALLENGE_ID,
			creator_id: USER_A.id,
			club_id: null,
			title: 'Pace e2e challenge',
			metric: 'distance',
			scope: 'individual',
			goal_value: 100000,
			is_public: true,
			starts_at: new Date(Date.now() - 6 * 86400000).toISOString(),
			ends_at: new Date(Date.now() + 4 * 86400000).toISOString()
		});
		await admin.from('challenge_participants').insert({
			challenge_id: CHALLENGE_ID,
			user_id: USER_A.id
		});
		const ins = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 86400000).toISOString(),
				duration_s: 6000,
				distance_m: 20000,
				activity_type: 'run',
				source: 'app',
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();
		runId = (ins.data as { id: string } | null)?.id ?? null;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (runId) await admin.from('runs').delete().eq('id', runId);
		await admin.from('challenges').delete().eq('id', CHALLENGE_ID);
	});

	test('a behind-pace joined challenge shows the verdict + required rate', async ({ page }) => {
		await page.goto(`/challenges/${CHALLENGE_ID}`);
		await expect(page.getByRole('heading', { level: 1, name: 'Pace e2e challenge' })).toBeVisible({
			timeout: 10_000
		});

		await expect(page.getByText('Behind pace')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText(/per day to finish/)).toBeVisible();
	});
});
