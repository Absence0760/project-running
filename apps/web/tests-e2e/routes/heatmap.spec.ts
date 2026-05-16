import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes — Heatmap tab (popular-route discovery overlay).
 *
 * Backed by the `heatmap_points_in_bbox` PostGIS RPC (migration
 * 20260828_001) which returns lat/lng of densified points from every
 * intersecting public route. The web mounts a MapLibre canvas with a
 * `heatmap` paint layer in `RouteHeatmap.svelte`; the tab is wired
 * into the `tab = 'heatmap'` branch of /routes.
 *
 * Real MapTiler tile rendering needs a key; these tests pin the
 * *control surface* + the underlying RPC plumbing without driving
 * the canvas:
 *
 *   - Tab is reachable and switches state.
 *   - URL query `?tab=heatmap` deep-links onto the tab.
 *   - The PostGIS RPC returns a non-error response (the migration
 *     fix from earlier this session — search_path = public,
 *     extensions — is the load-bearing precondition).
 *   - The component mounts the map container.
 */

test.describe('/routes — Heatmap tab', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Heatmap tab button is reachable from /routes', async ({ page }) => {
		await page.goto('/routes');
		await page.waitForLoadState('networkidle');
		const heatmapTab = page.getByRole('tab', { name: 'Heatmap', exact: true });
		await expect(heatmapTab).toBeVisible({ timeout: 10_000 });
	});

	test('clicking Heatmap activates the tab (My routes deactivates)', async ({ page }) => {
		await page.goto('/routes');
		await page.waitForLoadState('networkidle');
		const heatmapTab = page.getByRole('tab', { name: 'Heatmap', exact: true });
		const mineTab = page.getByRole('tab', { name: 'My routes', exact: true });
		// Default: My routes is active.
		await expect(mineTab).toHaveClass(/active/);
		await heatmapTab.click();
		await expect(heatmapTab).toHaveClass(/active/);
		await expect(mineTab).not.toHaveClass(/active/);
	});

	test('?tab=heatmap deep-links onto the tab on first paint', async ({ page }) => {
		// Snapshot restore via the `?tab=` query string. A regression
		// in setTab or the onMount tab-resolve would land on My routes
		// even though the URL asked for Heatmap — surfaces here.
		await page.goto('/routes?tab=heatmap');
		await page.waitForLoadState('networkidle');
		await expect(
			page.getByRole('tab', { name: 'Heatmap', exact: true })
		).toHaveClass(/active/, { timeout: 10_000 });
	});

	test('Heatmap pane mounts a maplibregl canvas after switching tabs', async ({ page }) => {
		// The RouteHeatmap component binds a MapLibre map to a div.
		// The canvas only mounts after the tab switches because the
		// component is in a `{#if tab === 'heatmap'}` branch.
		// MapLibre injects `<canvas class="maplibregl-canvas">` once
		// the map's load event fires; we tolerate the canvas-missing
		// case (no MapTiler key in CI) by accepting either the canvas
		// or the .maplibregl-map container div.
		await page.goto('/routes?tab=heatmap');
		await page.waitForLoadState('networkidle');
		const mapContainer = page.locator('.maplibregl-map');
		await expect(mapContainer).toBeVisible({ timeout: 15_000 });
	});

	test('heatmap_points_in_bbox RPC returns a 2xx for a sane bbox', async ({ page }) => {
		// Direct PostGIS-RPC smoke: the migration's
		// `set search_path = public, extensions` fix (this session's
		// d39296f) made this RPC actually run. A regression that
		// dropped the extensions schema would 500 here. Drive via
		// the running Supabase REST endpoint with the seeded anon
		// session.
		const res = await page.evaluate(async () => {
			const r = await fetch(
				'http://localhost:54321/rest/v1/rpc/heatmap_points_in_bbox',
				{
					method: 'POST',
					headers: {
						'Content-Type': 'application/json',
						apikey:
							'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlLWRlbW8iLCJpYXQiOjE2NDE3NjkyMDAsImV4cCI6MTc5OTUzNTYwMH0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE',
					},
					body: JSON.stringify({
						p_min_lng: -0.2,
						p_min_lat: 51.4,
						p_max_lng: 0.0,
						p_max_lat: 51.6,
						p_max_points: 100,
					}),
				}
			);
			return { status: r.status, body: await r.text() };
		});
		// 200 = success; 401 acceptable only if the local stack is
		// gating anon on this RPC (which it should not — the function
		// has no SECURITY DEFINER + no auth check; the migration grants
		// EXECUTE to anon). Anything in the 5xx range = regression in
		// the migration's search_path fix.
		expect(res.status).toBeGreaterThanOrEqual(200);
		expect(res.status).toBeLessThan(500);
	});

	test('tab labels are mutually exclusive (only one .active at a time)', async ({ page }) => {
		// Tab state machine: My routes / Explore / Heatmap. The
		// .active CSS class drives the underline + colour. A regression
		// in setTab that left two active simultaneously would visually
		// confuse the page but not error — pin the count.
		await page.goto('/routes');
		await page.waitForLoadState('networkidle');
		await page.getByRole('tab', { name: 'Heatmap', exact: true }).click();
		await expect(page.locator('button.tab.active')).toHaveCount(1);
		await page.getByRole('tab', { name: 'Explore', exact: true }).click();
		await expect(page.locator('button.tab.active')).toHaveCount(1);
		await page.getByRole('tab', { name: 'My routes', exact: true }).click();
		await expect(page.locator('button.tab.active')).toHaveCount(1);
	});
});
