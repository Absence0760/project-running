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
		await expect(page).toHaveURL(new RegExp(`/recap/${CURRENT_YEAR}`));
		await expect(page.getByText(/Sign in to see your year/)).toBeVisible();
	});

	test('out-of-range year (1999) renders the picker hint', async ({ page }) => {
		await page.goto('/recap/1999');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
		await expect(page).toHaveURL(/\/recap\/1999/);
	});

	test('out-of-range year (2200) renders the same hint', async ({ page }) => {
		await page.goto('/recap/2200');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
	});

	test('non-numeric year is gracefully ignored', async ({ page }) => {
		await page.goto('/recap/abc');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
		await expect(page).toHaveURL(/\/recap\/abc/);
	});

	test('future year (2099) is in-range — anon falls through to sign-in prompt', async ({
		page
	}) => {
		await page.goto('/recap/2099');
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

		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		for (const label of [
			'Longest run',
			'Fastest pace',
			'Best streak',
			'Top week',
			'Routes run',
			'Earliest start',
			'Personal records',
			'Photos'
		]) {
			// exact: the card labels "Personal records" / "Photos" also appear
			// as substrings inside badge-detail text ("3 personal records").
			await expect(page.getByText(label, { exact: true })).toBeVisible();
		}

		// The seed user logs enough this year to earn at least one trophy.
		await expect(page.getByRole('heading', { name: 'Trophies' })).toBeVisible();

		await expect(page.getByRole('heading', { name: 'Distance by month' })).toBeVisible();
		const bars = page.locator('.bar-col');
		await expect(bars).toHaveCount(12);
	});

	test('empty-year recap renders the encouragement empty state', async ({ page }) => {
		await page.goto('/recap/2010');
		await expect(page.getByText(/No runs in 2010 yet/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Longest run')).toHaveCount(0);
	});

	test('future year (2099) — no data, renders the empty hero, not a 500', async ({ page }) => {
		const response = await page.goto('/recap/2099');
		expect(response?.status() ?? 0).toBeLessThan(500);
		await expect(page.getByText(/No runs in 2099 yet/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Longest run')).toHaveCount(0);
	});

	test('year before user joined (2011) — falls through to the same empty hero', async ({
		page
	}) => {
		await page.goto('/recap/2011');
		await expect(page.getByText(/No runs in 2011 yet/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Longest run')).toHaveCount(0);
	});

	test('Share recap button is visible on the populated path', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('button', { name: 'Share recap' })).toBeVisible();
	});

	test('Share recap shares the rendered card image when file-share is supported', async ({
		page
	}) => {
		await page.addInitScript(() => {
			const w = window as unknown as { __shared?: Record<string, unknown> };
			Object.defineProperty(navigator, 'canShare', {
				value: (data: { files?: unknown[] }) => Array.isArray(data?.files),
				configurable: true
			});
			Object.defineProperty(navigator, 'share', {
				value: async (data: { files?: File[]; title?: string; text?: string }) => {
					w.__shared = {
						fileCount: data.files?.length ?? 0,
						fileName: data.files?.[0]?.name ?? null,
						fileType: data.files?.[0]?.type ?? null,
						fileSize: data.files?.[0]?.size ?? 0,
						title: data.title ?? null,
						text: data.text ?? null
					};
				},
				configurable: true
			});
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: 'Share recap' }).click();

		const shared = await expect
			.poll(
				async () =>
					page.evaluate(() => (window as unknown as { __shared?: unknown }).__shared ?? null),
				{ timeout: 5_000 }
			)
			.not.toBeNull();
		const payload = (await page.evaluate(
			() => (window as unknown as { __shared: Record<string, unknown> }).__shared
		)) as Record<string, unknown>;
		expect(payload.fileCount).toBe(1);
		expect(payload.fileName).toBe(`threkir-${CURRENT_YEAR}.png`);
		expect(payload.fileType).toBe('image/png');
		expect(payload.fileSize as number).toBeGreaterThan(0);
		expect(payload.title).toBe(`My ${CURRENT_YEAR} in running`);
		void shared;
	});

	test('Share recap downloads the card image when file-share is unavailable', async ({ page }) => {
		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'canShare', { value: undefined, configurable: true });
			Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		const downloadPromise = page.waitForEvent('download', { timeout: 8_000 });
		await page.getByRole('button', { name: 'Share recap' }).click();
		const download = await downloadPromise;
		expect(download.suggestedFilename()).toBe(`threkir-${CURRENT_YEAR}.png`);
	});

	test('Falls back to clipboard text when card rendering fails', async ({ page, context }) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: 'http://localhost:7777'
		});

		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
			// Force the SVG→PNG rasterise to throw so the text fallback runs.
			HTMLCanvasElement.prototype.getContext = () => null as never;
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: 'Share recap' }).click();

		// Feedback is now a toast, not a native alert() dialog.
		await expect(page.locator('.toast-success')).toContainText(/copied to clipboard/i, {
			timeout: 5_000
		});

		const clipText = await page.evaluate(() => navigator.clipboard.readText());
		expect(clipText).toContain(`My ${CURRENT_YEAR} in running`);
		expect(clipText).toMatch(/Longest run:/);
		expect(clipText).toMatch(/Best streak:/);
		expect(clipText).toMatch(/Top week:/);
	});

	test('monthly recap route renders the month card', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}/1`);
		// The seed user has runs across the current year; January may or may not
		// be populated, so accept either the populated hero or the empty hero —
		// the point is the route resolves with a month-scoped card, never a 500.
		await expect(
			page.getByText(/in running/).first().or(page.getByText(/No runs in/))
		).toBeVisible({ timeout: 10_000 });
		// The monthly card hides the 12-month "Distance by month" chart.
		await expect(page.getByRole('heading', { name: 'Distance by month' })).toHaveCount(0);
	});

	test('out-of-range month falls through to the invalid-month hint', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}/13`);
		await expect(page.getByText(/Pick a month between/)).toBeVisible({ timeout: 10_000 });
	});

	test('Wrap-it-up closing CTA also shares the card image', async ({ page }) => {
		await page.addInitScript(() => {
			const w = window as unknown as { __sharedCount?: number };
			w.__sharedCount = 0;
			Object.defineProperty(navigator, 'canShare', {
				value: (data: { files?: unknown[] }) => Array.isArray(data?.files),
				configurable: true
			});
			Object.defineProperty(navigator, 'share', {
				value: async () => {
					w.__sharedCount = (w.__sharedCount ?? 0) + 1;
				},
				configurable: true
			});
		});

		await page.goto(`/recap/${CURRENT_YEAR}`);
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: `Share my ${CURRENT_YEAR}` }).click();

		await expect
			.poll(
				async () =>
					page.evaluate(() => (window as unknown as { __sharedCount?: number }).__sharedCount ?? 0),
				{ timeout: 5_000 }
			)
			.toBeGreaterThan(0);
	});
});
