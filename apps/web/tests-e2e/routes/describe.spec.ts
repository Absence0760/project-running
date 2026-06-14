import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * /routes/[id] — "Describe this route" affordance.
 *
 * The endpoint (`/api/coach/route-describe`) is mocked at the network
 * layer so these tests don't need an Anthropic key: its real behaviour
 * (JWT verify, is_pro gate, model call, templated fallback) is unit-
 * tested in `src/lib/routes/route_describe/handler.test.ts`. Here we
 * verify the page wiring — the templated baseline renders instantly,
 * the AI text replaces it on a Pro success, the upgrade hint shows for
 * a free user, and a hard failure keeps the baseline.
 *
 * The seeded route (RUNNER_PUBLIC_ROUTE_ID) has no stored description,
 * so the Describe button is present. Each beforeEach clears any
 * description a prior run might have set.
 */

async function clearDescription(): Promise<void> {
	const admin = getAdminClient();
	await admin
		.from('routes')
		.update({ description: null, is_public: true })
		.eq('id', RUNNER_PUBLIC_ROUTE_ID);
}

test.describe('/routes/[id] — Describe (free user)', () => {
	test.use({ storageState: USER_A.storageStatePath });
	test.beforeEach(clearDescription);

	test('Describe renders the templated baseline + a Pro upgrade hint', async ({ page }) => {
		let called = false;
		await page.route('**/api/coach/route-describe', async (route) => {
			called = true;
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					description: 'E2E demo public route is a 10.00 km road point-to-point route.',
					source: 'template',
					upgrade: true
				})
			});
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		const describeBtn = page.getByRole('button', { name: /Describe this route/i });
		await expect(describeBtn).toBeVisible({ timeout: 10_000 });
		await describeBtn.click();

		// The templated baseline appears (rendered locally before the
		// fetch resolves); the upgrade hint surfaces after the response.
		await expect(page.locator('.route-description')).toBeVisible();
		await expect(page.locator('.route-description')).toContainText(/road .*route/i);
		await expect(page.locator('.desc-upgrade')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.desc-upgrade')).toContainText(/Pro/i);
		// No AI attribution on the free / templated path.
		await expect(page.locator('.desc-attribution')).toHaveCount(0);
		expect(called).toBe(true);
	});

	test('hard failure keeps the templated baseline and shows a non-blocking error', async ({
		page
	}) => {
		await page.route('**/api/coach/route-describe', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'tier check failed' })
			});
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: /Describe this route/i }).click();

		// The locally-rendered templated baseline must remain visible —
		// the L4 enhancement failure never erases the L1 baseline.
		await expect(page.locator('.route-description')).toBeVisible();
		await expect(page.locator('.route-description')).toContainText(/road .*route/i);
		// And a non-blocking error is surfaced.
		await expect(page.locator('.desc-error')).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/routes/[id] — Describe (Pro user)', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });
	test.beforeEach(clearDescription);

	test('Describe replaces the baseline with AI text + attribution', async ({ page }) => {
		await page.route('**/api/coach/route-describe', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					description:
						'A flowing 10 km road loop with gentle climbs — a steady, scenic effort that rewards an even pace.',
					source: 'ai',
					upgrade: false
				})
			});
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: /Describe this route/i }).click();

		await expect(page.locator('.route-description')).toContainText(
			/flowing 10 km road loop/i,
			{ timeout: 10_000 }
		);
		// AI source shows the attribution; no upgrade hint.
		await expect(page.locator('.desc-attribution')).toBeVisible();
		await expect(page.locator('.desc-upgrade')).toHaveCount(0);
	});
});
