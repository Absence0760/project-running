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

			// The link must come BEFORE the region it skips — that is the whole of
			// the ordering claim, and it is asserted as document order rather than
			// as "the first Tab reaches it". The dev server injects focusables of
			// its own into the page asynchronously (a Sentry DPA link, ahead of the
			// skip link on some runs), and they exist on no production build, so
			// any first-focusable or first-Tab assertion measures a race with the
			// harness instead of the page. Document order cannot be perturbed by
			// something appended elsewhere.
			const precedesMain = await page.evaluate(() => {
				const link = document.querySelector('a.skip-link[href="#main-content"]');
				const main = document.querySelector('main#main-content');
				if (!link || !main) return null;
				// DOCUMENT_POSITION_FOLLOWING: main comes after the link.
				return Boolean(link.compareDocumentPosition(main) & Node.DOCUMENT_POSITION_FOLLOWING);
			});
			expect(precedesMain, 'the skip link must precede <main> in document order').toBe(true);

			// Following it must actually bypass the chrome, which is the whole
			// point — and the assertion is deliberately NOT `main` is focused.
			// `<main>` carries no tabindex on any of these pages, so a fragment
			// navigation moves the sequential-focus starting point rather than
			// focus itself; activeElement stays on <body>. What a keyboard user
			// experiences is the NEXT Tab, which must land inside the landmark.
			// Asserting the platform's real behaviour keeps this from becoming a
			// test that only passes if someone adds a tabindex it doesn't need.
			await skip.focus();
			await page.keyboard.press('Enter');
			await page.keyboard.press('Tab');
			await expect(
				page.locator('main#main-content :focus'),
				'the first Tab after following the skip link must land inside <main>',
			).toHaveCount(1);
		});
	}
});
