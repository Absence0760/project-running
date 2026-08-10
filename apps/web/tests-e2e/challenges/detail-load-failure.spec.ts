import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /challenges/[id] — a failed read must not claim the challenge is gone.
 *
 * The page's `load()` caught every throw into `notFound`, and `notFound` is
 * rendered before anything else, so a transient failure — including one on
 * the leaderboard read for a challenge that had already resolved — told the
 * creator "This challenge isn't available." Failure now has its own branch
 * with a retry; a genuinely missing row still gets the not-found line.
 */
test.describe('/challenges/[id] — a failed read is not a missing challenge', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of created) {
			await admin.from('challenges').delete().eq('id', id);
		}
		created.length = 0;
	});

	async function plantChallenge(): Promise<string> {
		const admin = getAdminClient();
		const now = Date.now();
		const { data, error } = await admin
			.from('challenges')
			.insert({
				creator_id: USER_A.id,
				title: `e2e-challenge-load-failure ${now}`,
				scope: 'individual',
				metric: 'distance',
				goal_value: 100000,
				starts_at: new Date(now - 86400000).toISOString(),
				ends_at: new Date(now + 7 * 86400000).toISOString(),
			})
			.select('id')
			.single();
		if (error || !data) throw error ?? new Error('plantChallenge failed');
		created.push(data.id as string);
		return data.id as string;
	}

	test('shows a load error with retry, not the not-found line', async ({ page }) => {
		const id = await plantChallenge();

		let failRead = true;
		await page.route('**/rest/v1/challenges?*', async (route) => {
			if (failRead && route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated challenge read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto(`/challenges/${id}`);

		const banner = page.getByTestId('challenge-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		await expect(page.getByText("This challenge isn't available.")).toHaveCount(0);

		failRead = false;
		await banner.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('challenge-load-error')).toHaveCount(0, { timeout: 15_000 });
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
	});

	test('a failed leaderboard read is a load failure, not a missing challenge', async ({
		page,
	}) => {
		const id = await plantChallenge();

		await page.route('**/rest/v1/rpc/challenge_leaderboard*', (route) =>
			route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated leaderboard failure' }),
			}),
		);

		await page.goto(`/challenges/${id}`);

		await expect(page.getByTestId('challenge-load-error')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByText("This challenge isn't available.")).toHaveCount(0);
	});

	test('a genuinely absent challenge still gets the not-found line', async ({ page }) => {
		await page.goto('/challenges/00000000-0000-4000-8000-000000000000');

		await expect(page.getByText("This challenge isn't available.")).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.getByTestId('challenge-load-error')).toHaveCount(0);
	});
});
