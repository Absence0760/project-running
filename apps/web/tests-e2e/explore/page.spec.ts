import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

test.describe('/explore — authed user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('redirects to /routes?tab=explore', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });
		await expect(page.getByRole('tab', { name: /Explore/ })).toHaveAttribute(
			'aria-selected',
			'true',
			{ timeout: 10_000 }
		);
	});

	test('Explore tab is the only one with aria-selected=true post-redirect', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });

		const tabs = page.getByRole('tab');
		await expect(tabs).toHaveCount(3, { timeout: 10_000 });
		await expect(page.getByRole('tab', { name: /My routes/ })).toHaveAttribute(
			'aria-selected',
			'false'
		);
		await expect(page.getByRole('tab', { name: /Explore/ })).toHaveAttribute(
			'aria-selected',
			'true'
		);
		await expect(page.getByRole('tab', { name: /Heatmap/ })).toHaveAttribute(
			'aria-selected',
			'false'
		);
	});

	test('Explore tab content (RouteExplorer) mounts after the redirect', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });
		await expect(page.getByRole('tab', { name: /Explore/ })).toHaveAttribute(
			'aria-selected',
			'true',
			{ timeout: 10_000 }
		);
		await expect(page.getByRole('tab', { name: /My routes/ })).toBeVisible();
	});

	test('post-redirect URL preserves no extra query params', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });
		const url = new URL(page.url());
		expect(url.pathname).toBe('/routes');
		expect(url.searchParams.get('tab')).toBe('explore');
	});
});

test.describe('/explore — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('anon visitor bounces through the auth wall to /login with return_to', async ({ page }) => {
		await page.goto('/explore');
		await expect(page).toHaveURL(/\/login(\?|$)/, { timeout: 10_000 });

		const url = new URL(page.url());
		const returnTo = url.searchParams.get('return_to');
		if (returnTo) {
			expect(returnTo).toMatch(/\/(explore|routes)/);
		}
	});
});
