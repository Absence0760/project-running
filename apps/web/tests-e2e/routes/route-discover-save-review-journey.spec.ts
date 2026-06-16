import { expect, test, type Browser, type BrowserContext } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	createSagaUsers,
	deleteSagaUsers,
	type SagaUser
} from '../fixtures/saga-users';
import { insertRoute, deleteRoute } from '../fixtures/simulate';

/**
 * Routes — CROSS-USER discover → save → review JOURNEY.
 *
 * One runner discovers a PUBLIC route created by SOMEONE ELSE, saves it
 * to their own library, and rates + reviews it; the review then shows on
 * the route and lifts its aggregate rating, and the saved route appears
 * in the discoverer's My routes. This is the stitched community arc the
 * granular specs each cover only a slice of:
 *   - routes/review.spec.ts            — the review form in isolation
 *   - routes/list.spec.ts              — /routes My-routes filters alone
 *   - routes/detail.spec.ts            — /routes/[id] OWNER ops alone
 *   - routes/route-lifecycle-journey   — the OWNER's own route's life
 *     (create → list → publish → anon share → delete)
 *   - routes/heatmap-*.spec.ts         — the community heatmap browser
 *
 * route-lifecycle-journey walks the owner publishing + anon-sharing
 * their OWN route. This walks a DIFFERENT user — who does NOT own the
 * route — discovering it through the community explorer, bookmarking it
 * (saved_routes reference, decisions §30), and reviewing it. The
 * non-owner review path is gated by RLS on route visibility
 * (`is_route_visible_to`, migration 20260703_001), so the route must be
 * genuinely public for the write to land.
 *
 * Two users via createSagaUsers(2): OWNER plants the route, DISCOVERER
 * drives every assertion through the real UI.
 *
 * DISCOVERY PATH: the real community explorer. /routes?tab=explore mounts
 * RouteExplorer, whose search box drives the `search_public_routes` RPC
 * (name ILIKE). The route is planted with a unique name so the search
 * narrows to exactly this one row. The SAVE write goes through the
 * explorer's `.save-btn` (→ saved_routes), and the REVIEW write goes
 * through the route-detail Rate form (→ route_reviews) — both real UI.
 *
 * MAP NOTE: /routes/[id] mounts a MapLibre canvas (RunMap) and the
 * explorer cards lazy-fetch an SVG track preview. Every assertion here
 * targets DOM (headings, the .review-card / .review-comment rows, the
 * .avg-rating text in the Reviews header, the .save-btn saved state, the
 * My-routes .route-card[href]) — never canvas paint — to dodge the
 * animation-wait hangs the lifecycle spec documents.
 */

const uniqueSuffix = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/**
 * A context for a saga user with the cookie-consent choice pre-seeded —
 * the GDPR banner is a role="dialog" that floats over the explorer cards,
 * the route map's "Load map" gate, AND the review form, so it must be
 * dismissed before any click. Saga storageState does NOT carry consent
 * (only the seeded users do), so inject it on every navigation.
 */
async function sagaContext(browser: Browser, user: SagaUser): Promise<BrowserContext> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	await ctx.addInitScript(setConsentAccepted);
	return ctx;
}

test.describe('saga: discover a public route, save it, review it (cross-user)', () => {
	// Multi-context saga over the explorer + route-detail (both hold open
	// realtime / map sockets). 90 s gives headroom over the default 30 s.
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[];
	let routeId = '';
	let routeName = '';

	test.beforeAll(async () => {
		users = await createSagaUsers(2, {
			displayNames: ['Saga Route Owner', 'Saga Route Discoverer']
		});
		const [owner] = users;

		// Plant the discoverable PUBLIC route OWNED BY THE OWNER, not the
		// discoverer — the whole point is reviewing someone else's route.
		// Unique name so the explorer search narrows to exactly this row.
		// A short Melbourne-area polyline gives the detail map + scrubber
		// real geometry; >=2 waypoints so the geom trigger fires.
		routeName = `E2E discover route ${uniqueSuffix()}`;
		routeId = await insertRoute({
			user_id: owner.id,
			name: routeName,
			distance_m: 8000,
			elevation_m: 60,
			is_public: true,
			waypoints: [
				{ lat: -37.82, lng: 144.97, elevation_m: 20 },
				{ lat: -37.818, lng: 144.972, elevation_m: 25 },
				{ lat: -37.816, lng: 144.974, elevation_m: 30 },
				{ lat: -37.814, lng: 144.976, elevation_m: 35 },
				{ lat: -37.812, lng: 144.978, elevation_m: 40 },
				{ lat: -37.81, lng: 144.98, elevation_m: 45 }
			]
		});
	});

	test.afterAll(async () => {
		// Sweep the rows the journey planted through the UI (saved_routes
		// + route_reviews) before the route + users go. deleteSagaUsers
		// also wipes route_reviews/routes for owned ids, but the
		// discoverer's review + bookmark reference the OWNER's route, so
		// clear them explicitly first. Best-effort: deleteSagaUsers's
		// CASCADE on auth.users cleans up the discoverer's own rows too.
		const admin = getAdminClient();
		if (routeId) {
			await admin.from('route_reviews').delete().eq('route_id', routeId);
			await admin.from('saved_routes').delete().eq('route_id', routeId);
			await deleteRoute(routeId).catch(() => {});
		}
		if (users) await deleteSagaUsers(users);
	});

	test('discoverer finds the owner’s public route in Explore, saves it, reviews it, sees it in My routes', async ({
		browser
	}) => {
		const [, discoverer] = users;
		const ctx = await sagaContext(browser, discoverer);
		const page = await ctx.newPage();

		try {
			await test.step('1. DISCOVER — the public route surfaces in the community Explore search', async () => {
				// /routes?tab=explore mounts RouteExplorer. Its search box
				// drives search_public_routes (name ILIKE), so typing the
				// unique name + Enter narrows to exactly this one row. No
				// networkidle wait — the page holds an open realtime socket
				// (it never settles); poll for the concrete card instead.
				await page.goto('/routes?tab=explore');

				const searchBox = page.getByPlaceholder('Search routes by name...');
				await expect(searchBox).toBeVisible({ timeout: 15_000 });
				await searchBox.fill(routeName);
				await searchBox.press('Enter');

				// The explorer card is a .route-card wrapping an
				// <a class="route-link" href="/routes/{id}?from=explore">.
				const card = page.locator(`.route-card:has(a.route-link[href^="/routes/${routeId}"])`);
				await expect(card).toBeVisible({ timeout: 15_000 });
				await expect(card).toContainText(routeName);
			});

			await test.step('2. SAVE — bookmark the route from the explorer card', async () => {
				const card = page.locator(`.route-card:has(a.route-link[href^="/routes/${routeId}"])`);
				const saveBtn = card.locator('button.save-btn');
				await expect(saveBtn).toBeVisible({ timeout: 10_000 });
				// Pre-save the icon is `bookmark_add` and the button is not
				// `.saved`; the save writes a saved_routes reference (not a
				// clone, decisions §30).
				await expect(saveBtn).not.toHaveClass(/saved/);
				await saveBtn.click();
				// Optimistic flip to the saved state — icon → `bookmark`,
				// `.saved` class added. A success toast also fires; assert
				// on the durable button state, not the transient toast.
				await expect(saveBtn).toHaveClass(/saved/, { timeout: 10_000 });
				// Icon ligature flips from `bookmark_add` to exactly `bookmark`
				// (toHaveText is exact, so it won't false-match the `bookmark_add`
				// substring the unsaved state renders).
				await expect(saveBtn.locator('.material-symbols')).toHaveText('bookmark');
			});

			await test.step('3. OPEN — go to the route detail (non-owner view)', async () => {
				// Open via the explorer card's link so the from=explore
				// back-link path is exercised too. The detail page waits for
				// auth.ready() then fetches the row; poll for the h1.
				await page
					.locator(`.route-card a.route-link[href^="/routes/${routeId}"]`)
					.click();
				await page.waitForURL(new RegExp(`/routes/${routeId}`), { timeout: 10_000 });
				await expect(
					page.getByRole('heading', { name: routeName, level: 1 })
				).toBeVisible({ timeout: 15_000 });

				// Reviews section starts empty for a freshly-planted route.
				const reviewsSection = page.locator('.reviews-header');
				await expect(reviewsSection.locator('h2')).toContainText('Reviews');
				await expect(page.locator('.no-reviews')).toBeVisible({ timeout: 10_000 });
				// No aggregate yet — the avg-rating chip only renders once a
				// review exists.
				await expect(page.locator('.avg-rating')).toHaveCount(0);
			});

			const comment = 'Lovely riverside loop — great surface.';

			await test.step('4. REVIEW — open the Rate form, pick a rating, submit', async () => {
				// A logged-in non-owner sees the "Rate" toggle (owner-gated
				// affordances like the star are hidden — this is someone
				// else's route). Default reviewRating is 4; click the 5th
				// star to make the rating deterministic at 5.
				const rateToggle = page.getByRole('button', { name: 'Rate', exact: true });
				await expect(rateToggle).toBeVisible({ timeout: 10_000 });
				await rateToggle.click();

				const reviewForm = page.locator('.review-form');
				await expect(reviewForm).toBeVisible({ timeout: 10_000 });
				// Star buttons carry aria-label "Set rating to {n} of 5".
				await reviewForm.getByRole('button', { name: 'Set rating to 5 of 5' }).click();
				await reviewForm.locator('textarea.review-textarea').fill(comment);
				await reviewForm.getByRole('button', { name: 'Submit', exact: true }).click();
			});

			await test.step('5. REVIEW APPEARS — the review row + aggregate rating render on the route', async () => {
				// submitReview re-fetches getRouteReviews and closes the
				// form, so the row appears and the form disappears.
				await expect(page.locator('.review-form')).toHaveCount(0, { timeout: 10_000 });

				const reviewCard = page.locator('.review-card');
				await expect(reviewCard).toHaveCount(1, { timeout: 10_000 });
				await expect(reviewCard.locator('.review-comment')).toHaveText(comment);
				// Five filled stars for the rating-5 review.
				await expect(reviewCard.locator('.star-display.filled')).toHaveCount(5);

				// The aggregate now renders in the Reviews header: avgRating
				// = mean of one rating-5 review = "5.0", shown as "(5.0 / 5)".
				await expect(page.locator('.avg-rating')).toHaveText('(5.0 / 5)', {
					timeout: 10_000
				});
				// The empty-state copy is gone now that a review exists.
				await expect(page.locator('.no-reviews')).toHaveCount(0);
			});

			await test.step('6. REVIEW PERSISTS — a reload still shows the review + rating', async () => {
				// Guards against an optimistic-only render: the row must come
				// back from the server on a fresh load.
				await page.reload();
				await expect(
					page.getByRole('heading', { name: routeName, level: 1 })
				).toBeVisible({ timeout: 15_000 });
				await expect(page.locator('.review-card .review-comment')).toHaveText(comment, {
					timeout: 10_000
				});
				await expect(page.locator('.avg-rating')).toHaveText('(5.0 / 5)', {
					timeout: 10_000
				});
			});

			await test.step('7. MY ROUTES — the saved route shows in the discoverer’s library', async () => {
				// /routes My-routes is the union of owned + saved routes
				// (fetchRoutesWithError). The discoverer owns no routes, so
				// the only card present is the one they just saved. Narrow
				// by name to be robust, then assert the href matches the
				// owner's route id.
				await page.goto('/routes');
				const card = page.locator(`.route-card[href$="${routeId}"]`);
				await expect(card).toBeVisible({ timeout: 15_000 });
				await expect(card).toContainText(routeName);
			});
		} finally {
			await ctx.close();
		}
	});
});
