import { expect, test } from '@playwright/test';

// audit-findings 2026-05-30 Medium [accessibility] (WCAG 2.4.1 Bypass
// Blocks): the signed-in shell has a "Skip to main content" link, but the
// anon-allowed long content pages (legal text, /compare) rendered without
// the shell — no skip link + no <main> landmark. Run as anon (no
// storageState) so the shell-less branch is exercised.
test.describe('skip link on anon content pages', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('/privacy exposes a skip link that targets the main landmark', async ({ page }) => {
		await page.goto('/privacy');

		const skip = page.locator('a.skip-link[href="#main-content"]');
		await expect(skip).toHaveCount(1);
		await expect(page.locator('main#main-content')).toHaveCount(1);

		// First Tab from the top of the document lands on the skip link
		// (it must be the first focusable element).
		await page.keyboard.press('Tab');
		await expect(skip).toBeFocused();
	});
});
