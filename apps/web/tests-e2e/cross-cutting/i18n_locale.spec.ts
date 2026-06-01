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
});
