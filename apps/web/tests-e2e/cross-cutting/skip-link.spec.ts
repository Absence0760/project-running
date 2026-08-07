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

// The 2026-05-30 audit above fixed the ANON branch and left the SHELL-LESS one,
// which is a different branch of the same {#if} — so all 24 of those routes
// (landing, login, every /share/*, /live/*, /learn*, the two invite landings)
// shipped with no bypass at all. §543 gave each of them its own
// `main#main-content`; this pins the link that makes the landmark reachable.
//
// Two routes rather than one, because they enter the branch by different rules:
// /login is a `shellLessExact` entry and /learn matches a `startsWith` prefix.
test.describe('skip link on shell-less pages', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const path of ['/login', '/learn']) {
		test(`${path} exposes a skip link that targets the main landmark`, async ({ page }) => {
			await page.goto(path);

			const skip = page.locator('a.skip-link[href="#main-content"]');
			await expect(skip).toHaveCount(1);
			await expect(page.locator('main#main-content')).toHaveCount(1);

			await page.keyboard.press('Tab');
			await expect(skip).toBeFocused();

			// Following it must actually bypass the chrome, which is the whole
			// point — and the assertion is deliberately NOT `main` is focused.
			// `<main>` carries no tabindex on any of these pages, so a fragment
			// navigation moves the sequential-focus starting point rather than
			// focus itself; activeElement stays on <body>. What a keyboard user
			// experiences is the NEXT Tab, which must land inside the landmark.
			// Asserting the platform's real behaviour keeps this from becoming a
			// test that only passes if someone adds a tabindex it doesn't need.
			await page.keyboard.press('Enter');
			await page.keyboard.press('Tab');
			await expect(
				page.locator('main#main-content :focus'),
				'the first Tab after following the skip link must land inside <main>',
			).toHaveCount(1);
		});
	}
});
