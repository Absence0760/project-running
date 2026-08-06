import { expect, type Page } from '@playwright/test';

/**
 * Shared contract for the WCAG 1.4.10 reflow specs. Extracted so the static
 * sweep (cross-cutting/reflow-narrow-viewport.spec.ts) and the seeded-dynamic
 * sweep (cross-cutting/reflow-seeded-routes.spec.ts) cannot drift into two
 * different definitions of "conforms".
 *
 * The assertion is the derivation, never a pixel (§ 500): a page conforms when
 * `documentElement.scrollWidth` is no wider than its `clientWidth`. Content
 * that genuinely cannot reflow — a data table, a segmented control, a course
 * editor's set grid — is allowed to scroll *inside its own* `overflow-x: auto`
 * box, which is exactly what that comparison tolerates and a hard px bound
 * would not.
 *
 * The 300 px row is headroom, not a stricter reading of the criterion. A page
 * whose narrowest fit is 318 px passes at 320 on one renderer and fails on
 * another: CI's Linux font stack measured these routes 12-20 px wider than a
 * macOS run, which is how `/routes` (318 px narrowest fit locally) passed
 * locally and failed CI at 330 (§ 535's amendment). Asserting one viewport
 * below the requirement converts that invisible 2 px into a visible 20 px, and
 * it is the same derivation — no absolute width is asserted anywhere.
 */
export const VIEWPORTS = [
	{ width: 300, height: 720 },
	{ width: 320, height: 720 },
	{ width: 360, height: 720 }
];

/** Enough descendants that a spinner or a redirect stub cannot satisfy it. */
export const MIN_MAIN_NODES = 10;

/**
 * Measure one route at every viewport and assert it reflows.
 *
 * `populated` is the § 534 half that a node floor alone does not give. Every
 * route here is behind an auth gate or a data fetch, and a page that rendered a
 * spinner, a redirect stub, or an empty state trivially fits any viewport —
 * which is exactly how four route families came to be recorded as "measured"
 * when nothing had rendered. Pass a locator that only resolves on the LOADED,
 * POPULATED page, and the assertion is a MINIMUM count, never an exact one: an
 * exact count is a seed-shape assertion that fails on any renderer or fixture
 * change, which round 15 shipped and CI rejected.
 */
export async function expectReflows(
	page: Page,
	route: string,
	populated?: { locator: string; min?: number }
) {
	for (const viewport of VIEWPORTS) {
		await page.setViewportSize(viewport);
		await page.goto(route);
		// Several of these routes paint an auth-gate stub first and fill in
		// once their fetch lands; measuring the stub would measure nothing.
		await page.waitForLoadState('networkidle');
		await expect(
			page.locator('#main-content').locator('a, button, h1, h2').first()
		).toBeVisible({ timeout: 15_000 });

		if (populated) {
			const found = page.locator(populated.locator);
			await expect(
				found.first(),
				`${route} at ${viewport.width}px never rendered ${populated.locator} — ` +
					`the page is in an empty / not-found state, so nothing real was measured`
			).toBeVisible({ timeout: 15_000 });
			expect(
				await found.count(),
				`${route} at ${viewport.width}px matched too few ${populated.locator}`
			).toBeGreaterThanOrEqual(populated.min ?? 1);
		}

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

		// A bare "scrollWidth 302 vs 300" says a page overflowed but not by what,
		// and the two causes need opposite fixes: a BOX wider than the viewport is
		// a rule (a fixed width, a flex item at its min-content floor), whereas a
		// container whose SCROLL extent exceeds its client width is content (an
		// unbreakable token in user-supplied text). Both were live on these routes
		// and neither was findable from the assertion message alone.
		if (measured.scrollWidth > measured.clientWidth) {
			const offenders = await page.evaluate((limit) => {
				const out: string[] = [];
				const name = (el: Element) =>
					`${el.tagName.toLowerCase()}.${(el.className || '').toString().split(' ').filter(Boolean).join('.')}`;
				for (const el of Array.from(document.querySelectorAll('*'))) {
					const r = el.getBoundingClientRect();
					if (r.right > limit + 0.5 || r.left < -0.5) {
						out.push(
							`BOX ${name(el)} left=${r.left.toFixed(1)} right=${r.right.toFixed(1)} w=${r.width.toFixed(1)}`
						);
					}
					if (el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0) {
						const cs = getComputedStyle(el);
						out.push(
							`SCROLL ${name(el)} scrollW=${el.scrollWidth} clientW=${el.clientWidth} overflowX=${cs.overflowX} minW=${cs.minWidth}`
						);
					}
				}
				return out.slice(0, 30);
			}, measured.clientWidth);
			console.log(`OFFENDERS ${route} @${viewport.width}:\n` + offenders.join('\n'));
		}

		expect(
			measured.scrollWidth,
			`${route} scrolls horizontally at ${viewport.width}px: scrollWidth ${measured.scrollWidth} vs clientWidth ${measured.clientWidth}`
		).toBeLessThanOrEqual(measured.clientWidth);
	}
}
