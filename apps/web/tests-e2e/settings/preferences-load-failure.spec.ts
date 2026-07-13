import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/preferences — a failed settings/profile read must FAIL CLOSED
 * (uxhunt-web.md finding #3).
 *
 * The load populates the Art 9 health-consent state + demographics (gender,
 * DOB, height, weight) and every cross-device preference. Previously any load
 * failure only warned to the console and the form rendered its DEFAULTS — so a
 * user could edit and Save, round-tripping defaults back to the server and
 * silently clearing their real values (including the consent-derived fields).
 *
 * The fix: on a failed `get_my_profile` read the page shows a role="alert"
 * banner INSTEAD of the form, which gates every persist path (the auto-save
 * controls and the explicit demographics Save) until a reload succeeds.
 *
 * The auth store reads get_my_profile during auth.ready() — on init AND again
 * on the INITIAL_SESSION onAuthStateChange event — so the page's own read (made
 * after it awaits auth.ready()) is call #2 OR #3, not a fixed ordinal. We let
 * the first read succeed (it populates onboarded_at so the layout gate doesn't
 * redirect to /onboarding) and fail every read after it: the page's read fails
 * whichever ordinal it lands on, then we unblock and Retry.
 */
test.describe('/settings/preferences — load failure fails closed', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed profile read shows a load-error banner and gates every save', async ({
		page,
	}) => {
		let profileReads = 0;
		await page.route('**/rest/v1/rpc/get_my_profile**', async (route) => {
			profileReads += 1;
			// #1 = the auth store's first read (must succeed, else the layout
			// gate would redirect to /onboarding). Fail EVERY read after it: the
			// auth store reads again on the INITIAL_SESSION event, so the page's
			// own read is #2 OR #3 — a re-read failure is caught in fetchUser and
			// leaves the established user intact, while the page's read (whichever
			// ordinal) trips the load-error banner.
			if (profileReads >= 2) {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated profile-read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/settings/preferences');

		// The alert banner renders instead of the form.
		const banner = page.getByTestId('prefs-load-error');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner).toHaveAttribute('role', 'alert');

		// Every persist surface is gated: the form (and therefore the auto-save
		// controls + the explicit demographics Save) is not rendered, so a
		// failed read can't be round-tripped back as defaults.
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toHaveCount(0);
		await expect(page.getByTestId('save-demographics')).toHaveCount(0);

		// Recover: stop failing the read, Retry, and the real form appears.
		await page.unroute('**/rest/v1/rpc/get_my_profile**');
		await page.getByTestId('prefs-load-retry').click();
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
			timeout: 10_000,
		});
		await expect(page.getByTestId('save-demographics')).toBeVisible();
	});
});
