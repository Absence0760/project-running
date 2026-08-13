import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /challenges — the "My challenges" cards must show the caller's REAL banked
 * value, not a placeholder zero.
 *
 * `fetchChallenges` reads the `challenges` table, which carries no per-caller
 * value — that lives only in the `challenge_leaderboard` aggregate. It used to
 * hardcode `my_value: null` and the card rendered `value={c.my_value ?? 0}`, so
 * every joined challenge showed a 0 % bar while the dashboard ChallengesPanel,
 * reading `my_active_challenges`, showed the true number for the same row. The
 * list now folds that aggregate in.
 *
 * Asserted on the progress bar's `aria-valuenow` rather than a formatted string
 * so the pin is independent of the km/mi preference: 20 km banked against a
 * 100 km goal is 20 %, and was 0 before the fix.
 */
const CHALLENGE_ID = 'eeeeeeee-eeee-eeee-eeee-eeee000000b3';
const TITLE = 'List progress e2e challenge';

test.describe('/challenges — My-challenges progress', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		await admin.from('challenges').insert({
			id: CHALLENGE_ID,
			creator_id: USER_A.id,
			club_id: null,
			title: TITLE,
			metric: 'distance',
			scope: 'individual',
			goal_value: 100000,
			is_public: true,
			starts_at: new Date(Date.now() - 3 * 86400000).toISOString(),
			ends_at: new Date(Date.now() + 3 * 86400000).toISOString()
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

	test('a joined challenge card shows the banked value, not zero', async ({ page }) => {
		await page.goto('/challenges');

		const card = page.locator('li').filter({ hasText: TITLE }).first();
		await expect(card).toBeVisible({ timeout: 10_000 });

		const bar = card.getByRole('progressbar');
		await expect(bar).toHaveAttribute('aria-valuenow', '20', { timeout: 10_000 });
		await expect(card.getByTestId('challenge-my-rank')).toHaveText('#1');
		await expect(card.getByTestId('challenge-progress-unavailable')).toHaveCount(0);
	});

	test('a card whose value could not be loaded says so instead of showing zero', async ({
		page
	}) => {
		// The value comes from my_active_challenges; the list itself still loads.
		// A failed enrichment must degrade to "unavailable", never to a 0 % bar.
		await page.route('**/rest/v1/rpc/my_active_challenges*', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated my_active_challenges failure' })
			});
		});

		await page.goto('/challenges');

		const card = page.locator('li').filter({ hasText: TITLE }).first();
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('challenge-progress-unavailable')).toBeVisible();
		await expect(card.getByRole('progressbar')).toHaveCount(0);
	});
});
