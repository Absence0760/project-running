import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The run-detail fundraiser SECTION — a failed campaign read must not read as
 * "there is no campaign".
 *
 * `fetchFundraiserForRun` throws on a failed read now, but the section's own
 * loader catches it and leaves `fundraiser = null` on purpose, so the owner's
 * "Create fundraiser" CTA cannot be hidden by a blip. The consequence for the
 * OTHER reader went unfixed: a donor following a shared link to a run whose
 * fundraiser read failed saw the section render nothing at all — byte for byte
 * what a run with no campaign renders.
 *
 * Runs anonymously: the audience the bug hurt is the non-owner.
 */
test.describe('run-detail fundraiser section — a failed read is not "no campaign"', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	let fundraiserId = '';
	let runId = '';

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin.from('instructor_payout_accounts').upsert({
			user_id: USER_A.id,
			stripe_connect_account_id: `acct_e2e_frsec_${USER_A.id.slice(0, 8)}`,
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
				title: `e2e-fundraiser-section-failure ${Date.now()}`,
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

	test('a non-owner gets a retry, and the retry brings the campaign back', async ({ page }) => {
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

		await page.goto(`/runs/${runId}`);

		const banner = page.getByTestId('fundraiser-section-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		// An anonymous viewer is not the owner, so the Create CTA must not be
		// offered to them whether the read worked or not.
		await expect(page.getByTestId('fundraiser-create-cta')).toHaveCount(0);

		failRead = false;
		await banner.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('fundraiser-section-load-error')).toHaveCount(0, {
			timeout: 15_000,
		});
		await expect(page.getByText('Recent supporters')).toBeVisible({ timeout: 15_000 });
	});

	test('a run with genuinely no campaign shows nothing at all to a non-owner', async ({
		page,
	}) => {
		// The control the first test needs to mean anything: the empty case and
		// the failed case rendered identically, so the fix is only real if the
		// empty case still renders nothing.
		const admin = getAdminClient();
		await admin.from('fundraisers').delete().eq('id', fundraiserId);
		fundraiserId = '';

		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('fundraiser-section-load-error')).toHaveCount(0);
		await expect(page.getByTestId('fundraiser-create-cta')).toHaveCount(0);
	});
});
