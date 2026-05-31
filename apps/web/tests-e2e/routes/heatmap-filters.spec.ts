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
});

test.describe('Heatmap filter chips (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('chip bar swaps the lens and the count tracks the RPC', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1200);

		// Pan to Virginia where the seeded routes live.
		await page.evaluate(async () => {
			type MapHandle = {
				flyTo: (o: { center: [number, number]; zoom: number }) => void;
				once: (event: string, cb: () => void) => void;
			};
			const m = (window as unknown as { __heatmapMap?: MapHandle }).__heatmapMap;
			if (!m) return;
			await new Promise<void>((resolve) => {
				m.once('moveend', () => resolve());
				m.flyTo({ center: [-78, 38], zoom: 7 });
			});
		});
		await page.waitForTimeout(900);

		const filterBar = page.getByTestId('heatmap-filters');
		await expect(filterBar).toBeVisible();

		// Popular is the default lens.
		const popularChip = filterBar.locator('[data-filter="popular"]');
		const featuredChip = filterBar.locator('[data-filter="featured"]');
		await expect(popularChip).toHaveAttribute('aria-pressed', 'true');
		await expect(featuredChip).toHaveAttribute('aria-pressed', 'false');

		// Seed VA: popular = 6 (3 featured + 3 run_count>0).
		await expect(popularChip.locator('.filter-chip-count')).toHaveText('6');

		// Switch to Featured: active state + count both move (→ 3).
		await featuredChip.click();
		await expect(featuredChip).toHaveAttribute('aria-pressed', 'true');
		await expect(popularChip).toHaveAttribute('aria-pressed', 'false');
		await expect(featuredChip.locator('.filter-chip-count')).toHaveText('3', {
			timeout: 5000,
		});
	});
});
