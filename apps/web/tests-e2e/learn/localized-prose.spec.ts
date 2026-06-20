import { expect, test } from '@playwright/test';

/**
 * `/learn/<slug>` localized prose + English fallback.
 *
 * All eight guides are now authored in all six locales (the prose
 * localization is complete — features/learn.md, decisions §179). So a
 * non-English visitor always gets a localized body and never the
 * "available in English only" notice for a real guide.
 *
 * The fallback path (English body + notice) is no longer reachable with
 * real content — there is no untranslated (slug, locale) pair left to
 * demonstrate it in the DOM. It stays guarded structurally in
 * guides.test.ts (every localized file must have an English sibling; a
 * missing localized file is what isEnglishFallback keys off). These e2e
 * cases assert the positive contract: the localized body renders and the
 * notice never appears for a real guide, in more than one locale.
 *
 * Locale is seeded into localStorage before the SPA boots so initLocale()
 * picks it up.
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

	test('a guide that used to be English-only now renders its localized body (de)', async ({
		context,
		page,
	}) => {
		await seedLocale(context, 'de');
		// couch-to-5k is now authored in German (prose localization is
		// complete) — the resolver serves the localized body, no notice.
		await page.goto('/learn/couch-to-5k');

		await expect(
			page.getByRole('heading', { level: 1, name: 'Couch to 5K: dein erster Monat' })
		).toBeVisible();
		// No fallback notice in any of its forms.
		await expect(page.getByText('available in English only')).toHaveCount(0);
		await expect(page.getByText(/nur auf Englisch/i)).toHaveCount(0);
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
