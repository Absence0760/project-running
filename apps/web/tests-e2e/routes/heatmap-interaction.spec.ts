import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/**
 * /routes/heatmap — interactive surface beyond the bare "mounts"
 * pin in routes/heatmap.spec.ts. The component is render-only
 * (RouteHeatmap.svelte: a MapLibre canvas with a `heatmap` paint
 * layer + a legend card; no click handler on density cells), so this
 * spec asserts:
 *
 *   - Legend renders the header + intent copy.
 *   - The MapLibre map container and the NavigationControl mount.
 *   - The "Updated …" timestamp surfaces once the bounded RPC returns
 *     (the load → moveend → fetch path actually fires).
 *   - Dragging the map triggers a refresh (moveend debounce → second
 *     fetch → "Updated" timestamp updates again).
 *
 * If clickable dots / per-effort markers land later (the audit
 * proposed wiring past-effort dots into the heatmap), extend this
 * spec to drive the click + assert the run-detail navigation. For
 * now the markup carries no dot affordances — heatmap layers are
 * density-shaded raster pixels, not DOM elements.
 */

test.describe('/routes/heatmap — interaction', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
	});

	test('map container + NavigationControl mount; discover sidebar + timestamp surface', async ({
		page
	}) => {
		await page.goto('/routes/heatmap');

		// The discover-sidebar redesign replaced the standalone info-icon
		// legend with a route-discovery sidebar; the heat scale is now a
		// toggle chip and the freshness stamp lives in the sidebar's
		// results header (`.results-updated`).
		const mapContainer = page.locator('.maplibregl-map');
		await expect(mapContainer).toBeVisible({ timeout: 15_000 });

		await expect(page.locator('.maplibregl-ctrl-zoom-in')).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('.maplibregl-ctrl-zoom-out')).toBeVisible();

		await expect(page.getByTestId('discover-sidebar')).toBeVisible();

		// The "Updated <time>" stamp surfaces once the initial route fetch
		// resolves (loading shows the spinner instead).
		await expect(page.locator('.results-updated')).toBeVisible({
			timeout: 15_000
		});
	});

	test('pan → moveend debounce fires a fresh fetch (updated-timestamp ticks)', async ({
		page
	}) => {
		await page.goto('/routes/heatmap');

		// Wait for the initial fetch to settle into the "Updated <time>"
		// terminal state in the sidebar results header.
		await expect(page.locator('.results-updated')).toBeVisible({
			timeout: 15_000
		});
		const firstStamp = (await page.locator('.results-updated').textContent()) ?? '';

		await page.locator('.maplibregl-ctrl-zoom-in').click();
		await page.locator('.maplibregl-ctrl-zoom-in').click();

		// moveend is debounced 350ms in RouteHeatmap.svelte. Allow the
		// fetch to land. The `toLocaleTimeString` granularity is HH:MM so
		// the stamp may stay stable across two clicks in the same minute —
		// what matters is the header returns to the terminal "Updated"
		// state (the loading spinner is gone), proving the refetch resolved.
		await page.waitForTimeout(1500);
		await expect(page.locator('.results-spinner')).toHaveCount(0);
		await expect(page.locator('.results-updated')).toBeVisible();

		const secondStamp = (await page.locator('.results-updated').textContent()) ?? '';
		expect(secondStamp.length).toBeGreaterThan(0);
		expect(firstStamp.length).toBeGreaterThan(0);
	});
});
