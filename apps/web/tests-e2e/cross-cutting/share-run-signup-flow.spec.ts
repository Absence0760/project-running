import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /share/run/<id> → signup conversion saga.
 *
 * The whole point of the public run share page (no auth required) is
 * to convert anonymous visitors who landed via a shared link into
 * accounts. The pinned bottom signup CTA card that lives on the page
 * is the only call-to-action a non-logged-in viewer sees, and its
 * link must drop the visitor into the signup form with the GDPR Art
 * 8 age gate + ToS consent boxes showing.
 *
 * Two paths pinned here:
 *  1. Anon viewer sees the CTA, clicks through, lands on
 *     /login?signup=1 with both consent boxes visible.
 *  2. Signed-in viewer at the same URL does NOT see the CTA — the
 *     `{#if !auth.loggedIn && hasRun}` guard on the share page must
 *     keep working.
 */

test.describe('/share/run/<id> — signup conversion', () => {
	test('anon visitor sees pinned signup CTA → lands on /login?signup=1 with age + ToS boxes', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		const page = await ctx.newPage();
		try {
			await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

			await expect(page.getByText('A run on Threkir')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
			await expect(page.locator('.hero .subtitle')).toBeVisible();

			const cta = page.locator('.signup-cta');
			await expect(cta).toBeVisible({ timeout: 10_000 });
			await expect(
				cta.getByRole('heading', { name: /Sign up to track your own runs/i }),
			).toBeVisible();

			const signupLink = cta.getByRole('link', { name: /Sign up/i });
			await expect(signupLink).toHaveAttribute('href', '/login?signup=1');
			await signupLink.click();

			await page.waitForURL(/\/login\?signup=1$/, { timeout: 10_000 });
			await expect(
				page.getByRole('heading', { name: 'Create an account' }),
			).toBeVisible({ timeout: 10_000 });
			await expect(
				page.getByLabel(/I confirm I am 16 years of age or older/),
			).toBeVisible();
			await expect(page.getByLabel(/I have read and agree to the/)).toBeVisible();
		} finally {
			await ctx.close();
		}
	});

	test('signed-in visitor does NOT see the signup CTA on the same public run', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			await expect(page.getByText('A run on Threkir')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.signup-cta')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
