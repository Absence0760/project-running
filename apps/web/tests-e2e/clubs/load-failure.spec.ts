import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /clubs (SocialClubs panel) — a failed clubs fetch must show a distinct
 * error + retry card, NOT the friendly "no clubs yet" empty state.
 *
 * Before the fix, browseClubs / fetchMyClubs discarded the PostgREST
 * error and returned [], so a network / RLS / RPC failure rendered the
 * empty card — telling the user there are no clubs when the fetch
 * actually failed. The WithError variants now surface the error and the
 * panel renders an alert with Try again.
 */

test.describe('/clubs — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed My-clubs fetch shows the error card, not the empty state', async ({
		page
	}) => {
		// My clubs is the default subtab; it fetches via club_members.
		await page.route('**/rest/v1/club_members*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated club_members failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto('/clubs');

		// Error card surfaces with a retry — and the "no clubs yet" empty
		// copy must NOT be what the user sees.
		await expect(page.getByText("Couldn't load clubs")).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
		await expect(page.getByText("You haven't joined a club yet")).toHaveCount(0);
	});

	test('Try again re-fetches and clears the error on a healthy response', async ({
		page
	}) => {
		// Fail the first My-clubs GET, then return a clean (empty) success
		// so the retry path is exercised without depending on the seeded
		// membership rows surviving a future schema change.
		let failNext = true;
		await page.route('**/rest/v1/club_members*', async (route) => {
			if (route.request().method() !== 'GET') {
				await route.continue();
				return;
			}
			if (failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated club_members failure' })
				});
			} else {
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify([])
				});
			}
		});

		await page.goto('/clubs');
		await expect(page.getByText("Couldn't load clubs")).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Try again' }).click();

		// The retry succeeds (empty result): the error alert clears and the
		// friendly empty state takes its place.
		await expect(page.getByText("Couldn't load clubs")).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByText("You haven't joined a club yet")).toBeVisible({ timeout: 10_000 });
	});
});
