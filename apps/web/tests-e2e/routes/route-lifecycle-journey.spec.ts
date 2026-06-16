import { expect, test, type Browser } from '@playwright/test';

import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Routes — full-lifecycle JOURNEY (create → list → detail → publish →
 * anon public share → delete → gone).
 *
 * This is a long, cross-surface "one route's life" walk, distinct from
 * the single-surface specs that already exist:
 *   - routes/list.spec.ts     — /routes filters in isolation
 *   - routes/detail.spec.ts   — /routes/[id] owner ops in isolation
 *   - routes/segments.spec.ts — the SegmentsPanel in isolation
 *   - share/route.spec.ts     — /share/route/[id] anon read in isolation
 *
 * What this journey threads together end-to-end, as USER_A unless noted:
 *   1. CREATE — seed the route via the service-role admin client.
 *      The /routes/new builder is MapLibre + OSRM and map-heavy to drive
 *      reliably in e2e, and routes have NO UI delete affordance at all
 *      (see routes/detail.spec.ts: "the only delete path is service-role
 *      / SQL"). So both the create and the teardown go through the admin
 *      client — mirroring share/route.spec.ts's private-route fixture —
 *      and every assertion in between is driven through the real UI.
 *   2. LIST — the route shows up in My routes on /routes, found by its
 *      unique name through the search box.
 *   3. DETAIL — /routes/[id] renders the name (h1), the key-stats tiles,
 *      the MapLibre map, and the always-mounted Segments panel; the
 *      "Describe this route" affordance produces an offline description.
 *   4. PUBLISH — confirm the public toggle reads Public (the route was
 *      seeded is_public=true), so the share surface is reachable.
 *   5. PUBLIC SHARE (the key cross-surface step) — a fresh ANONYMOUS
 *      context with NO storageState (logged out) opens /share/route/[id]
 *      and sees the privacy-clipped public page: name + distance + surface.
 *   6. DELETE + GONE — remove the route via the admin client, then assert
 *      it is gone from USER_A's /routes AND that the anon share URL now
 *      renders the not-found state.
 *
 * Self-contained: the route is created in beforeEach under a unique name
 * and torn down in afterEach (the delete step normally removes it; the
 * afterEach is the belt-and-braces sweep if a mid-journey failure leaves
 * the row behind).
 */

test.describe('Routes — create → list → detail → publish → anon share → delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Unique per test run so re-runs on a dirty DB never collide, and so
	// the /routes search box narrows to exactly this one row.
	let routeId = '';
	let routeName = '';

	test.beforeEach(async ({ context }) => {
		// The seeded user's storageState already carries accepted cookie
		// consent, but inject it on every navigation too so the GDPR banner
		// never floats over the map / share surfaces and eats a click.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});

		// create_route is rate-limited (30/hour per user, migration
		// 20260907_001). A shared-USER_A shard can blow through the cap;
		// reset the window so the (admin-client) seed isn't the thing that
		// trips it, and so the journey reads as a clean create.
		await resetRateLimit(USER_A.id, 'create_route');

		const admin = getAdminClient();
		routeId = crypto.randomUUID();
		routeName = `E2E lifecycle route ${Date.now()}`;
		const { error } = await admin.from('routes').insert({
			id: routeId,
			user_id: USER_A.id,
			name: routeName,
			distance_m: 8000,
			elevation_m: 60,
			surface: 'road',
			is_public: true,
			// A short Melbourne-area polyline (mirrors the seed's public
			// route shape) so the detail map + preview scrubber + describe
			// affordance all have real geometry to work with.
			waypoints: [
				{ lat: -37.82, lng: 144.97, ele: 20 },
				{ lat: -37.818, lng: 144.972, ele: 25 },
				{ lat: -37.816, lng: 144.974, ele: 30 },
				{ lat: -37.814, lng: 144.976, ele: 35 },
				{ lat: -37.812, lng: 144.978, ele: 40 },
				{ lat: -37.81, lng: 144.98, ele: 45 }
			]
		});
		if (error) {
			throw new Error(`route-lifecycle-journey: seed insert failed: ${error.message}`);
		}
	});

	test.afterEach(async () => {
		// Belt-and-braces: the delete step removes the row on the happy
		// path, but sweep here so a mid-journey failure can't leak a route
		// into USER_A's /routes for the next spec.
		if (routeId) {
			await getAdminClient().from('routes').delete().eq('id', routeId);
		}
	});

	test('a route is created, listed, opened, published, shared anonymously, then deleted', async ({
		page,
		browser
	}) => {
		await test.step('2. the new route appears in My routes on /routes', async () => {
			await page.goto('/routes');
			// /routes fetches the My-routes list client-side in onMount
			// (fetchRoutesWithError); the page paints a skeleton first, then
			// swaps in the .route-card grid. The auto-waiting toBeVisible
			// below polls for the cards — don't waitForLoadState('networkidle')
			// here: the page keeps an open Supabase realtime socket so it
			// never reaches network-idle and that wait can hang.
			// My routes is the default tab; search to narrow to exactly the
			// freshly-seeded row by its unique name (the seed has several
			// other routes for USER_A).
			await expect(page.locator('.route-card').first()).toBeVisible({
				timeout: 10_000
			});
			await page.getByLabel('Search routes').fill(routeName);
			const card = page.locator(`.route-card[href$="${routeId}"]`);
			await expect(card).toBeVisible({ timeout: 10_000 });
			await expect(card).toContainText(routeName);
		});

		await test.step('3a. /routes/[id] renders name, key stats, and the map', async () => {
			await page.goto(`/routes/${routeId}`);
			// The auto-waiting assertions below poll until the page hydrates;
			// no networkidle wait (the page holds an open realtime socket).

			// Name in the h1.
			await expect(
				page.getByRole('heading', { name: routeName, level: 1 })
			).toBeVisible({ timeout: 10_000 });

			// Key-stat tiles: distance + surface are always rendered.
			const keyStats = page.locator('.key-stats');
			await expect(keyStats).toBeVisible();
			await expect(keyStats).toContainText('Distance');
			await expect(keyStats).toContainText('road');

			// MapLibre map container mounts.
			await expect(page.locator('.run-map').first()).toBeVisible({
				timeout: 10_000
			});
		});

		await test.step('3b. the always-mounted Segments panel renders (empty leaderboard ok)', async () => {
			// SegmentsPanel mounts on every /routes/[id]; this route has no
			// segments, so we assert the panel + its header are present
			// rather than any leaderboard rows.
			await expect(page.locator('.segments-panel')).toBeVisible({
				timeout: 10_000
			});
			await expect(page.locator('.segments-panel h2')).toHaveText('Segments');
		});

		await test.step('3c. the "Describe this route" affordance produces a description', async () => {
			// The route has no stored description, so the describe button is
			// rendered. Clicking it runs the offline describeRoute() path
			// (the always-works L1 fallback) and renders .route-description.
			const describeBtn = page.locator('button.describe-btn');
			await expect(describeBtn).toBeVisible({ timeout: 10_000 });
			await describeBtn.click();
			await expect(page.locator('.route-description')).toBeVisible({
				timeout: 10_000
			});
		});

		await test.step('4. the public toggle confirms the route is published', async () => {
			// The route was seeded is_public=true, so the owner toggle reads
			// "Public — tap to make private". (Same title-attribute selector
			// the detail spec uses; the button label text includes the icon
			// ligature, so target by the title prefix.)
			const toggleBtn = page.locator(
				'button[title^="Public"], button[title^="Private"]'
			);
			await expect(toggleBtn).toBeVisible({ timeout: 10_000 });
			await expect(toggleBtn).toHaveAttribute('title', /^Public/);
		});

		await test.step('5. an anonymous (logged-out) visitor sees the public share page', async () => {
			// The cross-surface key step: a brand-new context with NO
			// storageState is fully logged out. The anon read goes through
			// the public_routes view (privacy-clipped: drops geom +
			// start_point), so it must still surface the name + distance +
			// surface.
			const anon = await newAnonContext(browser);
			try {
				const anonPage = await anon.newPage();
				await anonPage.goto(`/share/route/${routeId}`);

				await expect(
					anonPage.getByRole('heading', { name: routeName, level: 1 })
				).toBeVisible({ timeout: 10_000 });

				// The body-level .route-meta strip carries surface + distance.
				await expect(anonPage.locator('.route-meta .surface-tag')).toContainText(
					'road'
				);
				await expect(anonPage.locator('.route-meta')).toContainText('8');
			} finally {
				await anon.close();
			}
		});

		await test.step('6. deleting the route removes it from /routes and the anon share URL', async () => {
			// Routes have no UI delete; the canonical delete path is
			// service-role / SQL (see routes/detail.spec.ts). Delete via the
			// admin client, then assert both surfaces reflect the removal.
			await getAdminClient().from('routes').delete().eq('id', routeId);
			const deletedId = routeId;
			// Null it so the afterEach sweep doesn't double-delete (harmless,
			// but keeps intent clear).
			routeId = '';

			// Owner /routes no longer lists it. The list fetches client-side
			// in onMount, so the auto-waiting assertion polls for the cards
			// rather than waitForLoadState('networkidle') — the page holds an
			// open Supabase realtime socket and never reaches network-idle, so
			// that wait would hang to the test timeout.
			await page.goto('/routes');
			// The toolbar persists the search box to localStorage, and step 2
			// left it set to this run's unique name. Clear it first, or the
			// restored filter hides every card (the deleted route is the only
			// name-match and it's now gone) and the list shows its empty
			// state instead of the seed's other routes.
			await page.getByLabel('Search routes').fill('');
			await expect(page.locator('.route-card').first()).toBeVisible({
				timeout: 15_000
			});
			await page.getByLabel('Search routes').fill(routeName);
			await expect(page.locator(`.route-card[href$="${deletedId}"]`)).toHaveCount(
				0,
				{ timeout: 10_000 }
			);

			// Anon share URL now renders the not-found copy (public_routes
			// view returns no row, same shape as a missing id).
			const anon = await newAnonContext(browser);
			try {
				const anonPage = await anon.newPage();
				await anonPage.goto(`/share/route/${deletedId}`);
				await expect(
					anonPage.getByText('Route not found or is private.')
				).toBeVisible({ timeout: 10_000 });
			} finally {
				await anon.close();
			}
		});
	});
});

/**
 * A fresh, fully logged-out browser context: NO storageState, but the
 * cookie-consent choice pre-seeded so the GDPR banner doesn't float over
 * the share surface. Contexts spun up from the test `browser` fixture
 * inherit the project's baseURL, so relative goto() works (same pattern
 * as the anon contexts in clubs/event-rsvp.spec.ts + share/route.spec.ts).
 */
async function newAnonContext(browser: Browser) {
	const ctx = await browser.newContext({
		storageState: { cookies: [], origins: [] }
	});
	await ctx.addInitScript(() => {
		localStorage.setItem(
			'cookie_consent',
			JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
		);
	});
	return ctx;
}
