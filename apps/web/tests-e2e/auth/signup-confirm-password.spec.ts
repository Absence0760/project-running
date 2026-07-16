import { expect, test } from '@playwright/test';

/**
 * Signup form — password confirmation.
 *
 * The sign-up form used to take the password in a SINGLE field. A typo
 * there is silently baked into the account: GoTrue hashes whatever was
 * typed, the confirmation email arrives and is clicked, and the account
 * is then permanently unreachable by its owner. Nothing errors, on
 * either side — the user believes they know their password, we see a
 * confirmed account that has simply never signed in. It is
 * indistinguishable from a forgotten password, and it cost us a real
 * user (last_sign_in_at null on a confirmed account, 2026-07-16).
 *
 * /auth/reset has always asked twice. This pins the same contract on
 * the surface where the password is FIRST minted, which is the one that
 * matters most.
 *
 * The pair logic itself is unit-tested in
 * src/lib/core/auth_gates.test.ts (checkPasswordPair) — these cases pin
 * the WIRING: that the field exists in the right mode, that the check
 * runs before the account is created, and that the error is the
 * localized string rather than an opaque GoTrue failure.
 */

test.describe('Signup password confirmation', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	// exact: true — getByPlaceholder is a case-insensitive substring
	// match, so a bare 'Password' also matches 'Confirm password'.
	const pw = (page: import('@playwright/test').Page) =>
		page.getByPlaceholder('Password', { exact: true });
	const confirmPw = (page: import('@playwright/test').Page) =>
		page.getByPlaceholder('Confirm password');

	async function gotoSignUp(page: import('@playwright/test').Page) {
		await page.goto('/login?signup=1');
		await expect(
			page.getByRole('heading', { name: 'Create an account' })
		).toBeVisible({ timeout: 5_000 });
		// The submit handler is wired after hydration; clicking earlier
		// posts the native form instead of running our check.
		await page.waitForLoadState('networkidle');
	}

	async function acceptGates(page: import('@playwright/test').Page) {
		await page.getByLabel(/I confirm I am 16 years of age or older/).check();
		await page.getByLabel(/I have read and agree to the/).check();
	}

	test('the confirm field renders in sign-up mode', async ({ page }) => {
		await gotoSignUp(page);
		await expect(confirmPw(page)).toBeVisible();
		// type=password so it is masked like the field it mirrors — a
		// plaintext confirm would defeat the point of asking twice.
		await expect(confirmPw(page)).toHaveAttribute('type', 'password');
		// autocomplete=new-password on BOTH fields, so a password
		// manager offers to generate/store rather than autofilling the
		// current-password value into one of them.
		await expect(confirmPw(page)).toHaveAttribute('autocomplete', 'new-password');
		await expect(pw(page)).toHaveAttribute('autocomplete', 'new-password');
	});

	test('the confirm field does NOT render in sign-in mode', async ({ page }) => {
		// Signing in to an existing account doesn't mint a password, so
		// asking twice would be pure friction on the hotter path.
		await page.goto('/login');
		await expect(
			page.getByRole('heading', { name: 'Sign in to your account' })
		).toBeVisible({ timeout: 5_000 });
		await expect(confirmPw(page)).toHaveCount(0);
		await expect(pw(page)).toBeVisible();
	});

	test('the confirm field does NOT render in reset-request mode', async ({ page }) => {
		// /login?reset=1 collects an email only — no password at all.
		await page.goto('/login?reset=1');
		await expect(
			page.getByRole('heading', { name: 'Reset your password' })
		).toBeVisible({ timeout: 5_000 });
		await expect(confirmPw(page)).toHaveCount(0);
		await expect(pw(page)).toHaveCount(0);
	});

	test('toggling sign-in → sign-up reveals the confirm field', async ({ page }) => {
		await page.goto('/login');
		await page.waitForLoadState('networkidle');
		await expect(confirmPw(page)).toHaveCount(0);

		// .link-btn distinguishes the mode toggle from the submit
		// button, which collides on casing ('Sign up' vs 'Sign Up').
		await page.locator('button.link-btn', { hasText: 'Sign up' }).click();
		await expect(
			page.getByRole('heading', { name: 'Create an account' })
		).toBeVisible({ timeout: 5_000 });
		await expect(confirmPw(page)).toBeVisible();

		await page.locator('button.link-btn', { hasText: 'Sign in' }).click();
		await expect(
			page.getByRole('heading', { name: 'Sign in to your account' })
		).toBeVisible({ timeout: 5_000 });
		await expect(confirmPw(page)).toHaveCount(0);
	});

	test('mismatched passwords surface an error and create NO account', async ({ page }) => {
		await gotoSignUp(page);

		// A plausible transposition: same characters, two swapped.
		const email = `e2e-mismatch-${Date.now()}@test.local`;
		await page.getByPlaceholder('Email address').fill(email);
		await pw(page).fill('runner123');
		await confirmPw(page).fill('runenr123');
		await acceptGates(page);

		await page.getByRole('button', { name: 'Sign Up' }).click();

		await expect(page.getByText(/Passwords don't match/)).toBeVisible();
		// The whole point: we never reached signUp, so there is no
		// confirmed-but-unreachable account left behind. Staying on
		// /login is the observable proxy for that — a successful signUp
		// navigates away.
		await expect(page).toHaveURL(/\/login/);
	});

	test('both password fields carry the same native minlength', async ({ page }) => {
		await gotoSignUp(page);
		// Native minlength is the first line of defence on the length
		// rule and blocks submission before the JS handler runs, so the
		// too_short branch of checkPasswordPair is a backstop for when
		// native validation is bypassed — its precedence over mismatch
		// is pinned in auth_gates.test.ts, not reachable from here.
		// What IS worth pinning here: the two fields agree, so the
		// confirmation can't be the thing that rejects a password the
		// first field accepted.
		await expect(pw(page)).toHaveAttribute('minlength', '6');
		await expect(confirmPw(page)).toHaveAttribute('minlength', '6');
	});

	test('a trailing space is treated as a real difference', async ({ page }) => {
		await gotoSignUp(page);
		await page.getByPlaceholder('Email address').fill(`e2e-space-${Date.now()}@test.local`);
		// The nastiest typo class: visually identical, and trimming
		// would silently store one of the two. Must be rejected.
		await pw(page).fill('secretpass ');
		await confirmPw(page).fill('secretpass');
		await acceptGates(page);

		await page.getByRole('button', { name: 'Sign Up' }).click();

		await expect(page.getByText(/Passwords don't match/)).toBeVisible();
		await expect(page).toHaveURL(/\/login/);
	});

	test('correcting a mismatch clears the error and proceeds', async ({ page }) => {
		await gotoSignUp(page);
		const email = `e2e-corrected-${Date.now()}@test.local`;
		await page.getByPlaceholder('Email address').fill(email);
		await pw(page).fill('goodpass123');
		await confirmPw(page).fill('goodpass124');
		await acceptGates(page);

		await page.getByRole('button', { name: 'Sign Up' }).click();
		await expect(page.getByText(/Passwords don't match/)).toBeVisible();

		// Fix the confirmation and resubmit — the error must not latch.
		await confirmPw(page).fill('goodpass123');
		await page.getByRole('button', { name: 'Sign Up' }).click();

		// Signup proceeds: either straight to the app or to the
		// check-your-email state, depending on whether the project
		// requires confirmation. Either way the mismatch error is gone.
		await expect(page.getByText(/Passwords don't match/)).toHaveCount(0);
	});
});
