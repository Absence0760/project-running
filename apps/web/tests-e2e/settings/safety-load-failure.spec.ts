import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/safety — a failed contact read must not render as "no contacts".
 *
 * `fetchMySafetyContacts` used to console.error and return `[]`, so a
 * transient failure dropped the page into its empty state — "No safety
 * contacts yet" — for a runner who does have contacts configured. On the one
 * surface whose job is "someone is told if I don't come back", that is the
 * single most dangerous wrong answer the page can give: it invites the runner
 * to go out believing nobody is watching, or to re-add a contact that is
 * already there.
 *
 * The fix returns the error alongside the rows and the page renders a
 * role="alert" banner with a retry in place of the list.
 */
test.describe('/settings/safety — a failed read is not an empty list', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('shows a load-error banner with retry instead of the empty state', async ({ page }) => {
		let failRead = true;
		await page.route('**/rest/v1/safety_contacts*', async (route) => {
			if (failRead && route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated safety-contact read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/settings/safety');

		const banner = page.getByTestId('safety-load-error');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner).toHaveAttribute('role', 'alert');

		// The empty state must NOT be the thing a failed read shows.
		await expect(page.getByTestId('safety-empty')).toHaveCount(0);
		await expect(page.getByTestId('safety-contact-list')).toHaveCount(0);

		// Recover: the retry re-reads and the real list (or a genuine empty
		// state) takes over.
		failRead = false;
		await page.getByTestId('safety-load-retry').click();
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByTestId('safety-contact-list')).toBeVisible({ timeout: 10_000 });
	});
});
