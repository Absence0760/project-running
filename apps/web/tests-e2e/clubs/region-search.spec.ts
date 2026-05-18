import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /social?tab=clubs — region-aware Browse search.
 *
 * `searchClubs` geocodes the query via MapTiler, then passes the
 * centroid + a bbox-derived radius into the `search_clubs` RPC so
 * "Virginia" pulls clubs that are physically *in* Virginia even when
 * their `location_label` is "Richmond, VA" — i.e. no "Virginia"
 * substring to match via ILIKE. See migration 20260905_001.
 *
 * MapTiler isn't reachable from CI (no key), so we intercept the
 * geocoding endpoint with `page.route` and return a synthetic feature
 * for "Virginia". A real-server hit is exercised in dev manually per
 * apps/web/local_testing.md.
 */

const plantedClubIds: string[] = [];

const VIRGINIA_GEOCODE = {
	type: 'FeatureCollection',
	features: [
		{
			type: 'Feature',
			place_name: 'Virginia, United States',
			text: 'Virginia',
			center: [-78.6569, 37.4316],
			bbox: [-83.675, 36.541, -75.166, 39.466],
			place_type: ['region'],
		},
	],
};

test.describe('clubs Browse — geocoded region search', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		if (plantedClubIds.length === 0) return;
		const admin = getAdminClient();
		await admin.from('clubs').delete().in('id', plantedClubIds);
		plantedClubIds.length = 0;
	});

	test('searching "Virginia" surfaces a club whose location_point is in VA but label has no "Virginia" substring', async ({
		page,
	}) => {
		const admin = getAdminClient();

		// Plant a club inside Virginia with a location_label that does
		// NOT contain the string "Virginia". The ILIKE branch can't
		// match this — only the ST_DWithin branch on location_point
		// will surface it.
		const uniqueSuffix = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const name = `Geosearch Tempo Crew ${uniqueSuffix}`;
		const slug = `geosearch-tempo-${uniqueSuffix}`;
		const { data, error } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name,
				slug,
				description: 'Region-search e2e seed',
				location_label: 'Richmond, VA',
				// Richmond, VA — ~37.54N, -77.43E. Will land inside the
				// "Virginia" bbox returned by the geocode mock.
				location_point: 'SRID=4326;POINT(-77.4360 37.5407)',
				is_public: true,
				join_policy: 'open',
			})
			.select('id')
			.single();
		if (error || !data) throw new Error(`seed club insert failed: ${error?.message}`);
		plantedClubIds.push(data.id as string);

		// Intercept MapTiler geocoding so the test doesn't depend on a
		// real API key. Match any query — `searchClubs` URL-encodes the
		// term into the path.
		await page.route('**/api.maptiler.com/geocoding/**', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify(VIRGINIA_GEOCODE),
			}),
		);

		await page.goto('/social?tab=clubs&clubs-sub=browse');
		await page.waitForLoadState('networkidle');

		// Wait for the initial Browse load to settle.
		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' }),
		).toBeVisible({ timeout: 10_000 });

		await page.getByPlaceholder(/Search by name/).fill('Virginia');

		// Geographic match should appear. The seeded "Geosearch Tempo
		// Crew" club has no "Virginia" in its name or label, so this
		// asserts the geographic branch fired.
		await expect(page.getByRole('heading', { name })).toBeVisible({
			timeout: 10_000,
		});

		// Sydney Run Club should NOT appear — Sydney is far outside the
		// Virginia bbox, and its label doesn't contain "Virginia".
		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' }),
		).toHaveCount(0);
	});

	test('falls back to ILIKE on label when MapTiler returns no feature', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const uniqueSuffix = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const name = `Virginia Trail Runners ${uniqueSuffix}`;
		const slug = `virginia-trail-runners-${uniqueSuffix}`;

		// This time the club's name itself contains "Virginia", so it
		// must surface via the text branch even when geocoding fails.
		// No location_point — we're not testing the geographic branch
		// here.
		const { data, error } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name,
				slug,
				description: 'ILIKE-fallback seed',
				location_label: 'Northern Virginia',
				is_public: true,
				join_policy: 'open',
			})
			.select('id')
			.single();
		if (error || !data) throw new Error(`seed club insert failed: ${error?.message}`);
		plantedClubIds.push(data.id as string);

		// MapTiler returns an empty feature collection — geocoding
		// returns null → searchClubs calls the RPC with no centre →
		// only the ILIKE branch can match.
		await page.route('**/api.maptiler.com/geocoding/**', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ type: 'FeatureCollection', features: [] }),
			}),
		);

		await page.goto('/social?tab=clubs&clubs-sub=browse');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' }),
		).toBeVisible({ timeout: 10_000 });

		await page.getByPlaceholder(/Search by name/).fill('Virginia');

		await expect(page.getByRole('heading', { name })).toBeVisible({
			timeout: 10_000,
		});
	});
});
