import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Race calendar discovery (migration 20270214_001) — the /races surface over
 * the search_race_listings RPC. Seeds a manual, future-dated, verified listing
 * and confirms it surfaces, responds to the name + distance-band filters, and
 * exposes its registration link. Then submits a crowd listing through the
 * editor and confirms it lands (unverified).
 */

test.describe('/races — calendar discovery', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const raceName = `E2E Half ${stamp}`;
	const future = '2027-09-12';
	let listingId: string | null = null;
	const submitted: string[] = [];

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('race_listings')
			.insert({
				provider: 'manual',
				name: raceName,
				race_date: future,
				distance_m: 21097,
				location_label: 'Richmond, VA',
				entry_url: 'https://example.com/register',
				is_verified: true
			})
			.select('id')
			.single();
		listingId = (data as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (listingId) await admin.from('race_listings').delete().eq('id', listingId);
		for (const name of submitted) await admin.from('race_listings').delete().eq('name', name);
	});

	test('name + distance-band filters surface a listing with a register link', async ({ page }) => {
		await page.goto('/races');

		await page.getByTestId('races-search').fill(raceName);
		const results = page.getByTestId('races-results');
		const card = results.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 10_000 });

		// The register link points at the listing's entry_url.
		await expect(card.getByTestId('race-register')).toHaveAttribute(
			'href',
			'https://example.com/register'
		);

		// Half-marathon band keeps it; 5K drops it.
		await page.getByTestId('races-dist-half').click();
		await expect(card).toBeVisible();
		await page.getByTestId('races-dist-5k').click();
		await expect(card).toBeHidden({ timeout: 10_000 });
	});

	test('submitting a manual listing lands it (unverified)', async ({ page }) => {
		const newName = `E2E Submitted ${stamp}`;
		submitted.push(newName);

		await page.goto('/races');
		await page.getByTestId('race-submit').click();

		await page.getByTestId('race-name').fill(newName);
		await page.getByTestId('race-date').fill('2027-10-01');
		await page.getByTestId('race-distance').fill('10000');
		await page.getByTestId('race-save').click();

		// It refreshes into the list; a crowd listing is unverified.
		await page.getByTestId('races-search').fill(newName);
		const card = page.getByTestId('races-results').getByTestId('race-card').filter({ hasText: newName });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('race-unverified')).toBeVisible();
	});
});
