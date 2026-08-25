import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/account — profile + email / password / parkrun number /
 * DOB / HR fields. Covers the display-name round-trip + the
 * change-password validation branches; future depth: parkrun number
 * import button, profile avatar upload, account deletion.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/settings/account', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('display name update — save persists across reload, restore', async ({
		page
	}) => {
		// Profile saves write to user_profiles.display_name (visible
		// across the app — feed, kudos, comments, /u/[id]). The
		// regression risk is that a save returns 200 but RLS blocks
		// the update silently, or the optimistic local state masks a
		// failed write. Reload-then-assert covers both.
		const newName = uniqueText('e2e-name');
		const originalName = 'Jared Howard';

		await page.goto('/settings/account');

		const nameInput = page.getByLabel('Display Name');
		await expect(nameInput).toHaveValue(originalName);
		await nameInput.fill(newName);

		await page.getByRole('button', { name: /Save Profile/ }).click();
		// `handleSave` flips the button label to "Saved!" once the
		// upsert resolves — wait for that before reloading so the
		// reload sees a persisted value, not in-flight optimistic UI.
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await expect(page.getByLabel('Display Name')).toHaveValue(newName);

		// Restore so the spec is idempotent.
		await page.getByLabel('Display Name').fill(originalName);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
		await page.reload();
		await expect(page.getByLabel('Display Name')).toHaveValue(originalName);
	});

	test('parkrun athlete number save persists across reload', async ({
		page
	}) => {
		// parkrun_number is a text column on user_profiles that the
		// parkrun importer uses to find the user's results page. A
		// regression that dropped the field from the save payload
		// would surface here. Use a placeholder-style value (no real
		// athletes hit by leaking it) and restore.
		await page.goto('/settings/account');
		// Needed: inputValue() snapshots — no auto-retry — so the read
		// would capture the pre-fetch default rather than the user's
		// persisted value.
		await page.waitForLoadState('networkidle');

		const input = page.getByLabel(/parkrun Athlete Number/);
		const before = await input.inputValue();
		const next = `A${Date.now()}`.slice(0, 9);

		await input.fill(next);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await expect(page.getByLabel(/parkrun Athlete Number/)).toHaveValue(next);

		// Restore.
		await page.getByLabel(/parkrun Athlete Number/).fill(before);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
	});

	test('Resting HR save persists across reload', async ({ page }) => {
		// resting_hr_bpm lives in user_settings.prefs, not user_profiles.
		// The Save handler stitches the two writes together; a regression
		// that dropped the prefs branch would let HR slip while
		// display_name persisted.
		await page.goto('/settings/account');
		// Needed: inputValue() snapshots — no auto-retry — so the read
		// would capture the pre-fetch default rather than the user's
		// persisted setting.
		await page.waitForLoadState('networkidle');

		const hr = page.getByLabel(/Resting HR/);
		const before = await hr.inputValue();
		const next = '54';

		await hr.fill(next);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await expect(page.getByLabel(/Resting HR/)).toHaveValue(next);

		await page.getByLabel(/Resting HR/).fill(before);
		await page.getByRole('button', { name: /Save Profile/ }).click();
		await expect(page.getByRole('button', { name: 'Saved!' })).toBeVisible({
			timeout: 5_000
		});
	});

	test('Date of birth input caps at today and leaves birth years unbounded', async ({
		page
	}) => {
		// Mirrors /settings/preferences + /onboarding: `max` of today
		// blocks a future DOB, and no `min` fences off realistic birth
		// years decades back (issue #222).
		await page.goto('/settings/account');
		const dob = page.getByLabel('Date of Birth', { exact: true });
		const max = await dob.getAttribute('max');
		expect(max).toMatch(/^\d{4}-\d{2}-\d{2}$/);
		expect(Math.abs(Date.parse(`${max}T00:00:00Z`) - Date.now())).toBeLessThan(
			48 * 3600 * 1000
		);
		expect(await dob.getAttribute('min')).toBeNull();
	});

	test('the DOB field is not disabled by the health-data consent box', async ({
		page
	}) => {
		// decisions § 718: this input feeds the user_profiles age record
		// behind the under-18 discoverability floor, which does not rest on
		// Art 9 consent. Disabling it also deadlocked the page — the save
		// aborted on a stored DOB the runner could not clear. In-memory only:
		// the box is restored and nothing is saved.
		await page.goto('/settings/account');
		const consent = page
			.locator('label.consent-checkbox')
			.locator('input[type="checkbox"]')
			.first();
		const startedChecked = await consent.isChecked();
		if (startedChecked) await consent.uncheck();
		await expect(page.getByTestId('date-of-birth')).toBeEnabled();
		if (startedChecked) await consent.check();
	});

	// Change-password validation. This section MINTS a password
	// (updateUser), so it shares checkPasswordPair with /login?signup=1
	// and /auth/reset — see web_app_auth.md § Password confirmation.
	//
	// Only the REJECTION branches are exercised: a successful save would
	// rotate USER_A's password out from under storageStatePath and every
	// other spec that signs in as them. Every case below returns before
	// updateUser is called, which is exactly why they're safe to run
	// against the shared fixture user.
	test.describe('change password — step-up + validation', () => {
		// A live access token must not be enough to rotate the password
		// (issue #381, OWASP ASVS V2.1.14). Belt-and-braces for the shared
		// fixture: PUT /auth/v1/user is aborted, so even a regression that
		// skipped the current-password proof can't change USER_A's password.
		const guardUpdateUser = async (page: import('@playwright/test').Page) => {
			const seen = { put: 0 };
			await page.route('**/auth/v1/user', async (route) => {
				if (route.request().method() !== 'PUT') {
					await route.continue();
					return;
				}
				seen.put += 1;
				await route.abort();
			});
			return seen;
		};

		test('a wrong current password is rejected and never reaches updateUser', async ({
			page
		}) => {
			const seen = await guardUpdateUser(page);
			// Only the password grant is stubbed — the refresh_token grant
			// on the same endpoint has to keep working or the session dies
			// mid-test.
			await page.route('**/auth/v1/token**', async (route) => {
				if (!route.request().url().includes('grant_type=password')) {
					await route.continue();
					return;
				}
				await route.fulfill({
					status: 400,
					contentType: 'application/json',
					body: JSON.stringify({
						error: 'invalid_grant',
						error_description: 'Invalid login credentials'
					})
				});
			});

			await page.goto('/settings/account');
			await page.getByLabel('Current Password').fill('not-my-password');
			await page.getByLabel('New Password').fill('longenough1');
			await page.getByLabel('Confirm Password').fill('longenough1');
			await page.getByRole('button', { name: 'Save Password' }).click();

			await expect(
				page.getByText('That current password is incorrect.', { exact: false })
			).toBeVisible();
			expect(seen.put).toBe(0);
		});

		test('Save Password stays disabled until the current password is entered', async ({
			page
		}) => {
			await page.goto('/settings/account');
			const save = page.getByRole('button', { name: 'Save Password' });
			await page.getByLabel('New Password').fill('longenough1');
			await page.getByLabel('Confirm Password').fill('longenough1');
			await expect(save).toBeDisabled();

			await page.getByLabel('Current Password').fill('anything');
			await expect(save).toBeEnabled();
		});

		test('mismatched entries are rejected before the current password is sent', async ({
			page
		}) => {
			const seen = await guardUpdateUser(page);
			let sawGrant = false;
			await page.route('**/auth/v1/token**', async (route) => {
				if (route.request().url().includes('grant_type=password')) sawGrant = true;
				await route.continue();
			});

			await page.goto('/settings/account');
			await page.getByLabel('Current Password').fill('irrelevant');
			await page.getByLabel('New Password').fill('longenough1');
			await page.getByLabel('Confirm Password').fill('longenough2');
			await page.getByRole('button', { name: 'Save Password' }).click();

			await expect(page.getByText('Passwords do not match.')).toBeVisible();
			// The local check runs first, so a typo in the new field never
			// burns a sign-in attempt against GoTrue's rate limit.
			expect(sawGrant).toBe(false);
			expect(seen.put).toBe(0);
		});

		test('a too-short entry reports length, not mismatch', async ({ page }) => {
			await page.goto('/settings/account');
			// Short AND mismatched: length is the user's real problem, so
			// reporting a mismatch would send them round the loop fixing
			// the wrong thing. Pins the precedence through the UI.
			await page.getByLabel('Current Password').fill('irrelevant');
			await page.getByLabel('New Password').fill('abc');
			await page.getByLabel('Confirm Password').fill('xyz');
			await page.getByRole('button', { name: 'Save Password' }).click();

			await expect(
				page.getByText('Password must be at least 8 characters.')
			).toBeVisible();
			await expect(page.getByText('Passwords do not match.')).toHaveCount(0);
		});
	});

	// Change-email request path. `auth.updateUser({ email })` starts
	// GoTrue's secure double-confirmation (a link to BOTH the old and
	// the new address) — issue #245. The PUT /auth/v1/user call is
	// STUBBED so the spec verifies the request → pending-UI seam without
	// actually rotating USER_A's real address out from under every other
	// spec that signs in as them.
	test.describe('change email — request path', () => {
		test('an invalid or unchanged address is rejected before any request', async ({
			page
		}) => {
			let sawRequest = false;
			await page.route('**/auth/v1/user', async (route) => {
				if (route.request().method() === 'PUT') sawRequest = true;
				await route.continue();
			});

			await page.goto('/settings/account');
			await page.getByTestId('change-email').click();
			// Same address as the current one — the guard must catch it
			// (a no-op change-email would still fire GoTrue mail).
			await page.getByTestId('new-email-input').fill(USER_A.email);
			await page.getByTestId('submit-email-change').click();

			await expect(page.locator('[role="alert"]')).toBeVisible();
			await expect(page.getByTestId('email-change-pending')).toHaveCount(0);
			expect(sawRequest).toBe(false);
		});

		test('a valid new address requests the change and shows the pending state', async ({
			page
		}) => {
			await page.route('**/auth/v1/user', async (route) => {
				if (route.request().method() !== 'PUT') {
					await route.continue();
					return;
				}
				// GoTrue returns the user row unchanged (email flips only
				// after both confirmations); a bare 200 is enough for the
				// SDK to resolve without an error.
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ id: '00000000-0000-0000-0000-000000000000' })
				});
			});

			await page.goto('/settings/account');
			await page.getByTestId('change-email').click();
			const next = `e2e-change-${Date.now()}@test.local`;
			await page.getByTestId('new-email-input').fill(next);
			await page.getByTestId('submit-email-change').click();

			// The pending banner names both inboxes; the editor collapses.
			const pending = page.getByTestId('email-change-pending');
			await expect(pending).toBeVisible();
			await expect(pending).toContainText(next);
			await expect(pending).toContainText(USER_A.email);
			await expect(page.getByTestId('new-email-input')).toHaveCount(0);
		});
	});
});
