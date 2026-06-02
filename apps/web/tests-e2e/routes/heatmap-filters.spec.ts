import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Route-discovery filter facet on the heatmap (`p_filter` on
 * `discoverable_routes_in_bbox`, added 20261113_001).
 *
 * The map's pin set switches between four lenses so the surface
 * reads as a route browser, not one undifferentiated blob:
 *
 *   • popular     — featured OR run_count > 0 (the prior default;
 *                   unchanged so old callers keep working).
 *   • featured    — admin-curated only.
 *   • friends     — public routes created by users the caller
 *                   follows (user_follows graph, via auth.uid()).
 *   • hidden_gems — un-run public routes past a >=1km sanity floor.
 *
 * Backend-contract tests assert each lens over seed data + a couple
 * of inserted fixtures (the seed has no un-run or followee-owned
 * public routes). The web test proves the chip bar swaps the lens
 * and the count tracks the RPC.
 */

const VA_BBOX = {
	p_min_lng: -83.7,
	p_min_lat: 36.5,
	p_max_lng: -75.2,
	p_max_lat: 39.5,
	p_limit: 100,
};

// A remote box clear of every seeded route (seed lat range is
// ~ -38..39, so lat 48 is empty) for the inserted fixtures.
const FIX_BBOX = {
	p_min_lng: 7.5,
	p_min_lat: 47.5,
	p_max_lng: 8.5,
	p_max_lat: 48.5,
	p_limit: 100,
};

type Pin = {
	id: string;
	featured: boolean;
	run_count: number;
	distance_m: number;
};

/// Pan the discovery map to Virginia, where the seeded routes live, and
/// wait for the post-move bbox refresh to land.
async function flyToVA(page: import('@playwright/test').Page) {
	await page.evaluate(async () => {
		type MapHandle = {
			flyTo: (o: { center: [number, number]; zoom: number }) => void;
			once: (event: string, cb: () => void) => void;
		};
		const m = (window as unknown as { __heatmapMap?: MapHandle }).__heatmapMap;
		if (!m) return;
		await new Promise<void>((resolve) => {
			m.once('moveend', () => resolve());
			// Zoom 6 (not 7): the sidebar narrows the map, so a tighter
			// zoom clips the easternmost / westernmost of the six VA
			// routes (they span ~4° of longitude) out of the viewport.
			m.flyTo({ center: [-78, 37.9], zoom: 6 });
		});
	});
	await page.waitForTimeout(900);
}

test.describe('discoverable_routes_in_bbox p_filter (backend contract)', () => {
	test('featured lens returns only featured routes, a subset of popular', async () => {
		const admin = getAdminClient();
		const popular = (
			await admin.rpc('discoverable_routes_in_bbox', { ...VA_BBOX, p_filter: 'popular' })
		).data as Pin[];
		const featured = (
			await admin.rpc('discoverable_routes_in_bbox', { ...VA_BBOX, p_filter: 'featured' })
		).data as Pin[];

		expect(featured.length).toBeGreaterThanOrEqual(3);
		for (const p of featured) {
			expect(p.featured, `route ${p.id} under featured lens must be featured`).toBe(true);
		}
		// Every featured route is also "popular" (popular = featured OR run_count>0).
		const popularIds = new Set(popular.map((p) => p.id));
		for (const p of featured) expect(popularIds.has(p.id)).toBe(true);
		// Popular is the strictly broader set here (it also has run_count>0 routes).
		expect(popular.length).toBeGreaterThan(featured.length);
	});

	test('hidden_gems lens surfaces un-run routes past the 1km floor, never popular ones', async () => {
		const admin = getAdminClient();
		const gemId = crypto.randomUUID();
		const tinyId = crypto.randomUUID();
		try {
			// A genuine un-run route (>=1km) and a sub-floor scribble.
			// start_point is trigger-derived from waypoints[0], so the
			// fixtures carry real waypoints rather than an explicit point.
			await admin.from('routes').insert([
				{
					id: gemId,
					user_id: USER_A.id,
					name: 'hidden gem fixture',
					distance_m: 5000,
					is_public: true,
					surface: 'trail',
					waypoints: [
						{ lng: 8.0, lat: 48.0 },
						{ lng: 8.01, lat: 48.01 },
					],
				},
				{
					id: tinyId,
					user_id: USER_A.id,
					name: 'sub-floor scribble',
					distance_m: 500,
					is_public: true,
					surface: 'trail',
					waypoints: [
						{ lng: 8.1, lat: 48.1 },
						{ lng: 8.11, lat: 48.11 },
					],
				},
			]);

			const gems = (
				await admin.rpc('discoverable_routes_in_bbox', { ...FIX_BBOX, p_filter: 'hidden_gems' })
			).data as Pin[];
			const gemIds = gems.map((p) => p.id);
			expect(gemIds, 'the >=1km un-run route is a hidden gem').toContain(gemId);
			expect(gemIds, 'the 500m scribble is below the floor').not.toContain(tinyId);
			for (const p of gems) {
				expect(p.featured).toBe(false);
				expect(p.run_count).toBe(0);
				expect(p.distance_m).toBeGreaterThanOrEqual(1000);
			}

			// An un-run, non-featured route must NOT appear under popular.
			const popular = (
				await admin.rpc('discoverable_routes_in_bbox', { ...FIX_BBOX, p_filter: 'popular' })
			).data as Pin[];
			expect(popular.map((p) => p.id)).not.toContain(gemId);
		} finally {
			await admin.from('routes').delete().in('id', [gemId, tinyId]);
		}
	});

	test('friends lens shows a followee route, and only with the follower authenticated', async () => {
		const admin = getAdminClient();
		// runner (USER_A) follows alex (USER_B) in the seed; give alex a
		// public, un-run route so it can only surface via the friends lens.
		const friendRouteId = crypto.randomUUID();
		try {
			await admin.from('routes').insert({
				id: friendRouteId,
				user_id: USER_B.id,
				name: "alex's route fixture",
				distance_m: 6000,
				is_public: true,
				surface: 'road',
				waypoints: [
					{ lng: 8.2, lat: 48.2 },
					{ lng: 8.21, lat: 48.21 },
				],
			});

			const runner = await getUserClient({ email: USER_A.email, password: USER_A.password });
			const friends = (
				await runner.rpc('discoverable_routes_in_bbox', { ...FIX_BBOX, p_filter: 'friends' })
			).data as Pin[];
			expect(friends.map((p) => p.id), "runner sees a followee's route").toContain(friendRouteId);

			// run_count 0 + not featured → never under popular.
			const popular = (
				await runner.rpc('discoverable_routes_in_bbox', { ...FIX_BBOX, p_filter: 'popular' })
			).data as Pin[];
			expect(popular.map((p) => p.id)).not.toContain(friendRouteId);

			// Fail-closed: the service-role client has no auth.uid(), so the
			// followee set is empty and the friends lens returns nothing.
			const anonFriends = (
				await admin.rpc('discoverable_routes_in_bbox', { ...FIX_BBOX, p_filter: 'friends' })
			).data as Pin[];
			expect(anonFriends.length, 'no caller identity → no friend routes').toBe(0);
		} finally {
			await admin.from('routes').delete().eq('id', friendRouteId);
		}
	});

	test('distance bands filter to the selected windows in any combination', async () => {
		const admin = getAdminClient();
		const all = (
			await admin.rpc('discoverable_routes_in_bbox', { ...VA_BBOX, p_filter: 'popular' })
		).data as Pin[];

		// Single band: every result falls in [4000, 6000).
		const fiveK = (
			await admin.rpc('discoverable_routes_in_bbox', {
				...VA_BBOX,
				p_filter: 'popular',
				p_dist_min: [4000],
				p_dist_max: [6000],
			})
		).data as Pin[];
		for (const p of fiveK) {
			expect(p.distance_m).toBeGreaterThanOrEqual(4000);
			expect(p.distance_m).toBeLessThan(6000);
		}
		expect(fiveK.length).toBeLessThanOrEqual(all.length);

		// Two bands OR together: the 5k∪10k result is exactly the union of
		// each band taken alone (no double counting, no drops).
		const tenK = (
			await admin.rpc('discoverable_routes_in_bbox', {
				...VA_BBOX,
				p_filter: 'popular',
				p_dist_min: [8000],
				p_dist_max: [12000],
			})
		).data as Pin[];
		const union = (
			await admin.rpc('discoverable_routes_in_bbox', {
				...VA_BBOX,
				p_filter: 'popular',
				p_dist_min: [4000, 8000],
				p_dist_max: [6000, 12000],
			})
		).data as Pin[];
		const expected = new Set([...fiveK, ...tenK].map((p) => p.id));
		expect(new Set(union.map((p) => p.id))).toEqual(expected);

		// Open-ended upper bound (ultra) via a NULL hi.
		const ultra = (
			await admin.rpc('discoverable_routes_in_bbox', {
				...VA_BBOX,
				p_filter: 'popular',
				p_dist_min: [44500],
				p_dist_max: [null],
			})
		).data as Pin[];
		for (const p of ultra) expect(p.distance_m).toBeGreaterThanOrEqual(44500);
	});
});

test.describe('Heatmap filters popover (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	async function open(page: import('@playwright/test').Page) {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);
		await flyToVA(page);
	}

	test('the Filters button opens the panel; the lens swaps the result set', async ({
		page,
	}) => {
		await open(page);

		const count = page.locator('.results-count strong');
		const readCount = async () =>
			parseInt((await count.textContent()) ?? '0', 10);
		// Relationship-based, not a magic number, so adding seed routes in
		// VA doesn't break it: popular has routes.
		await expect.poll(readCount, { timeout: 6000 }).toBeGreaterThanOrEqual(1);
		const popularN = await readCount();

		// Filters panel is closed until the button is pressed.
		await expect(page.getByTestId('filters-panel')).toHaveCount(0);
		await page.getByTestId('filters-button').click();
		const panel = page.getByTestId('filters-panel');
		await expect(panel).toBeVisible();

		const popularChip = panel.locator('[data-filter="popular"]');
		const featuredChip = panel.locator('[data-filter="featured"]');
		await expect(popularChip).toHaveAttribute('aria-pressed', 'true');

		// Featured is a non-default lens (badge = 1) and a subset of
		// popular, so its count is >=1 and never exceeds the popular count.
		await featuredChip.click();
		await expect(featuredChip).toHaveAttribute('aria-pressed', 'true');
		await expect(popularChip).toHaveAttribute('aria-pressed', 'false');
		await expect(page.getByTestId('filters-button').locator('.filters-badge')).toHaveText('1');
		await expect.poll(readCount, { timeout: 6000 }).toBeLessThanOrEqual(popularN);
		expect(await readCount()).toBeGreaterThanOrEqual(1);
	});

	test('race-distance bands filter the results to the chosen bands', async ({ page }) => {
		await open(page);
		await page.getByTestId('filters-button').click();
		const bands = page.getByTestId('band-chips');
		const badges = page.locator('.results-list .result-band');
		const rows = page.locator('.results-list .result-row');

		// 5K only → every visible row is a 5K route (badge text + count
		// agree). Asserting the *contract* (band filtering is correct), not
		// a magic total, so it survives more VA seed.
		await bands.locator('[data-band="5k"]').click();
		await expect(page.getByTestId('filters-button').locator('.filters-badge')).toHaveText('1');
		await expect
			.poll(
				async () => {
					const l = await badges.allTextContents();
					return l.length > 0 && l.every((x) => x === '5K');
				},
				{ timeout: 6000 },
			)
			.toBe(true);
		const fiveKCount = await rows.count();
		expect(await badges.count(), 'every 5K row carries a 5K badge').toBe(fiveKCount);

		// Add 10K → the result is the union, so every row is now 5K or 10K
		// and the count never shrinks below the 5K-only count.
		await bands.locator('[data-band="10k"]').click();
		await expect(page.getByTestId('filters-button').locator('.filters-badge')).toHaveText('2');
		await expect
			.poll(
				async () => {
					const l = await badges.allTextContents();
					return l.length >= fiveKCount && l.every((x) => x === '5K' || x === '10K');
				},
				{ timeout: 6000 },
			)
			.toBe(true);

		// Reset clears the lens + bands.
		await page.locator('.filters-reset').click();
		await expect(page.getByTestId('filters-button').locator('.filters-badge')).toHaveCount(0);
	});
});

test.describe('Heatmap route-pin clustering (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a dense pile of route pins collapses into one cluster bubble', async ({ page }) => {
		const admin = getAdminClient();
		// Four featured (→ visible under the default 'popular' lens)
		// public routes packed within ~50m of (9,49), a spot no seed
		// route touches, so they must cluster into a single bubble.
		const ids = [0, 1, 2, 3].map(() => crypto.randomUUID());
		try {
			await admin.from('routes').insert(
				ids.map((id, i) => ({
					id,
					user_id: USER_A.id,
					name: `cluster fixture ${i}`,
					distance_m: 4000,
					is_public: true,
					featured: true,
					surface: 'road',
					waypoints: [
						{ lng: 9.0 + i * 0.0004, lat: 49.0 + i * 0.0004 },
						{ lng: 9.001 + i * 0.0004, lat: 49.001 + i * 0.0004 },
					],
				})),
			);

			await page.goto('/routes/heatmap');
			await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
			await page.waitForTimeout(1000);

			const result = await page.evaluate(async () => {
				type MapHandle = {
					flyTo: (o: { center: [number, number]; zoom: number }) => void;
					once: (event: string, cb: () => void) => void;
					getLayer: (id: string) => unknown;
					querySourceFeatures: (
						id: string,
					) => Array<{ properties?: Record<string, unknown> }>;
				};
				const m = (window as unknown as { __heatmapMap?: MapHandle }).__heatmapMap;
				if (!m) return { ok: false, maxCount: 0, hasClusterLayer: false };
				await new Promise<void>((resolve) => {
					m.once('moveend', () => resolve());
					m.flyTo({ center: [9, 49], zoom: 12 });
				});
				// Give the GeoJSON source a beat to (re)cluster after the
				// bbox refresh lands the four fixtures.
				await new Promise((r) => setTimeout(r, 1200));
				const feats = m.querySourceFeatures('heatmap-route-pins');
				let maxCount = 0;
				for (const f of feats) {
					const c = Number(f.properties?.point_count ?? 0);
					if (c > maxCount) maxCount = c;
				}
				return {
					ok: true,
					maxCount,
					hasClusterLayer: !!m.getLayer('heatmap-route-pins-cluster'),
				};
			});

			expect(result.ok, '__heatmapMap dev hook must be present').toBe(true);
			expect(result.hasClusterLayer, 'cluster layer must be registered').toBe(true);
			expect(result.maxCount, 'four packed pins form one cluster').toBeGreaterThanOrEqual(2);
		} finally {
			await admin.from('routes').delete().in('id', ids);
		}
	});
});

test.describe('Heatmap results sidebar (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('list mirrors the lens; a row keeps it and the View link navigates', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);
		await flyToVA(page);

		const list = page.getByTestId('discover-list');
		await expect(list).toBeVisible();
		const rows = list.locator('.result-row');
		// Popular has routes (relationship-based, not a magic count).
		await expect.poll(() => rows.count(), { timeout: 6000 }).toBeGreaterThanOrEqual(1);
		const popularRows = await rows.count();

		// Featured is a subset → the list narrows (or holds) but stays
		// non-empty. Wait for the featured RPC to actually land before
		// reading the list: `<= popularRows` is trivially true against the
		// still-rendered popular set, so without this gate the click below
		// races a row that the featured refetch is about to replace.
		await page.getByTestId('filters-button').click();
		const featuredFetch = page.waitForResponse(
			(r) => r.url().includes('discoverable_routes_in_bbox') && r.status() === 200,
			{ timeout: 10_000 }
		);
		await page.getByTestId('lens-chips').locator('[data-filter="featured"]').click();
		await featuredFetch;
		await expect.poll(() => rows.count(), { timeout: 6000 }).toBeLessThanOrEqual(popularRows);
		expect(await rows.count()).toBeGreaterThanOrEqual(1);

		// Clicking a row keeps it on the map — it must NOT navigate. A
		// mis-click can no longer yank you off the discovery surface.
		const firstLi = list.locator('.result-li').first();
		await firstLi.locator('.result-row').click();
		await expect(page).toHaveURL(/\/routes\/heatmap/);
		await expect(firstLi.locator('.result-row')).toHaveClass(/kept/);
		await expect(page.getByTestId('clear-pins')).toBeVisible();

		// The explicit "View route" link is the only navigation.
		const view = firstLi.getByTestId('result-view');
		const href = await view.getAttribute('href');
		expect(href).toMatch(/^\/routes\/[0-9a-f-]+$/);
		await view.click();
		await expect(page).toHaveURL(/\/routes\/[0-9a-f-]+$/);
	});

	test('the sidebar collapses + restores', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);
		await flyToVA(page);

		const sidebar = page.getByTestId('discover-sidebar');
		await expect(sidebar).toBeVisible();
		await page.getByTestId('sidebar-toggle').click();
		await expect(sidebar).toBeHidden();
		await page.getByTestId('sidebar-toggle').click();
		await expect(sidebar).toBeVisible();
	});
});

test.describe('Heatmap hover-to-preview (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// LineString features currently drawn in the route-preview source.
	function lineCount(page: import('@playwright/test').Page) {
		return page.evaluate(() => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return -1;
			return m
				.querySourceFeatures('heatmap-routes')
				.filter((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString')
				.length;
		});
	}

	test('routes stay hidden until a row is hovered, then the line + row sync', async ({
		page,
	}) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);
		await flyToVA(page);

		// Nothing is drawn by default — the route lines are hidden.
		expect(await lineCount(page)).toBe(0);

		const rows = page.getByTestId('discover-list').locator('.result-row');
		await expect.poll(() => rows.count(), { timeout: 6000 }).toBeGreaterThanOrEqual(1);
		const first = rows.first();
		await first.hover();

		// The row picks up the synchronized-highlight class...
		await expect(first).toHaveClass(/hovered/);
		// ...and the map draws that one route's line + a halo on its dot.
		await expect.poll(() => lineCount(page), { timeout: 5000 }).toBeGreaterThanOrEqual(1);
		const halo = await page.evaluate(
			() =>
				(window as unknown as { __heatmapMap?: any }).__heatmapMap.querySourceFeatures(
					'heatmap-route-hl',
				).length,
		);
		expect(halo).toBeGreaterThanOrEqual(1);

		// Moving off the row clears the preview (debounced).
		await page.mouse.move(2, 2);
		await expect(first).not.toHaveClass(/hovered/);
		await expect.poll(() => lineCount(page), { timeout: 5000 }).toBe(0);
	});

	test('hovering a map dot previews its line and highlights its row', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);

		// Fly to a single route (zoom 14 → its pin is an un-clustered leaf)
		// and project its dot to page coordinates.
		const screen = await page.evaluate(async ([lng, lat]) => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return null;
			await new Promise<void>((r) => {
				m.once('moveend', () => r());
				m.flyTo({ center: [lng, lat], zoom: 14 });
			});
			const deadline = Date.now() + 4000;
			while (Date.now() < deadline) {
				const p = m.project([lng, lat]);
				if (
					m.queryRenderedFeatures([p.x, p.y], { layers: ['heatmap-route-pins-layer'] })
						.length > 0
				)
					break;
				await new Promise<void>((r) => setTimeout(r, 150));
			}
			const p = m.project([lng, lat]);
			const rect = m.getContainer().getBoundingClientRect();
			return { x: rect.left + p.x, y: rect.top + p.y };
		}, [-77.452, 37.5311]); // Belle Isle (seed)
		expect(screen, '__heatmapMap dev hook must be present').toBeTruthy();
		if (!screen) return;

		await page.mouse.move(screen.x, screen.y);
		// The dot hover draws the route line...
		await expect.poll(() => lineCount(page), { timeout: 5000 }).toBeGreaterThanOrEqual(1);
		// ...and the matching list row is highlighted (synchronized hover).
		await expect(
			page.getByTestId('discover-list').locator('.result-row.hovered'),
		).toHaveCount(1, { timeout: 5000 });
	});
});

test.describe('Discovery scenario testbed (Denver seed)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const DENVER = {
		p_min_lng: -105.12,
		p_min_lat: 39.64,
		p_max_lng: -104.94,
		p_max_lat: 39.78,
		p_limit: 100,
	};

	test('friends lens surfaces a followee-owned seed route; popular hides it', async () => {
		const runner = await getUserClient({ email: USER_A.email, password: USER_A.password });
		const friends = (
			await runner.rpc('discoverable_routes_in_bbox', { ...DENVER, p_filter: 'friends' })
		).data as Array<{ name: string }>;
		// Alex (a runner-followee) owns this un-run route — friends-only.
		expect(friends.map((r) => r.name)).toContain("Alex's Confluence Loop");
		const popular = (
			await runner.rpc('discoverable_routes_in_bbox', { ...DENVER, p_filter: 'popular' })
		).data as Array<{ name: string }>;
		expect(popular.map((r) => r.name)).not.toContain("Alex's Confluence Loop");
	});

	test('routes sharing an exact start collapse into one cluster bubble', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);

		const maxCount = await page.evaluate(async () => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return -1;
			await new Promise<void>((r) => {
				m.once('moveend', () => r());
				m.flyTo({ center: [-105.0, 39.74], zoom: 13 });
			});
			await new Promise<void>((r) => setTimeout(r, 1500));
			let mx = 0;
			for (const f of m.querySourceFeatures('heatmap-route-pins')) {
				const c = Number(f.properties?.point_count ?? 0);
				if (c > mx) mx = c;
			}
			return mx;
		});
		// Group A: three Wash Park routes share the identical start coord.
		expect(maxCount).toBeGreaterThanOrEqual(3);
	});
});

test.describe('Heatmap compute hygiene (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	function heatPointCount(page: import('@playwright/test').Page) {
		return page.evaluate(() => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return -1;
			return m.querySourceFeatures('heatmap-pts').length;
		});
	}

	test('heat density is opt-in: not fetched until the layer is enabled', async ({
		page,
	}) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);
		// Belle Isle (Richmond) at street zoom — a route runs right here, so
		// the heat would densify into the viewport once it's enabled.
		await page.evaluate(async () => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return;
			await new Promise<void>((r) => {
				m.once('moveend', () => r());
				m.flyTo({ center: [-77.45, 37.53], zoom: 13 });
			});
		});
		await page.waitForTimeout(900);

		// Default view: heat is off → the points are never fetched, so the
		// source is empty (no wasted server densification per pan).
		expect(await heatPointCount(page)).toBe(0);

		// Enable Heat in the Filters panel → the points fetch on demand.
		await page.getByTestId('filters-button').click();
		const heat = page.locator('.layer-row', { hasText: 'Heat' }).getByRole('checkbox');
		await expect(heat).not.toBeChecked();
		await heat.check();
		await expect.poll(() => heatPointCount(page), { timeout: 6000 }).toBeGreaterThan(0);
	});
});

test.describe('Heatmap cluster list (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('hovering an overlapping-start cluster lists its routes; a row previews', async ({
		page,
	}) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);

		// Wash Park (Denver seed): 3 routes share the EXACT same start, so
		// they always cluster and can't be zoomed apart — the list is the
		// only way to reach them. Fly there and project the cluster bubble.
		const screen = await page.evaluate(async ([lng, lat]) => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return null;
			await new Promise<void>((r) => {
				m.once('moveend', () => r());
				m.flyTo({ center: [lng, lat], zoom: 13 });
			});
			const deadline = Date.now() + 4000;
			while (Date.now() < deadline) {
				const p = m.project([lng, lat]);
				if (
					m.queryRenderedFeatures([p.x, p.y], {
						layers: ['heatmap-route-pins-cluster'],
					}).length > 0
				)
					break;
				await new Promise<void>((r) => setTimeout(r, 150));
			}
			const p = m.project([lng, lat]);
			const rect = m.getContainer().getBoundingClientRect();
			return { x: rect.left + p.x, y: rect.top + p.y };
		}, [-105.0, 39.74]);
		expect(screen, '__heatmapMap dev hook + a cluster must be present').toBeTruthy();
		if (!screen) return;

		await page.mouse.move(screen.x, screen.y);
		const popup = page.locator('.heatmap-cluster-popup');
		await expect(popup).toBeVisible({ timeout: 5000 });
		const rows = popup.locator('.cluster-route');
		await expect(rows).toHaveCount(3);

		// Hovering a row previews that route's line on the map.
		await rows.first().hover();
		await expect
			.poll(
				() =>
					page.evaluate(() => {
						const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
						return m
							.querySourceFeatures('heatmap-routes')
							.filter((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString')
							.length;
					}),
				{ timeout: 5000 },
			)
			.toBeGreaterThanOrEqual(1);

		// Each row carries an explicit "View" link to its route detail,
		// and clicking the row body keeps it (no navigation).
		const href = await rows.first().locator('.cluster-route-view').getAttribute('href');
		expect(href).toMatch(/^\/routes\/[0-9a-f-]+$/);
		await rows.first().locator('.cluster-route-main').click();
		await expect(page).toHaveURL(/\/routes\/heatmap/);
		await expect(rows.first()).toHaveClass(/kept/);
	});

	test('zoomed past clustering, overlapping pins still list (no arbitrary pick)', async ({
		page,
	}) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);

		// Zoom 16 is past clusterMaxZoom (14), so the 3 Wash Park routes
		// that share an exact start are now un-clustered, overlapping leaf
		// pins. Hovering must surface the list, not one arbitrary route.
		const screen = await page.evaluate(async ([lng, lat]) => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return null;
			await new Promise<void>((r) => {
				m.once('moveend', () => r());
				m.flyTo({ center: [lng, lat], zoom: 16 });
			});
			const deadline = Date.now() + 4000;
			while (Date.now() < deadline) {
				const p = m.project([lng, lat]);
				if (
					m.queryRenderedFeatures([p.x, p.y], {
						layers: ['heatmap-route-pins-layer'],
					}).length > 0
				)
					break;
				await new Promise<void>((r) => setTimeout(r, 150));
			}
			const p = m.project([lng, lat]);
			const rect = m.getContainer().getBoundingClientRect();
			return { x: rect.left + p.x, y: rect.top + p.y };
		}, [-105.0, 39.74]);
		expect(screen).toBeTruthy();
		if (!screen) return;

		await page.mouse.move(screen.x, screen.y);
		const popup = page.locator('.heatmap-cluster-popup');
		await expect(popup).toBeVisible({ timeout: 5000 });
		await expect(popup.locator('.cluster-route')).toHaveCount(3);
	});
});

test.describe('Heatmap keep-on-map / pin (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	function pinnedLineCount(page: import('@playwright/test').Page) {
		return page.evaluate(() => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			if (!m) return -1;
			return m
				.querySourceFeatures('heatmap-routes-pinned')
				.filter((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString')
				.length;
		});
	}

	test('pinning a route keeps its line after you move away; Clear removes it', async ({
		page,
	}) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1100);
		await flyToVA(page);

		const rows = page.getByTestId('discover-list').locator('.result-li');
		await expect.poll(() => rows.count(), { timeout: 6000 }).toBeGreaterThanOrEqual(1);
		const first = rows.first();

		expect(await pinnedLineCount(page)).toBe(0);
		await expect(page.getByTestId('clear-pins')).toHaveCount(0);

		await first.locator('.result-row').click();
		await expect(first.locator('.result-row')).toHaveClass(/kept/);
		await expect.poll(() => pinnedLineCount(page), { timeout: 6000 }).toBeGreaterThanOrEqual(1);
		await expect(page.getByTestId('clear-pins')).toBeVisible();

		await page.mouse.move(2, 2);
		await page.waitForTimeout(400);
		expect(await pinnedLineCount(page)).toBeGreaterThanOrEqual(1);

		await page.getByTestId('clear-pins').click();
		await expect.poll(() => pinnedLineCount(page), { timeout: 5000 }).toBe(0);
		await expect(page.getByTestId('clear-pins')).toHaveCount(0);
	});
});
