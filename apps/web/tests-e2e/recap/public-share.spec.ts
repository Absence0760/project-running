import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

const CURRENT_YEAR = new Date().getFullYear();
// A random, never-published uuid — the private-by-default / revoked case.
const UNKNOWN_ID = '00000000-0000-4000-8000-00000000dead';

test.describe('/recap/share/[id] — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('an unpublished id renders the not-found fallback, not a 500', async ({ page }) => {
		const response = await page.goto(`/recap/share/${UNKNOWN_ID}`);
		expect(response?.status() ?? 0).toBeLessThan(500);
		await expect(page.getByText(/isn't available/)).toBeVisible({ timeout: 10_000 });
	});

	test('the og:image endpoint always returns a 200 PNG (never a broken unfurl)', async ({
		request
	}) => {
		const res = await request.get(`/og/recap/${UNKNOWN_ID}.png`);
		expect(res.status()).toBe(200);
		expect(res.headers()['content-type']).toBe('image/png');
		const body = await res.body();
		expect(body.length).toBeGreaterThan(0);
	});
});

test.describe('/recap/share/[id] — publish round-trip (seed user)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('publish from /recap/[year] then load the public link with OG tags', async ({
		page,
		context
	}) => {
		// Stub the share sheet + clipboard so "Publish & copy link" resolves
		// deterministically and we can read the minted URL back.
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: 'http://localhost:7777'
		});
		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		const publishBtn = page.getByRole('button', { name: 'Publish & copy link' });
		await expect(publishBtn).toBeVisible();
		await publishBtn.click();

		// The copied link is /recap/share/<uuid>.
		const link = await expect
			.poll(async () => page.evaluate(() => navigator.clipboard.readText()), { timeout: 8_000 })
			.toMatch(/\/recap\/share\/[0-9a-f-]{36}$/);
		void link;
		const url = await page.evaluate(() => navigator.clipboard.readText());
		const id = url.split('/').pop()!;

		// Load the public share page as the same session and assert OG tags +
		// the rendered card.
		await page.goto(`/recap/share/${id}`);
		await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
			'content',
			`/og/recap/${id}.png`
		);
		await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
			'content',
			'summary_large_image'
		);
		await expect(page.getByText(/in running/).first()).toBeVisible({ timeout: 10_000 });
	});
});
