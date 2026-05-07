import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_C_PRO } from '../fixtures/users';

/**
 * `BillingIssueBanner` — global "Update your card" banner mounted on
 * the root layout. Driven by `user_profiles.billing_issue_at`, which
 * the `revenuecat-webhook` EF sets on `BILLING_ISSUE` and clears on
 * `RENEWAL` / `UNCANCELLATION` / `EXPIRATION` / `CANCELLATION`.
 *
 * The banner is the user-facing half of the grace-period semantic:
 * we deliberately DON'T downgrade to free on BILLING_ISSUE (that
 * would strip access from a user with a temporarily declined card
 * mid-grace-period); instead we surface the state so they can fix it
 * before EXPIRATION fires in 16-30 days. See
 * `apps/backend/supabase/functions/revenuecat-webhook/lib.ts` for
 * the tier vs billing-flag separation.
 *
 * Test plants the flag via service-role + tests the visible/hidden
 * branches end-to-end through the auth store's `get_my_profile`
 * fetch.
 */

test.describe('BillingIssueBanner — global grace-period surface', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.afterEach(async () => {
		// Always reset morgan to a clean state — no billing flag.
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ billing_issue_at: null })
			.eq('id', USER_C_PRO.id);
	});

	test('Pro user with billing_issue_at set sees the banner with CTA + relative-days copy', async ({
		page
	}) => {
		// Plant: morgan (pro per seed) had a renewal failure 3 days ago.
		const threeDaysAgo = new Date(Date.now() - 3 * 86_400_000).toISOString();
		const admin = getAdminClient();
		const { error } = await admin
			.from('user_profiles')
			.update({ billing_issue_at: threeDaysAgo })
			.eq('id', USER_C_PRO.id);
		expect(error).toBeNull();

		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const banner = page.getByTestId('billing-issue-banner');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner).toContainText(/Pro renewal payment failed/i);
		await expect(banner).toContainText(/3 days ago/i);
		await expect(banner).toContainText(/Update your card/i);

		// CTA navigates to /settings/upgrade where Manage subscription
		// is the actionable next step.
		await banner.getByRole('button', { name: /Manage subscription/i }).click();
		await expect(page).toHaveURL(/\/settings\/upgrade/, { timeout: 5_000 });

		// Banner is still visible on /settings/upgrade since it's
		// rooted in the layout.
		await expect(page.getByTestId('billing-issue-banner')).toBeVisible();
	});

	test('Pro user with billing_issue_at NULL does NOT see the banner', async ({
		page
	}) => {
		// Confirm baseline: morgan has no billing flag, banner absent.
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ billing_issue_at: null })
			.eq('id', USER_C_PRO.id);

		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		await expect(page.getByTestId('billing-issue-banner')).toHaveCount(0);
	});

	test('relative-days copy shows "today" for a flag set within the last 24h', async ({
		page
	}) => {
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ billing_issue_at: new Date().toISOString() })
			.eq('id', USER_C_PRO.id);

		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		await expect(page.getByTestId('billing-issue-banner')).toContainText(
			/today/i,
			{ timeout: 10_000 }
		);
	});

	test('billing_issue_at is read-only for non-service-role callers (lock_subscription_columns)', async () => {
		// Defence in depth: a self-DoS suppression of the banner would
		// be possible if the user could clear the flag client-side.
		// Migration 20260729_001 added billing_issue_at to the
		// lock_subscription_columns trigger so any non-service-role
		// UPDATE raises 42501. Pin that.
		const admin = getAdminClient();

		// Plant the flag.
		const oneHourAgo = new Date(Date.now() - 3_600_000).toISOString();
		await admin
			.from('user_profiles')
			.update({ billing_issue_at: oneHourAgo })
			.eq('id', USER_C_PRO.id);

		// Mint a real user JWT for morgan and try to clear the flag.
		const { getUserClient } = await import('../fixtures/local-supabase');
		const morgan = await getUserClient({
			email: USER_C_PRO.email,
			password: USER_C_PRO.password
		});
		const { error } = await morgan
			.from('user_profiles')
			.update({ billing_issue_at: null })
			.eq('id', USER_C_PRO.id);

		expect(
			error?.code,
			'a non-service-role UPDATE of billing_issue_at must raise 42501 ' +
				'(read-only by lock_subscription_columns trigger)'
		).toBe('42501');

		// Confirm via service-role: the flag is still set. Postgres
		// returns timestamps in `+00:00` ISO form; compare as Date to
		// be format-agnostic.
		const { data: row } = await admin
			.from('user_profiles')
			.select('billing_issue_at')
			.eq('id', USER_C_PRO.id)
			.single();
		expect(row?.billing_issue_at).toBeTruthy();
		expect(new Date(row?.billing_issue_at as string).toISOString()).toBe(
			oneHourAgo
		);
	});
});
