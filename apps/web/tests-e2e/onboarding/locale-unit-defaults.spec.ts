import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';

/**
 * Region unit defaults through the REAL new-user wiring (issue #488).
 *
 * The reporter expected a US visitor to default to miles and a metric
 * visitor to default to kilometres, changeable in Settings. The
 * `defaultUnitForLocale` helper already existed, but the new-profile
 * bootstrap in the auth store hard-coded `preferred_unit: 'km'` — a
 * locale-blind value that then clobbered the onboarding seed and left
 * skippers on km regardless of region.
 *
 * This drives a genuinely fresh signup (autoconfirm is on locally, so a
 * sign-up lands straight in the app) under a forced browser locale and
 * asserts the onboarding units step reflects the region default WITHOUT
 * the user touching it — i.e. the value came from account creation, not
 * a click. `defaultUnitForLocale` is unit-tested in isolation; this pins
 * that the region default actually reaches the new account through the
 * real signup → confirm_age_and_terms → onboarding wiring.
 *
 * Both contexts use an ENGLISH-UI locale (en-*) so the wizard chrome
 * stays English (the app negotiates en-US / en-CA → 'en'); only the
 * region differs — US is imperial, CA is metric — which is exactly the
 * `defaultUnitForLocale` axis under test. A non-English locale (de-DE)
 * would translate the headings/buttons and defeat the English selectors.
 *
 * Fresh throwaway emails per run; best-effort admin teardown of the
 * created auth user + profile so the local DB isn't littered.
 */

const uniqueEmail = (region: string) =>
	`e2e-locale-${region}-${Date.now()}-${Math.random().toString(36).slice(2, 6)}@test.local`;

async function signUpAndReachUnitsStep(
	page: import('@playwright/test').Page,
	email: string,
): Promise<void> {
	await page.goto('/login?signup=1');
	await expect(
		page.getByRole('heading', { name: 'Create an account' }),
	).toBeVisible({ timeout: 5_000 });
	// The submit handler wires after hydration; clicking earlier posts
	// the native form instead of running our signUp path.
	await page.waitForLoadState('networkidle');

	await page.getByPlaceholder('Email address').fill(email);
	await page.getByPlaceholder('Password', { exact: true }).fill('runner-pw-488');
	await page.getByPlaceholder('Confirm password').fill('runner-pw-488');
	await page.getByLabel(/I confirm I am 16 years of age or older/).check();
	await page.getByLabel(/I have read and agree to the/).check();
	await page.getByRole('button', { name: 'Sign Up' }).click();

	// Autoconfirm on: a session lands, goto('/dashboard') runs, and the
	// layout gate bounces the null-onboarded_at user into /onboarding.
	await page.waitForURL(/\/onboarding/, { timeout: 15_000 });

	// Step 1 — display name → step 2 (units). We never touch the unit
	// toggle: the assertion below is purely the bootstrapped default.
	await expect(
		page.getByRole('heading', { name: /What should we call you/i }),
	).toBeVisible({ timeout: 5_000 });
	await page.getByLabel('Display name').fill('E2E Locale');
	await page.getByRole('button', { name: 'Continue' }).click();
	await expect(
		page.getByRole('heading', { name: /Kilometres or miles/i }),
	).toBeVisible();
}

async function teardown(email: string): Promise<void> {
	try {
		const admin = getAdminClient();
		const { data } = await admin.auth.admin.listUsers();
		const u = data?.users?.find((x) => x.email === email);
		if (u) {
			await admin.from('user_profiles').delete().eq('id', u.id);
			await admin.auth.admin.deleteUser(u.id);
		}
	} catch {
		/* best-effort — a leftover throwaway row is harmless locally */
	}
}

test.describe('region unit defaults on first run', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a US-locale new user lands on miles', async ({ browser }) => {
		test.setTimeout(45_000);
		const context = await browser.newContext({
			locale: 'en-US',
			storageState: { cookies: [], origins: [] },
		});
		const page = await context.newPage();
		const email = uniqueEmail('us');
		try {
			await signUpAndReachUnitsStep(page, email);
			// Imperial region → Miles pre-selected, Kilometres not.
			await expect(page.getByRole('radio', { name: /Miles/ })).toHaveAttribute(
				'aria-checked',
				'true',
			);
			await expect(
				page.getByRole('radio', { name: /Kilometres/ }),
			).toHaveAttribute('aria-checked', 'false');
		} finally {
			await context.close();
			await teardown(email);
		}
	});

	test('a metric-region (en-CA) new user lands on kilometres', async ({ browser }) => {
		test.setTimeout(45_000);
		const context = await browser.newContext({
			locale: 'en-CA',
			storageState: { cookies: [], origins: [] },
		});
		const page = await context.newPage();
		const email = uniqueEmail('ca');
		try {
			await signUpAndReachUnitsStep(page, email);
			// Metric region → Kilometres pre-selected, Miles not.
			await expect(
				page.getByRole('radio', { name: /Kilometres/ }),
			).toHaveAttribute('aria-checked', 'true');
			await expect(page.getByRole('radio', { name: /Miles/ })).toHaveAttribute(
				'aria-checked',
				'false',
			);
		} finally {
			await context.close();
			await teardown(email);
		}
	});
});
