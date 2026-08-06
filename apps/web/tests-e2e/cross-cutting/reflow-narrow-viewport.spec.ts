import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * WCAG 1.4.10 reflow: no route may make the document scroll sideways at the
 * 320 CSS px the criterion names, nor at the 360 px a common phone reports.
 *
 * The assertion is the derivation, never a pixel (§ 500): a page conforms when
 * `documentElement.scrollWidth` is no wider than its `clientWidth`. Content
 * that genuinely cannot reflow — a data table, a segmented control, a course
 * editor's set grid — is allowed to scroll *inside its own* `overflow-x: auto`
 * box, which is exactly what that comparison tolerates and a hard px bound
 * would not.
 *
 * The population check is not decoration (§ 534). Every route here is behind
 * an auth gate or a data fetch, and a page that rendered a spinner, a redirect
 * stub, or nothing at all trivially fits any viewport. Both halves — a visible
 * control or heading inside the page region, and a node-count floor under it —
 * are the weakest pair that still rules that out. A heading alone would not
 * do: `/routes` and `/plans` carry their title in the surface-tab strip and
 * have no `h1` in their loaded state at all.
 */

const VIEWPORTS = [
	{ width: 320, height: 720 },
	{ width: 360, height: 720 }
];

/** Enough descendants that a spinner or a redirect stub cannot satisfy it. */
const MIN_MAIN_NODES = 10;

async function expectReflows(page: import('@playwright/test').Page, route: string) {
	for (const viewport of VIEWPORTS) {
		await page.setViewportSize(viewport);
		await page.goto(route);
		// Several of these routes paint an auth-gate stub first and fill in
		// once their fetch lands; measuring the stub would measure nothing.
		await page.waitForLoadState('networkidle');
		await expect(
			page.locator('#main-content').locator('a, button, h1, h2').first()
		).toBeVisible({ timeout: 15_000 });

		const measured = await page.evaluate(() => {
			const de = document.documentElement;
			const main = document.querySelector('#main-content') ?? document.body;
			return {
				scrollWidth: de.scrollWidth,
				clientWidth: de.clientWidth,
				mainNodes: main.querySelectorAll('*').length
			};
		});

		expect(
			measured.mainNodes,
			`${route} at ${viewport.width}px rendered ${measured.mainNodes} nodes — too few to be measuring the real page`
		).toBeGreaterThanOrEqual(MIN_MAIN_NODES);

		expect(
			measured.scrollWidth,
			`${route} scrolls horizontally at ${viewport.width}px: scrollWidth ${measured.scrollWidth} vs clientWidth ${measured.clientWidth}`
		).toBeLessThanOrEqual(measured.clientWidth);
	}
}

test.describe('no horizontal document scroll at 320 / 360 px', () => {
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
