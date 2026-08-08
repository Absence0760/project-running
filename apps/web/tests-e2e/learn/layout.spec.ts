import { expect, test } from '@playwright/test';

/**
 * The three /learn routes share one page shell (LearnPage.svelte).
 *
 * Each page used to hand-roll its own `.learn-page` wrapper and column
 * width, and they drifted: the hub's header sat in a 56rem column while
 * its own card grid was 64rem, so the heading and the cards it labels
 * did not share a left edge, and the hub centred its header where both
 * sibling pages left-align. Assert the geometry rather than the CSS —
 * a heading that stops lining up with the body it introduces is the
 * regression, whichever rule causes it.
 */

const PAGES = [
	{ path: '/learn', body: '.card-elevated' },
	{ path: '/learn/category/getting-started', body: '.card-elevated' },
	{ path: '/learn/road-running-101', body: '.prose p' },
];

const leftOf = async (page: import('@playwright/test').Page, selector: string) => {
	const box = await page.locator(selector).first().boundingBox();
	if (!box) throw new Error(`no box for ${selector}`);
	return Math.round(box.x);
};

test.describe('/learn shared page shell', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const { path, body } of PAGES) {
		// 1024 is above the 48rem breakpoint where the column gutter widens;
		// 1440 is wide enough that the max-width, not the gutter, decides.
		for (const width of [1024, 1440]) {
			test(`${path} lines its breadcrumb, heading and body up at ${width}px`, async ({
				page,
			}) => {
				await page.setViewportSize({ width, height: 900 });
				await page.goto(path);
				await expect(page.locator('h1')).toBeVisible();

				const [crumb, heading, firstBody] = await Promise.all([
					leftOf(page, '.breadcrumb'),
					leftOf(page, 'h1'),
					leftOf(page, body),
				]);

				expect(heading).toBe(crumb);
				expect(heading).toBe(firstBody);
			});
		}
	}

	test('the hub and its category pages share one column width', async ({ page }) => {
		await page.setViewportSize({ width: 1440, height: 900 });

		await page.goto('/learn');
		const hub = await leftOf(page, 'h1');

		await page.goto('/learn/category/getting-started');
		const category = await leftOf(page, 'h1');

		// Same shell, same width variant — so navigating between them must
		// not shift the heading sideways.
		expect(hub).toBe(category);
	});

	test('every learn page carries exactly one skip-link target', async ({ page }) => {
		for (const { path } of PAGES) {
			await page.goto(path);
			await expect(page.locator('#main-content')).toHaveCount(1);
		}
	});
});
