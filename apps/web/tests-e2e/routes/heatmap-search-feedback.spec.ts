import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Place search must distinguish "no such place" from "the search failed".
 *
 * Both used to collapse into an empty array in `searchPlacesWithKey`, and
 * because the dropdown only opened on a non-empty result set, a failed
 * geocoder lookup produced NO feedback at all — a runner typing a real
 * place name on a flaky connection was told nothing whatsoever.
 *
 * These tests force each provider outcome at the network boundary and
 * assert the three states the dropdown now has: results, no-results, and
 * unavailable-with-retry.
 */

// Both providers are intercepted regardless of which one the build
// dispatches to (MapTiler when PUBLIC_MAPTILER_KEY is set, Nominatim
// otherwise), so the spec doesn't depend on the local env's key.
//
// Anchored at the scheme so it can only match these two origins — an
// unanchored host pattern also matches a URL that merely contains the
// string. Scoped to each provider's SEARCH path for a second reason:
// MapTiler serves map tiles from the same host, and a host-wide pattern
// intercepts those too, so the failure this spec injects gets spent on a
// tile fetch instead of the geocoding call under test.
const GEOCODER_GLOB =
	/^https:\/\/(nominatim\.openstreetmap\.org\/search|api\.maptiler\.com\/geocoding\/)/;

const MAPTILER_HOST = 'api.maptiler.com';

// Compares the parsed hostname rather than substring-matching the URL, for
// the same reason.
function isMapTiler(url: string): boolean {
	return new URL(url).hostname === MAPTILER_HOST;
}

// The two providers disagree on response shape, and which one a build
// dispatches to depends on whether PUBLIC_MAPTILER_KEY is set. Canning one
// shape would make a passing spec depend on the local env's key — so pick
// the shape off the intercepted URL instead.
function oneHitBody(url: string): string {
	return isMapTiler(url)
		? JSON.stringify({
			features: [{ place_name: 'Richmond, Virginia', center: [-77.436, 37.5407] }],
		})
		: JSON.stringify([
			{ display_name: 'Richmond, Virginia', lat: '37.5407', lon: '-77.4360' },
		]);
}

function emptyBody(url: string): string {
	return isMapTiler(url) ? JSON.stringify({ features: [] }) : '[]';
}

test.describe('heatmap place-search feedback', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Deliberately does NOT wait on `.maplibregl-map`: the search box lives
	// in the discovery sidebar and its feedback contract holds whether or
	// not the tile layer came up, so gating on the canvas would couple this
	// spec to whether a tile key / local Protomaps stack is configured.
	async function openHeatmapAndSearch(page: import('@playwright/test').Page) {
		await page.goto('/routes/heatmap');
		const input = page.getByTestId('heatmap-search').getByRole('textbox');
		await expect(input).toBeVisible({ timeout: 15_000 });
		await input.fill('Richmond');
		return input;
	}

	test('a failed geocoder lookup says the search is unavailable and offers a retry',
		async ({ page }) => {
			await page.route(GEOCODER_GLOB, (route) => route.abort('failed'));

			await openHeatmapAndSearch(page);

			const status = page.getByTestId('heatmap-search-unavailable');
			await expect(status).toBeVisible({ timeout: 10_000 });
			// The failure must never be dressed up as an empty result set.
			await expect(page.getByTestId('heatmap-search-empty')).toHaveCount(0);
			await expect(status.getByRole('button')).toBeVisible();
		});

	test('a 429 from the geocoder reads as unavailable, not as no-results',
		async ({ page }) => {
			// The rate-limited case is the one most likely to be hit in
			// production, and the one an empty-list fallback misrepresents most
			// badly: a throttled search claiming the place does not exist.
			await page.route(GEOCODER_GLOB, (route) =>
				route.fulfill({ status: 429, body: 'rate limited' }));

			await openHeatmapAndSearch(page);

			await expect(page.getByTestId('heatmap-search-unavailable'))
				.toBeVisible({ timeout: 10_000 });
		});

	test('a genuinely empty result set says no places were found', async ({ page }) => {
		await page.route(GEOCODER_GLOB, (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: emptyBody(route.request().url()),
			}));

		await openHeatmapAndSearch(page);

		await expect(page.getByTestId('heatmap-search-empty'))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('heatmap-search-unavailable')).toHaveCount(0);
	});

	test('retrying after the geocoder recovers shows the results', async ({ page }) => {
		// Proves the retry control actually re-runs the lookup rather than
		// only clearing the banner.
		let failNext = true;
		await page.route(GEOCODER_GLOB, (route) => {
			if (failNext) {
				failNext = false;
				return route.abort('failed');
			}
			return route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: oneHitBody(route.request().url()),
			});
		});

		await openHeatmapAndSearch(page);

		const status = page.getByTestId('heatmap-search-unavailable');
		await expect(status).toBeVisible({ timeout: 10_000 });

		await status.getByRole('button').click();

		await expect(page.getByRole('button', { name: /Richmond, Virginia/ }))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('heatmap-search-unavailable')).toHaveCount(0);
	});
});
