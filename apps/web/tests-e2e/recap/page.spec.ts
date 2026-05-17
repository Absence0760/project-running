import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

const CURRENT_YEAR = new Date().getFullYear();

test.describe('/recap/[year] — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('valid year still loads (no auth-wall redirect)', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');
		await expect(page).toHaveURL(new RegExp(`/recap/${CURRENT_YEAR}`));
		await expect(page.getByText(/Sign in to see your year/)).toBeVisible();
	});

	test('out-of-range year (1999) renders the picker hint', async ({ page }) => {
		await page.goto('/recap/1999');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
		await expect(page).toHaveURL(/\/recap\/1999/);
	});

	test('out-of-range year (2200) renders the same hint', async ({ page }) => {
		await page.goto('/recap/2200');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
	});

	test('non-numeric year is gracefully ignored', async ({ page }) => {
		await page.goto('/recap/abc');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
		await expect(page).toHaveURL(/\/recap\/abc/);
	});

	test('future year (2099) is in-range — anon falls through to sign-in prompt', async ({
		page
	}) => {
		await page.goto('/recap/2099');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/Sign in to see your year/)).toBeVisible();
		await expect(page.getByText(/Pick a year between/)).toHaveCount(0);
	});

	test('document title reflects the year param', async ({ page }) => {
		await page.goto('/recap/2024');
		await expect(page).toHaveTitle(/2024 in running/);
	});

	test('non-numeric year does not 500 — page renders normally', async ({ page }) => {
		const response = await page.goto('/recap/foo');
		expect(response?.status() ?? 0).toBeLessThan(500);
		await expect(page.getByText(/Pick a year between/)).toBeVisible();
	});
});

test.describe('/recap/[year] — signed-in seed user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('current-year recap renders hero + cards + monthly chart', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');

		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		for (const label of [
			'Longest run',
			'Fastest pace',
			'Best streak',
			'Top week',
			'Routes run',
			'Earliest start'
		]) {
			await expect(page.getByText(label)).toBeVisible();
		}

		await expect(page.getByRole('heading', { name: 'Distance by month' })).toBeVisible();
		const bars = page.locator('.bar-col');
		await expect(bars).toHaveCount(12);
	});

	test('empty-year recap renders the encouragement empty state', async ({ page }) => {
		await page.goto('/recap/2010');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/No runs in 2010 yet/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Longest run')).toHaveCount(0);
	});

	test('future year (2099) — no data, renders the empty hero, not a 500', async ({ page }) => {
		const response = await page.goto('/recap/2099');
		expect(response?.status() ?? 0).toBeLessThan(500);
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/No runs in 2099 yet/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Longest run')).toHaveCount(0);
	});

	test('year before user joined (2011) — falls through to the same empty hero', async ({
		page
	}) => {
		await page.goto('/recap/2011');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/No runs in 2011 yet/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Longest run')).toHaveCount(0);
	});

	test('Share recap button is visible on the populated path', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('button', { name: 'Share recap' })).toBeVisible();
	});

	test('Share recap button copies a recap summary to the clipboard', async ({
		page,
		context
	}) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: 'http://localhost:7777'
		});

		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
		});

		const alerts: string[] = [];
		page.on('dialog', async (dialog) => {
			alerts.push(dialog.message());
			await dialog.dismiss();
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: 'Share recap' }).click();

		await expect.poll(() => alerts.length, { timeout: 5_000 }).toBeGreaterThan(0);
		expect(alerts[0]).toMatch(/copied to clipboard/i);

		const clipText = await page.evaluate(() => navigator.clipboard.readText());
		expect(clipText).toContain(`My ${CURRENT_YEAR} in running`);
		expect(clipText).toMatch(/Longest run:/);
		expect(clipText).toMatch(/Best streak:/);
		expect(clipText).toMatch(/Top week:/);
	});

	test('Wrap-it-up closing CTA also triggers share copy', async ({ page, context }) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: 'http://localhost:7777'
		});

		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
		});

		const alerts: string[] = [];
		page.on('dialog', async (dialog) => {
			alerts.push(dialog.message());
			await dialog.dismiss();
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: `Share my ${CURRENT_YEAR}` }).click();

		await expect.poll(() => alerts.length, { timeout: 5_000 }).toBeGreaterThan(0);
		expect(alerts[0]).toMatch(/copied to clipboard/i);
	});
});
