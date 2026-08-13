import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Famous-segment catalogue BROWSE journey — the discovery half of the
 * catalogue shipped in decisions §233, which until now could only be reached
 * by already having run one of its segments.
 *
 *   1. A curator plants two catalogue segments sharing a unique token, in
 *      different regions and on different surfaces, with different lengths
 *      and one accented name.
 *   2. /segments lists both. Searching the shared token narrows the page to
 *      exactly those two, so the assertions below are independent of whatever
 *      else the seeded catalogue holds (and of a concurrently-running spec).
 *   3. The accent fold is exercised end-to-end: an ASCII query reaches the
 *      accented name.
 *   4. Sorting by longest reorders the pair; the region filter narrows to one.
 *   5. A query that matches nothing shows the filtered-empty copy, NOT the
 *      empty-catalogue copy — the two states are distinct on purpose.
 *   6. Clicking a card opens /segments/[id]; its back-link returns to the
 *      catalogue rather than the dashboard.
 *
 * Teardown removes both catalogue rows.
 */

const M_PER_DEG_LAT = 111_320;

function line(baseLat: number, lng: number, lengthM: number) {
	return [
		{ lat: baseLat, lng },
		{ lat: baseLat + lengthM / M_PER_DEG_LAT, lng }
	];
}

test.describe('famous-segment catalogue browse', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('browse, search, filter, sort, then open a catalogue segment', async ({ page }) => {
		const admin = getAdminClient();
		const token = `e2ecat${Date.now().toString(36)}`;
		const shortName = `Côte du ${token}`;
		const longName = `Boulevard ${token}`;
		const shortRegion = `Chamonix ${token}, FR`;
		const longRegion = `Sydney ${token}, AU`;

		let shortId = '';
		let longId = '';

		try {
			await test.step('a curator plants two catalogue segments', async () => {
				const { data, error } = await admin
					.from('global_segments')
					.insert([
						{
							name: shortName,
							waypoints: line(-37.51, 144.51, 600),
							distance_m: 600,
							elevation_m: 90,
							surface: 'trail',
							region: shortRegion,
							country_code: 'FR'
						},
						{
							name: longName,
							waypoints: line(-37.52, 144.52, 3000),
							distance_m: 3000,
							elevation_m: 5,
							surface: 'road',
							region: longRegion,
							country_code: 'AU'
						}
					])
					.select('id, name');
				if (error) throw error;
				const rows = (data ?? []) as { id: string; name: string }[];
				shortId = rows.find((r) => r.name === shortName)!.id;
				longId = rows.find((r) => r.name === longName)!.id;
			});

			await test.step('the browse page lists the catalogue', async () => {
				await page.goto('/segments');
				await expect(page.getByTestId('segment-catalogue-list')).toBeVisible({ timeout: 15_000 });
				await expect(page.locator(`a.card[href="/segments/${shortId}"]`)).toBeVisible();
				await expect(page.locator(`a.card[href="/segments/${longId}"]`)).toBeVisible();
			});

			await test.step('search narrows to the planted pair, newest count reported', async () => {
				await page.getByTestId('segment-catalogue-search').fill(token);
				await expect(page.locator('a.card')).toHaveCount(2);
				await expect(page.getByTestId('segment-catalogue-count')).toHaveText('2 segments');
			});

			await test.step('the query folds accents — an ASCII spelling reaches Côte', async () => {
				await page.getByTestId('segment-catalogue-search').fill(`Cote du ${token}`);
				await expect(page.locator('a.card')).toHaveCount(1);
				await expect(page.locator(`a.card[href="/segments/${shortId}"]`)).toBeVisible();
				await expect(page.getByTestId('segment-catalogue-count')).toHaveText('1 segment');
			});

			await test.step('longest-first reorders the pair', async () => {
				await page.getByTestId('segment-catalogue-search').fill(token);
				await page.getByTestId('segment-catalogue-sort').selectOption('longest');
				const hrefs = await page.locator('a.card').evaluateAll((els) =>
					els.map((el) => el.getAttribute('href'))
				);
				expect(hrefs).toEqual([`/segments/${longId}`, `/segments/${shortId}`]);

				await page.getByTestId('segment-catalogue-sort').selectOption('shortest');
				const reversed = await page.locator('a.card').evaluateAll((els) =>
					els.map((el) => el.getAttribute('href'))
				);
				expect(reversed).toEqual([`/segments/${shortId}`, `/segments/${longId}`]);
			});

			await test.step('the region filter narrows to one', async () => {
				await page.getByTestId('segment-catalogue-region').selectOption(longRegion);
				await expect(page.locator('a.card')).toHaveCount(1);
				await expect(page.locator(`a.card[href="/segments/${longId}"]`)).toBeVisible();
			});

			await test.step('a filter that matches nothing is not reported as an empty catalogue', async () => {
				await page.getByTestId('segment-catalogue-search').fill(`${token}-no-such-segment`);
				await expect(page.getByTestId('segment-catalogue-no-matches')).toBeVisible();
				await expect(page.getByTestId('segment-catalogue-empty')).toHaveCount(0);
			});

			await test.step('reset restores the full catalogue', async () => {
				await page.getByTestId('segment-catalogue-reset').click();
				await expect(page.locator(`a.card[href="/segments/${shortId}"]`)).toBeVisible();
				await expect(page.locator(`a.card[href="/segments/${longId}"]`)).toBeVisible();
			});

			await test.step('a card opens the detail page, whose back-link returns here', async () => {
				await page.locator(`a.card[href="/segments/${shortId}"]`).click();
				await page.waitForURL(`**/segments/${shortId}`);
				await expect(page.locator('h1', { hasText: shortName })).toBeVisible({ timeout: 10_000 });

				await page.locator('a.back-link').click();
				await page.waitForURL('**/segments');
				await expect(page.getByTestId('segment-catalogue-list')).toBeVisible({ timeout: 15_000 });
			});
		} finally {
			for (const id of [shortId, longId]) {
				if (!id) continue;
				await admin
					.from('global_segments')
					.delete()
					.eq('id', id)
					.then(() => {})
					.catch(() => {});
			}
		}
	});
});
