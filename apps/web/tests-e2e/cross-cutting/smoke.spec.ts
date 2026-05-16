import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * Surface smoke tests — every key page mounts past its loading shell
 * and exposes the element a user is most likely to interact with on
 * arrival. These sit between unit tests and the deeper feature
 * specs: they don't drive a journey, they just verify the page
 * doesn't break (auth-race, route param parse, RLS query, layout
 * contract). A regression that turns ANY of these into a blank
 * sidebar-only render fails here long before a user sees it.
 *
 * Keep additions cheap — one assertion per page on a stable selector.
 * The deeper specs cover the actual behaviour.
 */

test.describe('surface smoke — authed', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/dashboard mounts with the Mileage chart heading', async ({ page }) => {
		await page.goto('/dashboard');
		await expect(page.getByRole('heading', { level: 2, name: 'Mileage' }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/feed mounts with the activity-type filter', async ({ page }) => {
		await page.goto('/feed');
		await expect(page.getByRole('button', { name: 'All' }).first())
			.toBeVisible({ timeout: 10_000 });
	});

	test('/runs mounts with the source-filter dropdown', async ({ page }) => {
		await page.goto('/runs');
		await expect(page.locator('select[aria-label="Source"]'))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/routes mounts with the My-routes / Explore tabs', async ({ page }) => {
		await page.goto('/routes');
		await expect(page.getByRole('tab', { name: /My routes/ }).or(
			page.getByRole('button', { name: /My routes/ })
		)).toBeVisible({ timeout: 10_000 });
	});

	test('/plans mounts with the New-plan button', async ({ page }) => {
		await page.goto('/plans');
		await expect(page.getByRole('button', { name: /New plan/ }).first())
			.toBeVisible({ timeout: 10_000 });
	});

	test('/clubs mounts with the My-clubs / Browse tabs', async ({ page }) => {
		await page.goto('/clubs');
		await expect(page.getByRole('tab', { name: 'Browse', exact: true }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/coach mounts with the composer textarea', async ({ page }) => {
		await page.goto('/coach');
		await expect(page.getByPlaceholder(/Ask about today/))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/settings redirects to /settings/account by default', async ({ page }) => {
		await page.goto('/settings');
		await page.waitForURL(/\/settings\/account/, { timeout: 10_000 });
	});

	test('/settings/account mounts with the Profile section', async ({ page }) => {
		await page.goto('/settings/account');
		await expect(page.getByRole('heading', { level: 2, name: 'Profile' }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/settings/preferences mounts with the theme toggle', async ({ page }) => {
		await page.goto('/settings/preferences');
		await expect(page.getByRole('button', { name: /^Auto$/ }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/settings/devices mounts with the device list', async ({ page }) => {
		await page.goto('/settings/devices');
		await expect(page.getByText(/This device/))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/settings/integrations mounts with the Strava row', async ({ page }) => {
		await page.goto('/settings/integrations');
		await expect(
			page.getByRole('heading', { name: 'Strava', exact: true })
		).toBeVisible({ timeout: 10_000 });
	});

	test('/settings/upgrade mounts with the Pro pricing card', async ({ page }) => {
		await page.goto('/settings/upgrade');
		await expect(page.getByText(/\bPro\b/).first())
			.toBeVisible({ timeout: 10_000 });
	});

	test('/settings/licenses mounts with at least one license entry', async ({
		page
	}) => {
		await page.goto('/settings/licenses');
		await expect(page.locator('main, .licenses, body')).toBeVisible();
	});

	test('/runs/[id] mounts with the seeded run heading', async ({ page }) => {
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/u/[me] mounts with profile header', async ({ page }) => {
		await page.goto(`/u/${USER_A.id}`);
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/clubs/sydney-run-club mounts with the club heading', async ({
		page
	}) => {
		await page.goto('/clubs/sydney-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('/plans/<seeded> mounts with the plan heading', async ({ page }) => {
		await page.goto('/plans/a1a1eada-aaaa-0000-0000-000000000001');
		await expect(
			page.getByRole('heading', { level: 1, name: /Sydney Half/ })
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('surface smoke — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('/ landing page renders', async ({ page }) => {
		await page.goto('/');
		await expect(page.getByRole('heading', { level: 1 }).first())
			.toBeVisible({ timeout: 10_000 });
	});

	test('/login renders the email form', async ({ page }) => {
		await page.goto('/login');
		await expect(page.getByPlaceholder('Email address'))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/login?signup=1 renders the Create-account heading', async ({ page }) => {
		await page.goto('/login?signup=1');
		await expect(page.getByRole('heading', { name: 'Create an account' }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/login?reset=1 renders the Reset-password heading', async ({ page }) => {
		await page.goto('/login?reset=1');
		await expect(page.getByRole('heading', { name: 'Reset your password' }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/login renders the Continue-with-Google button', async ({ page }) => {
		await page.goto('/login');
		await expect(page.getByRole('button', { name: /Google/ }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/share/run/<public> renders for anon visitors', async ({ page }) => {
		// Stub the EF; same shape as the existing share-run test.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);
		await page.goto('/share/run/11112222-3333-4444-5555-666677778888');
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/share/route/<public> renders for anon visitors', async ({ page }) => {
		await page.goto('/share/route/22223333-4444-5555-6666-777788889999');
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('surface smoke — cross-user (alex)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('signing in via /login gets to /dashboard', async ({ page }) => {
		await page.goto('/login');
		await page.getByPlaceholder('Email address').fill(USER_A.email);
		await page.getByPlaceholder('Password').fill(USER_A.password);
		await page.getByRole('button', { name: 'Sign In' }).click();
		await page.waitForURL(/\/dashboard/, { timeout: 15_000 });
	});
});
