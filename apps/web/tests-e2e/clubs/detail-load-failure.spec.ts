import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] and /clubs/[slug]/events/[id] — a failed club read must not
 * claim the club does not exist.
 *
 * `fetchClubBySlug` returned `null` on any postgrest error, and both pages
 * branch on `!club`, so a transient failure told a member "Club not found —
 * back to clubs." The helper reads with `.maybeSingle()`, which already
 * distinguishes a genuine miss (`data: null, error: null`) from a failure, so
 * the information was there and was being thrown away.
 */
const CLUBS_READ = '**/rest/v1/clubs?*slug=eq.*';

test.describe('/clubs/[slug] — a failed read is not a missing club', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('shows a load error with retry, not the not-found card', async ({ page }) => {
		let failRead = true;
		await page.route(CLUBS_READ, async (route) => {
			if (failRead && route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated club read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/clubs/richmond-run-club');

		const banner = page.getByTestId('club-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		await expect(page.getByRole('heading', { name: 'Club not found' })).toHaveCount(0);

		// The retry re-reads and resolves onto the real club.
		failRead = false;
		await banner.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('club-load-error')).toHaveCount(0, { timeout: 15_000 });
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
	});

	test('a genuinely absent club still gets the not-found card', async ({ page }) => {
		await page.goto('/clubs/no-such-club-e2e');

		await expect(page.getByRole('heading', { name: 'Club not found' })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.getByTestId('club-load-error')).toHaveCount(0);
	});
});

test.describe('/clubs/[slug]/events/[id] — a failed club read', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('states the failure instead of falling through to not-found', async ({ page }) => {
		await page.route(CLUBS_READ, async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated club read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		// Any event id: the club read fails before the event is resolved.
		await page.goto('/clubs/richmond-run-club/events/00000000-0000-4000-8000-000000000abc');

		const banner = page.getByTestId('club-event-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
	});
});
