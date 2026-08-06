import { test } from '@playwright/test';

import { expectReflows } from '../fixtures/reflow';
import { USER_A } from '../fixtures/users';

/**
 * WCAG 1.4.10 reflow over the STATIC routes: no route may make the document
 * scroll sideways at the 320 CSS px the criterion names, at the 360 px a common
 * phone reports, nor at the 300 px added as renderer headroom.
 *
 * The measurement contract — the three viewports, the derivation-not-a-pixel
 * assertion, and the population halves — lives in `../fixtures/reflow`, shared
 * with the seeded-dynamic sweep in `reflow-seeded-routes.spec.ts`.
 *
 * The population check here is a visible control or heading inside the page
 * region plus a node-count floor: the weakest pair that rules out a spinner or
 * a redirect stub (§ 534). A heading alone would not do — `/routes` and
 * `/plans` carry their title in the surface-tab strip and have no `h1` in their
 * loaded state at all, which the first draft discovered by failing.
 */

test.describe('no horizontal document scroll at 300 / 320 / 360 px', () => {
	test('the cookie notice, whose consent tables scroll in their own box', async ({ page }) => {
		// Public on purpose: the only route in this spec reachable logged out,
		// and the one carrying raw <table> markup with no page chrome to hide
		// behind.
		await expectReflows(page, '/cookie-notice');
	});

	test.describe('signed in', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test.beforeEach(async ({ context }) => {
			await context.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
		});

		// /dashboard is the route the audit named; the rest are the other
		// shapes the same sweep found — a card grid, a filter toolbar, a
		// timeline, a settings shell, and the two split/grid editors.
		for (const route of [
			'/dashboard',
			'/runs',
			'/routes',
			'/explore',
			'/history',
			'/gym',
			'/nutrition',
			'/plans',
			'/challenges',
			'/coaching',
			'/sessions',
			'/settings',
			'/settings/licenses',
			'/plans/new',
			'/gym/routines/new'
		]) {
			test(route, async ({ page }) => {
				await expectReflows(page, route);
			});
		}
	});
});
