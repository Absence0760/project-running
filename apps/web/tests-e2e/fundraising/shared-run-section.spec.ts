import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * A run's fundraiser must be visible to the people the runner shares the run
 * WITH, not only to the runner.
 *
 * `/runs/[id]` mounts `FundraiserSection` inside the branch only the owner
 * reaches; every other reader falls into `otherRunOwner`, which renders
 * `RunShareView`. That component did not mount the section at all, so the
 * shared link a fundraising runner actually posts carried no campaign and the
 * page was reachable only by its own `/fundraisers/[id]` URL — the one surface
 * a supporter has not been given.
 *
 * This is a rendering fix and not a visibility change: the `fundraisers` SELECT
 * policy is `owner_user_id = auth.uid() OR fundraiser_anchor_visible(...)`,
 * which for a run delegates to `is_run_visible_to` — the same predicate that
 * decides whether the reader may see the run at all — and its EXECUTE is
 * granted to `anon`. Every reader asserted on below could already read the row
 * from the API while the UI withheld it.
 *
 * The no-campaign case is the control: without it the first test would pass
 * against a section that renders for every run regardless.
 */
test.describe('a shared run carries its fundraiser', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let runId = '';
	let fundraiserId = '';

	test.beforeEach(async () => {
		const admin = getAdminClient();
		// The `fundraisers` open-status trigger refuses a campaign whose owner
		// has no charges-enabled payout account.
		await admin.from('instructor_payout_accounts').upsert({
			user_id: USER_A.id,
			stripe_connect_account_id: `acct_e2e_sharedrun_${USER_A.id.slice(0, 8)}`,
			charges_enabled: true,
			payouts_enabled: true,
			details_submitted: true,
			country: 'US',
			default_currency: 'usd',
		});
		runId = await insertRun({
			user_id: USER_A.id,
			duration_s: 1800,
			distance_m: 5000,
			is_public: true,
		});
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (fundraiserId) await admin.from('fundraisers').delete().eq('id', fundraiserId);
		if (runId) await deleteRun(runId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', USER_A.id);
		fundraiserId = '';
		runId = '';
	});

	test('a non-owner sees the campaign and can reach its page', async ({ page }) => {
		const admin = getAdminClient();
		const { data, error } = await admin
			.from('fundraisers')
			.insert({
				owner_user_id: USER_A.id,
				run_id: runId,
				charity_name: 'Test Charity',
				title: `e2e-shared-run-fundraiser ${Date.now()}`,
				goal_cents: 50_000,
				currency: 'usd',
				status: 'open',
			})
			.select('id')
			.single();
		if (error || !data) throw error ?? new Error('seed fundraiser failed');
		fundraiserId = data.id as string;

		await page.goto(`/runs/${runId}`);

		const section = page.locator('.fundraiser-section');
		await expect(section).toBeVisible({ timeout: 15_000 });
		await expect(section.locator(`a[href="/fundraisers/${fundraiserId}"]`)).toBeVisible();
		// The create affordance belongs to the owner and this reader is not one.
		await expect(page.getByTestId('fundraiser-create-cta')).toHaveCount(0);
	});

	test('a shared run with no campaign renders no section', async ({ page }) => {
		await page.goto(`/runs/${runId}`);
		// Anchored on a sibling that always renders, so the absence below is a
		// claim about the section rather than about an unloaded page.
		await expect(page.locator('.run-share, main')).toBeVisible({ timeout: 15_000 });
		await expect(page.locator('.fundraiser-section')).toHaveCount(0);
	});
});
