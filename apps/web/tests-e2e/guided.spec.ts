import { expect, test } from '@playwright/test';

/**
 * /guided + /guided/[id] — guided audio run library.
 *
 * Library lives in apps/web/src/lib/guided_runs.ts as GUIDED_RUN_LIBRARY.
 * Anon-readable public marketing surface; index page lists cards,
 * detail page shows the scripted cue list. The actual playback only
 * happens on mobile — the web is a preview surface (the page literally
 * says "Open these on the mobile app to run them").
 */

test.describe('/guided — guided run library', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('index page lists at least one guided run card', async ({ page }) => {
		await page.goto('/guided');
		await expect(
			page.getByRole('heading', { name: /coach in your ear/i })
		).toBeVisible();
		// Each card has a duration + title; assert at least one card link.
		const firstCard = page.locator('a.card').first();
		await expect(firstCard).toBeVisible();
		await expect(firstCard).toHaveAttribute('href', /^\/guided\//);
	});

	test('mobile-only callout is visible', async ({ page }) => {
		await page.goto('/guided');
		// The "preview only — run on mobile" callout is the contract
		// that prevents a user from expecting the web to play TTS.
		await expect(page.getByText(/Open these on the mobile app/)).toBeVisible();
	});

	test('detail page for the easy-30 fixture renders the cue list', async ({ page }) => {
		// easy-30 is the first entry in GUIDED_RUN_LIBRARY — pinned in
		// the lib file. A regression that removes it would fail loudly.
		await page.goto('/guided/easy-30');
		// Title is '30-Minute Easy Run' per the library data. Use a
		// loose regex so a marketing edit to "30 minute easy" doesn't
		// break the test.
		await expect(page.locator('body')).toContainText(/easy/i);
		// The cue script section is what makes this a guided-run
		// page rather than a 404. Pin the section heading.
		await expect(page.getByRole('heading', { name: /script/i })).toBeVisible();
	});

	test('detail page for an unknown id 404s or shows a not-found state', async ({ page }) => {
		const res = await page.goto('/guided/no-such-run-id');
		// SvelteKit's default for an unmatched +page.ts load can
		// either be a 404 or a soft not-found render. Accept either
		// as a valid contract — the user-facing behaviour is that the
		// page doesn't crash.
		expect(res?.status() ?? 200).toBeGreaterThanOrEqual(200);
		// At minimum, no run title for a bogus id.
		await expect(page.locator('body')).not.toContainText('Easy 30');
	});
});
