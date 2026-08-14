import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * A `date` column names a calendar day, and must render as that day in every
 * timezone. `new Date('2026-11-15')` is UTC midnight per ECMA-262, so the old
 * formatters rendered the day before everywhere west of Greenwich.
 *
 * The suite pins `timezoneId: 'UTC'` globally, which is exactly why this never
 * surfaced in CI — a positive-or-zero offset hides it entirely. These tests
 * override the timezone to a negative offset, which is the only way to catch
 * the class from the browser.
 */
test.describe('date-only columns render their own calendar day', () => {
	const stamp = Date.now();
	const raceName = `E2E TZ Race ${stamp}`;
	// A fixed future date whose rendering must not depend on the viewer's
	// timezone. Deliberately not derived from today — the point is the literal.
	const raceDate = '2027-11-15';
	let listingId: string | null = null;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('race_listings')
			.insert({
				provider: 'manual',
				name: raceName,
				race_date: raceDate,
				distance_m: 21097,
				is_verified: true,
			})
			.select('id')
			.single();
		listingId = (data as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (listingId) await admin.from('race_listings').delete().eq('id', listingId);
	});

	test.describe('west of Greenwich', () => {
		test.use({ storageState: USER_A.storageStatePath, timezoneId: 'America/New_York' });

		test('a race date does not slip to the previous day', async ({ page }) => {
			await page.goto('/races');
			await page.getByTestId('races-search').fill(raceName);
			const card = page
				.getByTestId('races-results')
				.getByTestId('race-card')
				.filter({ hasText: raceName });
			await expect(card).toBeVisible({ timeout: 10_000 });
			await expect(card).toContainText('15 Nov 2027');
			await expect(card).not.toContainText('14 Nov 2027');
		});
	});

	test.describe('east of Greenwich', () => {
		test.use({ storageState: USER_A.storageStatePath, timezoneId: 'Asia/Tokyo' });

		test('and reads identically on the other side of the world', async ({ page }) => {
			await page.goto('/races');
			await page.getByTestId('races-search').fill(raceName);
			const card = page
				.getByTestId('races-results')
				.getByTestId('race-card')
				.filter({ hasText: raceName });
			await expect(card).toBeVisible({ timeout: 10_000 });
			await expect(card).toContainText('15 Nov 2027');
		});
	});
});
