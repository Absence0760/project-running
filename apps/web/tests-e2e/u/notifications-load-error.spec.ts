import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /u/[me]?tab=notifications (NotificationsList) — a failed notifications
 * fetch must show a distinct error + retry banner, NOT the friendly
 * "No notifications yet / Find people" empty state.
 *
 * Before the fix, fetchNotifications swallowed the PostgREST error and
 * returned [], so a network / RLS failure rendered the empty inbox —
 * telling the user they have zero notifications when the fetch actually
 * failed. fetchNotificationsWithError now surfaces the error and the
 * inbox renders an alert with a retry.
 */

test.describe('/u/[me]?tab=notifications — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed notifications fetch shows the error banner, not the empty inbox', async ({
		page
	}) => {
		await page.route('**/rest/v1/notifications*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated notifications failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/u/${USER_A.id}?tab=notifications`);

		// The error banner surfaces with a retry — and the empty-inbox copy
		// must NOT be what the user sees.
		await expect(page.getByText("Couldn't load this profile.")).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('button', { name: 'Retry' })).toBeVisible();
		await expect(page.getByText('No notifications yet', { exact: false })).toHaveCount(0);
		await expect(page.getByRole('link', { name: 'Find people' })).toHaveCount(0);
	});

	test('Retry re-fetches and clears the error on a healthy response', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/notifications*', async (route) => {
			if (route.request().method() !== 'GET') {
				await route.continue();
				return;
			}
			if (failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated notifications failure' })
				});
			} else {
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify([])
				});
			}
		});

		await page.goto(`/u/${USER_A.id}?tab=notifications`);
		await expect(page.getByText("Couldn't load this profile.")).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Retry' }).click();

		// The retry succeeds (empty result): the error clears and the
		// friendly empty state takes its place.
		await expect(page.getByText("Couldn't load this profile.")).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByText('No notifications yet', { exact: false })).toBeVisible({
			timeout: 10_000
		});
	});
});
