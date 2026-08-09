import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /fundraisers/[id] — a failed read must not tell a donor the campaign
 * does not exist.
 *
 * `fetchFundraiserById` did `if (error || !data) return null`, so a
 * postgrest failure and a deleted campaign were the same answer and the
 * page rendered "This fundraiser isn't available." to an anonymous donor
 * who followed a perfectly good link.
 *
 * The page is public, so this runs anonymously — the audience the bug hurt.
 */
test.describe('/fundraisers/[id] — a failed read is not a missing campaign', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	let fundraiserId = '';
	let runId = '';

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin.from('instructor_payout_accounts').upsert({
			user_id: USER_A.id,
			stripe_connect_account_id: `acct_e2e_frlf_${USER_A.id.slice(0, 8)}`,
			charges_enabled: true,
			payouts_enabled: true,
			details_submitted: true,
			country: 'US',
			default_currency: 'usd',
		});
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
		});
		const { data, error } = await admin
			.from('fundraisers')
			.insert({
				owner_user_id: USER_A.id,
				run_id: runId,
				charity_name: 'Test Charity',
				title: `e2e-fundraiser-load-failure ${Date.now()}`,
				goal_cents: 50_000,
				currency: 'usd',
				status: 'open',
			})
			.select('id')
			.single();
		if (error || !data) throw error ?? new Error('seed fundraiser failed');
		fundraiserId = data.id as string;
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (fundraiserId) await admin.from('fundraisers').delete().eq('id', fundraiserId);
		if (runId) await admin.from('runs').delete().eq('id', runId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', USER_A.id);
		fundraiserId = '';
		runId = '';
	});

	test('shows a load error with retry, not the not-found line', async ({ page }) => {
		let failRead = true;
		await page.route('**/rest/v1/fundraisers?*', async (route) => {
			if (failRead && route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated fundraiser read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto(`/fundraisers/${fundraiserId}`);

		const banner = page.getByTestId('fundraiser-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		await expect(page.getByText("This fundraiser isn't available.")).toHaveCount(0);

		failRead = false;
		await banner.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('fundraiser-load-error')).toHaveCount(0, { timeout: 15_000 });
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
	});

	test('a genuinely absent fundraiser still gets the not-found line', async ({ page }) => {
		await page.goto('/fundraisers/00000000-0000-4000-8000-000000000000');

		await expect(page.getByText("This fundraiser isn't available.")).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.getByTestId('fundraiser-load-error')).toHaveCount(0);
	});
});
