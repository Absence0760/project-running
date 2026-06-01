import { expect, test } from '@playwright/test';
import { USER_A } from '../fixtures/users';

/**
 * i18n foundation — client-side locale negotiation.
 *
 * The web app is statically prerendered (adapter-static, no per-request
 * SSR), so the locale is detected on first client mount from the browser
 * language and applied to <html lang/dir> + the message catalogue. These
 * tests drive the real negotiation end-to-end on an anon-allowed page
 * (/privacy renders the translated "skip to main content" link), proving
 * a non-English browser gets translated chrome with the correct lang
 * attribute, and that an unsupported language falls back to English.
 */

test.describe('i18n locale negotiation', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a German browser gets de chrome + <html lang="de">', async ({ browser }) => {
		const context = await browser.newContext({ locale: 'de-DE' });
		const page = await context.newPage();
		await page.goto('/privacy');
		await expect(page.locator('html')).toHaveAttribute('lang', 'de');
		await expect(page.locator('html')).toHaveAttribute('dir', 'ltr');
		await expect(page.locator('a.skip-link').first()).toHaveText('Zum Hauptinhalt springen');
		await context.close();
	});

	test('a Brazilian-Portuguese browser resolves to pt-BR', async ({ browser }) => {
		const context = await browser.newContext({ locale: 'pt-BR' });
		const page = await context.newPage();
		await page.goto('/privacy');
		await expect(page.locator('html')).toHaveAttribute('lang', 'pt-BR');
		await expect(page.locator('a.skip-link').first()).toHaveText(
			'Pular para o conteúdo principal',
		);
		await context.close();
	});

	test('an unsupported language falls back to English', async ({ browser }) => {
		const context = await browser.newContext({ locale: 'it-IT' });
		const page = await context.newPage();
		await page.goto('/privacy');
		await expect(page.locator('html')).toHaveAttribute('lang', 'en');
		await expect(page.locator('a.skip-link').first()).toHaveText('Skip to main content');
		await context.close();
	});
});

test.describe('i18n language picker (settings → preferences)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('picking a language translates the chrome and persists across reload', async ({ page }) => {
		await page.goto('/settings/preferences');
		// Seeded user is an English (en-GB) browser → English chrome.
		await expect(page.locator('.nav-label').first()).toHaveText('Dashboard');

		await page.locator('[data-testid="language-select"]').selectOption('de');

		// The whole app shell re-renders from the same reactive signal.
		await expect(page.locator('html')).toHaveAttribute('lang', 'de');
		await expect(page.locator('.nav-label').first()).toHaveText('Übersicht');

		// Persisted to localStorage → survives a reload (initLocale reads it
		// back before the browser-language negotiation).
		await page.reload();
		await expect(page.locator('html')).toHaveAttribute('lang', 'de');
		await expect(page.locator('.nav-label').first()).toHaveText('Übersicht');

		// Restore so the shared storage state doesn't leak a non-English
		// locale into later specs sharing this context.
		await page.locator('[data-testid="language-select"]').selectOption('en');
		await expect(page.locator('html')).toHaveAttribute('lang', 'en');
	});

	test('distance numbers follow the locale decimal separator (W-15)', async ({ page }) => {
		// Seed run "Tempo on Belle Isle" is 6500 m → 6.50 km / 6,50 km. The
		// run-detail page is filter-independent (unlike the date-filtered
		// /runs list), so the distance is deterministically present.
		const runUrl = '/runs/a1000001-0000-0000-0000-000000000001';
		await page.goto(runUrl);
		await expect(page.getByText('6.50 km').first()).toBeVisible();

		await page.goto('/settings/preferences');
		await page.locator('[data-testid="language-select"]').selectOption('de');
		await expect(page.locator('html')).toHaveAttribute('lang', 'de');

		await page.goto(runUrl);
		// German formats the same distance with a comma decimal separator.
		await expect(page.getByText('6,50 km').first()).toBeVisible();
		await expect(page.getByText('6.50 km')).toHaveCount(0);

		await page.goto('/settings/preferences');
		await page.locator('[data-testid="language-select"]').selectOption('en');
	});

	test('inline dates follow the locale (W-12)', async ({ page }) => {
		// Belle Isle run is 2026-05-15 → "May 15, 2026" / "15. Mai 2026".
		const runUrl = '/runs/a1000001-0000-0000-0000-000000000001';
		await page.goto(runUrl);
		await expect(page.getByText(/May 15, 2026/).first()).toBeVisible();

		await page.goto('/settings/preferences');
		await page.locator('[data-testid="language-select"]').selectOption('de');
		await page.goto(runUrl);
		// German month name proves the date helper picked up the locale.
		await expect(page.getByText(/Mai 2026/).first()).toBeVisible();
		await expect(page.getByText(/May 15, 2026/)).toHaveCount(0);

		await page.goto('/settings/preferences');
		await page.locator('[data-testid="language-select"]').selectOption('en');
	});

	test('plan calendar month + weekday names follow the locale (W-5)', async ({ page }) => {
		const planUrl = '/plans/a1a1eada-aaaa-0000-0000-000000000001';
		await page.goto(planUrl);
		// Monday-first (default), English abbreviations.
		await expect(page.locator('.dow-row span').first()).toHaveText('Mon');

		await page.goto('/settings/preferences');
		await page.locator('[data-testid="language-select"]').selectOption('de');
		await page.goto(planUrl);
		// German weekday abbreviation + localised long month header.
		await expect(page.locator('.dow-row span').first()).toHaveText('Mo');
		await expect(page.locator('.cal-head h3')).toHaveText(
			/Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember/,
		);

		await page.goto('/settings/preferences');
		await page.locator('[data-testid="language-select"]').selectOption('en');
	});
});
