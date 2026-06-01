import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

test.describe('/runs/heatmap — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('anon is bounced to sign-in by the runs auth guard, no map', async ({ page }) => {
		await page.goto('/runs/heatmap');
		await expect(page.getByRole('heading', { name: /Sign in/i })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('personal-heatmap-map')).toHaveCount(0);
	});
});

test.describe('/runs/heatmap — signed-in seed user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('renders the heading + map and resolves loading to legend or empty', async ({ page }) => {
		await page.goto('/runs/heatmap');
		await expect(page.getByRole('heading', { name: 'Your heatmap' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('personal-heatmap-map')).toBeVisible();

		// The component downloads the user's tracks then either renders a
		// legend (data present) or an empty state (no mapped runs). Either
		// is a pass; what must NOT persist is the loading spinner.
		await expect(page.getByTestId('personal-heatmap-loading')).toHaveCount(0, {
			timeout: 20_000
		});
		const legend = page.getByTestId('personal-heatmap-legend');
		const empty = page.getByTestId('personal-heatmap-empty');
		await expect(legend.or(empty)).toBeVisible();
	});

	test('Heatmap link on the runs page navigates here', async ({ page }) => {
		await page.goto('/runs');
		await page.getByRole('link', { name: 'Heatmap' }).click();
		await expect(page).toHaveURL(/\/runs\/heatmap/);
		await expect(page.getByRole('heading', { name: 'Your heatmap' })).toBeVisible({
			timeout: 10_000
		});
	});
});

test.describe('/runs/heatmap — signed-in, consent NOT accepted', () => {
	// The persisted USER_A storageState bakes accepted consent; clear it
	// before each navigation so we exercise the not-yet-consented path.
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.removeItem('cookie_consent');
		});
	});

	test('gates the MapTiler map behind a Load-map tap (no auto-init before consent)', async ({
		page
	}) => {
		await page.goto('/runs/heatmap');

		// The consent card must show; the map must NOT auto-initialise
		// (MapTiler would log the IP per tile fetch before consent).
		const card = page.getByTestId('personal-heatmap-consent');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('personal-heatmap-legend')).toHaveCount(0);
		await expect(page.getByTestId('personal-heatmap-loading')).toHaveCount(0);
		const beforeInit = await page.evaluate(
			() => (window as { __personalHeatmap?: unknown }).__personalHeatmap ?? null
		);
		expect(beforeInit).toBeNull();

		// Tapping Load map is the affirmative act — the map initialises.
		await page.getByRole('button', { name: 'Load map' }).click();
		await expect(card).toHaveCount(0);
		await expect(page.getByTestId('personal-heatmap-map')).toBeVisible();
		await expect(page.getByTestId('personal-heatmap-loading')).toHaveCount(0, {
			timeout: 20_000
		});
		await expect(
			page
				.getByTestId('personal-heatmap-legend')
				.or(page.getByTestId('personal-heatmap-empty'))
		).toBeVisible();
	});
});
