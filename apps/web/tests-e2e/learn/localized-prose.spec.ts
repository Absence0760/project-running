import { expect, test } from '@playwright/test';

/**
 * `/learn/<slug>` localized prose + English fallback.
 *
 * road-running-101 is authored in all six locales; the other guides are
 * English-only. A non-English visitor must get the localized body when one
 * exists (no fallback notice), and the English body + a "this guide is in
 * English" notice when it does not. Locale is seeded into localStorage
 * before the SPA boots so initLocale() picks it up.
 */

// initLocale() reads localStorage['locale'] on first client mount and swaps
// the catalogue + drives the per-locale guide resolution. addInitScript
// serialises the function into the page, so the locale MUST be passed as
// the explicit arg — a closed-over variable is undefined in the browser.
async function seedLocale(context: import('@playwright/test').BrowserContext, locale: string) {
	await context.addInitScript((loc) => {
		localStorage.setItem('locale', loc);
	}, locale);
}

test.describe('/learn localized prose', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a localized guide renders its translated body with no fallback notice (de)', async ({
		context,
		page,
	}) => {
		await seedLocale(context, 'de');
		await page.goto('/learn/road-running-101');

		// German H1 (frontmatter title) once the active locale resolves.
		await expect(page.getByRole('heading', { level: 1, name: 'Straßenlauf 101' })).toBeVisible();
		// A known marker from the German body.
		await expect(page.getByText('Was Straßenlaufen wirklich ist')).toBeVisible();
		// No English-fallback notice: this slug IS localized in German.
		await expect(page.getByText('available in English only')).toHaveCount(0);
	});

	test('an untranslated guide falls back to English with the notice (de)', async ({
		context,
		page,
	}) => {
		await seedLocale(context, 'de');
		// couch-to-5k is English-only — the resolver must fall back.
		await page.goto('/learn/couch-to-5k');

		// The fallback notice tells the German visitor the body is English.
		await expect(page.getByText(/nur auf Englisch/i)).toBeVisible();
		// And the body itself is the English source (a known English marker).
		await expect(
			page.getByRole('heading', { level: 1, name: 'Couch to 5K: your first month' })
		).toBeVisible();
	});

	test('the localized card title surfaces on the hub for a non-English visitor (fr)', async ({
		context,
		page,
	}) => {
		await seedLocale(context, 'fr');
		await page.goto('/learn');

		// The hub card for road-running-101 shows its French title (the
		// localized frontmatter), proving hub→article consistency.
		const card = page.locator('a.guide-card[href="/learn/road-running-101"]');
		await expect(card.getByRole('heading', { name: 'La course sur route 101' })).toBeVisible();
	});

	test('English visitors see the English body and no notice', async ({ page }) => {
		await page.goto('/learn/road-running-101');
		await expect(page.getByRole('heading', { level: 1, name: 'Road running 101' })).toBeVisible();
		await expect(page.getByText('What road running actually is')).toBeVisible();
		await expect(page.getByText('available in English only')).toHaveCount(0);
	});
});
