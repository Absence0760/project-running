import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes/new — "Describe the route you want" box (AI route assistant,
 * REQUEST half).
 *
 * The endpoint (`/api/coach/route-request`) is mocked at the network
 * layer so these tests don't need an Anthropic key: its real behaviour
 * (JWT verify, is_pro gate, forced-tool model call) is unit-tested in
 * `src/lib/routes/route_request/handler.test.ts`, and the validate/clamp
 * trust boundary in `constraints.test.ts`. Here we verify the page wiring
 * — the NL box populates the manual generator form on success, surfaces a
 * Pro upsell on a 403, and never breaks the manual form on failure.
 */

test.describe('/routes/new — AI route request', () => {
	test.use({ storageState: USER_A.storageStatePath });

	async function openDistancePanel(page: import('@playwright/test').Page) {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		// Reveal the generate-by-distance panel that hosts the NL box.
		await page.getByRole('button', { name: /Generate a route by distance/i }).click();
	}

	test('a successful extraction fills the generator form + shows what was applied', async ({
		page
	}) => {
		let called = false;
		await page.route('**/api/coach/route-request', async (route) => {
			called = true;
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					constraints: {
						distanceM: 10000,
						shape: 'out_and_back',
						surface: 'trail',
						avoidHighways: true,
						assumptions: []
					}
				})
			});
		});

		await openDistancePanel(page);

		await page
			.getByPlaceholder(/a flat 10k loop avoiding main roads/i)
			.fill('a hilly 10k trail out and back avoiding main roads');
		await page.getByRole('button', { name: /^Fill$/i }).click();

		// Distance slider value reflects the extracted 10 km.
		await expect(page.locator('.target-value')).toContainText(/10\.0 km/i, {
			timeout: 10_000
		});
		// Surface flipped to Trail.
		await expect(page.getByRole('button', { name: /^Trail$/i })).toHaveClass(/active/);
		// The "applied" panel surfaces the non-form constraints.
		await expect(page.locator('.ai-request-applied')).toBeVisible();
		await expect(page.locator('.ai-request-applied')).toContainText(/Out and back/i);
		await expect(page.locator('.ai-request-applied')).toContainText(/Avoid main roads/i);
		expect(called).toBe(true);
	});

	test('a 403 shows the Pro upsell and leaves the manual controls usable', async ({ page }) => {
		await page.route('**/api/coach/route-request', async (route) => {
			await route.fulfill({
				status: 403,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'pro required', upgrade: true })
			});
		});

		await openDistancePanel(page);

		await page.getByPlaceholder(/a flat 10k loop avoiding main roads/i).fill('a quiet 5k loop');
		await page.getByRole('button', { name: /^Fill$/i }).click();

		await expect(page.locator('.ai-request-error')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.ai-request-error')).toContainText(/Pro/i);
		// The manual distance slider + Generate button are still present and
		// usable — the NL box is purely additive.
		await expect(page.locator('.target-slider')).toBeVisible();
		await expect(page.getByRole('button', { name: /Generate .* loop/i })).toBeEnabled();
	});

	test('a 503 failure keeps the manual form working with a non-blocking hint', async ({
		page
	}) => {
		await page.route('**/api/coach/route-request', async (route) => {
			await route.fulfill({
				status: 503,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'route assistant unavailable' })
			});
		});

		await openDistancePanel(page);

		await page.getByPlaceholder(/a flat 10k loop avoiding main roads/i).fill('a 5k loop');
		await page.getByRole('button', { name: /^Fill$/i }).click();

		await expect(page.locator('.ai-request-error')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.ai-request-error')).toContainText(/unavailable/i);
		// No "applied" panel on failure; the manual controls are untouched.
		await expect(page.locator('.ai-request-applied')).toHaveCount(0);
		await expect(page.locator('.target-slider')).toBeVisible();
	});
});
