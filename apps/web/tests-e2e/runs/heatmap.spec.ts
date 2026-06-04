import { expect, test } from '@playwright/test';

import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

// A short GPS track around Richmond, VA — enough distinct points to form
// heat cells AND a polyline. The seed runs carry track_url values whose
// gzipped blobs aren't staged in local Storage (downloads fail and are
// swallowed as L4 best-effort), so the personal heatmap has no data to plot
// unless a test stages a real track. This gives the legend + line layer
// something to render.
const HEATMAP_TRACK = Array.from({ length: 12 }, (_, i) => ({
	lat: 37.5407 + i * 0.0008,
	lng: -77.436 + i * 0.0006,
	t: new Date(Date.UTC(2026, 0, 1, 8, i)).toISOString()
}));

test.describe('/runs/heatmap — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('anon is bounced to sign-in by the runs auth guard, no map', async ({ page }) => {
		await page.goto('/runs/heatmap');
		await expect(page.getByRole('heading', { name: /Sign in/i })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('personal-heatmap-map')).toHaveCount(0);
	});
});

test.describe('/runs/heatmap — signed-in seed user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let heatRunId: string | null = null;
	test.beforeEach(async () => {
		// Stage one run with a real (uploaded) track so the heatmap resolves
		// to data — the seed runs' track blobs aren't present in local Storage.
		heatRunId = await insertRun({
			user_id: USER_A.id,
			duration_s: 1800,
			distance_m: 5000,
			track: HEATMAP_TRACK
		});
	});
	test.afterEach(async () => {
		if (heatRunId) await deleteRun(heatRunId);
		heatRunId = null;
	});

	test('renders the heading + map and resolves loading to legend or empty', async ({ page }) => {
		await page.goto('/runs/heatmap');
		await expect(page.getByRole('heading', { name: 'Your heatmap' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('personal-heatmap-map')).toBeVisible();

		// The component downloads the user's tracks then either renders a
		// legend (data present) or an empty state (no mapped runs). Either
		// is a pass; what must NOT persist is the loading spinner.
		await expect(page.getByTestId('personal-heatmap-loading')).toHaveCount(0, {
			timeout: 20_000
		});
		const legend = page.getByTestId('personal-heatmap-legend');
		const empty = page.getByTestId('personal-heatmap-empty');
		await expect(legend.or(empty)).toBeVisible();
	});

	test('crossfades from a heat cloud (zoomed out) to track lines (zoomed in)', async ({
		page
	}) => {
		await page.goto('/runs/heatmap');
		await expect(page.getByTestId('personal-heatmap-map')).toBeVisible();
		await expect(page.getByTestId('personal-heatmap-loading')).toHaveCount(0, {
			timeout: 20_000
		});
		// The seed user owns mapped runs, so data must resolve to the legend.
		await expect(page.getByTestId('personal-heatmap-legend')).toBeVisible();

		const state = await page.evaluate(() => {
			type MiniMap = {
				getLayer(id: string): unknown;
				getPaintProperty(layer: string, prop: string): unknown;
				getSource(id: string):
					| { serialize?(): { data?: { features?: unknown[] } } }
					| undefined;
			};
			const map = (window as { __personalHeatmap?: MiniMap }).__personalHeatmap;
			if (!map) return null;
			const lineSrc = map.getSource('personal-lines-src');
			const data = lineSrc?.serialize?.().data;
			return {
				hasHeatLayer: !!map.getLayer('personal-heat-layer'),
				hasLineLayer: !!map.getLayer('personal-lines-layer'),
				heatOpacity: map.getPaintProperty('personal-heat-layer', 'heatmap-opacity'),
				lineOpacity: map.getPaintProperty('personal-lines-layer', 'line-opacity'),
				lineFeatureCount: Array.isArray(data?.features) ? data!.features!.length : 0
			};
		});

		expect(state).not.toBeNull();
		// Both halves of the crossfade are present.
		expect(state!.hasHeatLayer).toBe(true);
		expect(state!.hasLineLayer).toBe(true);
		// The line layer is actually fed the runner's own tracks.
		expect(state!.lineFeatureCount).toBeGreaterThan(0);
		// Both opacities must be zoom-interpolated expressions (the
		// crossfade), not the old constant `heatmap-opacity: 0.85` — that
		// constant is exactly what made the heat dissolve with nothing
		// taking its place when zooming in.
		expect(Array.isArray(state!.heatOpacity)).toBe(true);
		expect((state!.heatOpacity as unknown[])[0]).toBe('interpolate');
		expect(Array.isArray(state!.lineOpacity)).toBe(true);
		expect((state!.lineOpacity as unknown[])[0]).toBe('interpolate');
	});

	test('Heatmap link on the runs page navigates here', async ({ page }) => {
		await page.goto('/history');
		await page.getByRole('link', { name: 'Heatmap' }).click();
		await expect(page).toHaveURL(/\/runs\/heatmap/);
		await expect(page.getByRole('heading', { name: 'Your heatmap' })).toBeVisible({
			timeout: 10_000
		});
	});
});

test.describe('/runs/heatmap — signed-in, consent NOT accepted', () => {
	// The persisted USER_A storageState bakes accepted consent; clear it
	// before each navigation so we exercise the not-yet-consented path.
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.removeItem('cookie_consent');
		});
	});

	test('gates the MapTiler map behind a Load-map tap (no auto-init before consent)', async ({
		page
	}) => {
		await page.goto('/runs/heatmap');

		// The consent card must show; the map must NOT auto-initialise
		// (MapTiler would log the IP per tile fetch before consent).
		const card = page.getByTestId('personal-heatmap-consent');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('personal-heatmap-legend')).toHaveCount(0);
		await expect(page.getByTestId('personal-heatmap-loading')).toHaveCount(0);
		const beforeInit = await page.evaluate(
			() => (window as { __personalHeatmap?: unknown }).__personalHeatmap ?? null
		);
		expect(beforeInit).toBeNull();

		// Tapping Load map is the affirmative act — the map initialises.
		await page.getByRole('button', { name: 'Load map' }).click();
		await expect(card).toHaveCount(0);
		await expect(page.getByTestId('personal-heatmap-map')).toBeVisible();
		await expect(page.getByTestId('personal-heatmap-loading')).toHaveCount(0, {
			timeout: 20_000
		});
		await expect(
			page
				.getByTestId('personal-heatmap-legend')
				.or(page.getByTestId('personal-heatmap-empty'))
		).toBeVisible();
	});
});
