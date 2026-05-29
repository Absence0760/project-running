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
