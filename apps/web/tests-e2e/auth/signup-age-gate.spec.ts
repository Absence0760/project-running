import { expect, test } from '@playwright/test';

/**
 * Signup form — GDPR Art 8 age gate + ToS acceptance.
 *
 * The signup form (apps/web/src/routes/login/+page.svelte) requires
 * the user to tick two boxes before the Submit button enables:
 *   1. Confirm they are 16 or older (GDPR Art 8 conservative floor).
 *   2. Agree to the Terms of Service and Privacy Policy.
 *
 * If either gate quietly disappears, we lose the legal posture this
 * session put in place — and a regulator could argue we collected
 * consent without lawful basis. Pin every branch.
 *
 * login.spec.ts has a happy-path signup that does check both boxes;
 * this file holds the *negative* cases that the happy-path would
 * not catch.
 */

test.describe('Signup age gate + ToS acceptance', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('Submit stays disabled until both boxes are checked', async ({ page }) => {
		await page.goto('/login?signup=1');
		await expect(
			page.getByRole('heading', { name: 'Create an account' })
		).toBeVisible({ timeout: 5_000 });

		const submit = page.getByRole('button', { name: 'Sign Up' });
		const email = page.getByPlaceholder('Email address');
		// exact: true — getByPlaceholder is a case-insensitive substring
		// match by default, so a bare 'Password' also matches the
		// sign-up-only 'Confirm password' field and trips strict mode.
		const password = page.getByPlaceholder('Password', { exact: true });
		const ageBox = page.getByLabel(/I confirm I am 16 years of age or older/);
		const termsBox = page.getByLabel(/I have read and agree to the/);

		// Fill credentials but leave the boxes off — Submit stays
		// disabled. Pinning this ensures a future refactor can't drop
		// the disabled binding.
		await email.fill('e2e-disabled-test@test.local');
		await password.fill('testtest');
		await expect(submit).toBeDisabled();

		// Age only — still disabled because ToS unchecked.
		await ageBox.check();
		await expect(submit).toBeDisabled();

		// ToS without age — also blocked.
		await ageBox.uncheck();
		await termsBox.check();
		await expect(submit).toBeDisabled();

		// Both checked → enabled.
		await ageBox.check();
		await expect(submit).toBeEnabled();
	});

	test('Sign-in mode does NOT show the age / ToS boxes', async ({ page }) => {
		await page.goto('/login');
		// No ?signup=1 → default sign-in. Submit should be enabled
		// after fill alone; the consent boxes only render in sign-up
		// mode where we're creating an account.
		await expect(
			page.getByLabel(/I confirm I am 16 years of age or older/)
		).toHaveCount(0);
		await expect(page.getByLabel(/I have read and agree to the/)).toHaveCount(0);
	});

	test('ToS box links to /terms and /privacy in new tabs', async ({ page }) => {
		await page.goto('/login?signup=1');
		await expect(
			page.getByRole('heading', { name: 'Create an account' })
		).toBeVisible();

		// Per the contract: ToS acceptance must point at the actual
		// docs we just published. A regression that loses the link
		// would make the consent meaningless.
		const tosLink = page.getByRole('link', { name: 'Terms of Service' }).first();
		const privacyLink = page.getByRole('link', { name: 'Privacy Policy' }).first();
		await expect(tosLink).toHaveAttribute('href', '/terms');
		await expect(privacyLink).toHaveAttribute('href', '/privacy');
		// target=_blank so the user doesn't lose their signup form.
		await expect(tosLink).toHaveAttribute('target', '_blank');
		await expect(privacyLink).toHaveAttribute('target', '_blank');
	});

	test('OAuth sign-up with un-ticked boxes surfaces the localized gate error', async ({
		page
	}) => {
		// The gate now returns a stable reason code; the page resolves it
		// through m('login.gateAdult') / m('login.gateTerms') instead of a
		// hard-coded English string. Clicking "Continue with Google" in
		// sign-up mode without ticking the boxes must show the adult-gate
		// copy inline (the first failing gate) and NOT start an OAuth
		// redirect. Pins that the i18n indirection is wired up.
		await page.goto('/login?signup=1');
		await expect(
			page.getByRole('heading', { name: 'Create an account' })
		).toBeVisible({ timeout: 5_000 });
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: 'Continue with Google' }).click();

		await expect(page.getByText(/16 or older to continue/)).toBeVisible();
		// Still on /login — the gate short-circuited before any redirect.
		await expect(page).toHaveURL(/\/login/);
	});

	test('Toggling between sign-in and sign-up shows/hides the consent boxes', async ({
		page
	}) => {
		await page.goto('/login');
		// Wait for hydration — the toggle button's onclick handler is
		// wired in onMount; clicking before then leaves $state untouched.
		// (Playwright's actionability check on .click() doesn't cover
		// Svelte hydration — only DOM presence + visibility.)
		await page.waitForLoadState('networkidle');
		// Boxes hidden initially (sign-in mode).
		await expect(
			page.getByLabel(/I confirm I am 16 years of age or older/)
		).toHaveCount(0);

		// Toggle to sign-up. The toggle is rendered via the .link-btn
		// class — distinct from the form submit button — so a class
		// selector targets it unambiguously regardless of casing
		// collisions between 'Sign in' (toggle) and 'Sign In' (submit).
		const toToSignUp = page.locator('button.link-btn', { hasText: 'Sign up' });
		await expect(toToSignUp).toBeVisible();
		await toToSignUp.click();
		// Heading flip is the canonical "mode actually changed" signal.
		await expect(
			page.getByRole('heading', { name: 'Create an account' })
		).toBeVisible({ timeout: 5_000 });
		await expect(
			page.getByLabel(/I confirm I am 16 years of age or older/)
		).toBeVisible();

		// Toggle back to sign-in.
		await page.locator('button.link-btn', { hasText: 'Sign in' }).click();
		await expect(
			page.getByRole('heading', { name: 'Sign in to your account' })
		).toBeVisible({ timeout: 5_000 });
		await expect(
			page.getByLabel(/I confirm I am 16 years of age or older/)
		).toHaveCount(0);
	});
});
