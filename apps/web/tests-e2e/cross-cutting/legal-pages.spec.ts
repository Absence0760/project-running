import { expect, test } from '@playwright/test';

/**
 * Production-readiness guard for the public legal pages.
 *
 * The pages are complete legal text (rewritten 2026-07-14); the only
 * permitted "unfinished" surface is the operator-facts pending banner
 * driven by src/lib/legal/operator.ts — never a TODO placeholder or a
 * "Draft" banner. If a fact is filled in operator.ts, the pending
 * copy for it must disappear without any other edit.
 */

const PAGES = [
	{ path: '/privacy', title: 'Privacy Policy' },
	{ path: '/terms', title: 'Terms of Service' },
	{ path: '/cookie-notice', title: 'Cookie Notice' },
	{ path: '/health-data-notice', title: 'Consumer Health Data Privacy Policy' },
];

test.describe('Legal pages', () => {
	// Anonymous — legal pages must never require auth.
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const { path, title } of PAGES) {
		test(`${path} renders anonymously with no draft markers`, async ({ page }) => {
			await page.goto(path);
			await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible();
			await expect(page.getByText(/^Last updated: \d{4}-\d{2}-\d{2}$/)).toBeVisible();

			const body = await page.locator('.legal-page').innerText();
			expect(body).not.toMatch(/TODO/);
			expect(body).not.toMatch(/\bDraft\b\./);
			expect(body).not.toMatch(/published as a placeholder/i);
			expect(body).not.toMatch(/to be confirmed|not yet operative|working scaffold/i);
		});
	}

	test('privacy policy states the 48-hour live-ping retention, not the stale 24h figure', async ({
		page
	}) => {
		await page.goto('/privacy');
		const body = await page.locator('.legal-page').innerText();
		expect(body).toContain('Live spectator pings');
		expect(body).toMatch(/Live spectator pings[^\n]*48 hours/);
	});

	test('terms cover the paid-events marketplace and DMCA contact', async ({ page }) => {
		await page.goto('/terms');
		const body = await page.locator('.legal-page').innerText();
		expect(body).toContain('merchant of record');
		expect(body).toContain('dmca@threkir.com');
	});

	test('cookie notice discloses GPC as honoured', async ({ page }) => {
		await page.goto('/cookie-notice');
		await expect(page.getByText('Global Privacy Control (GPC) is honoured.')).toBeVisible();
		await expect(page.getByTestId('manage-cookie-preferences')).toBeVisible();
	});

	test('health-data notice is linked from the privacy policy', async ({ page }) => {
		await page.goto('/privacy');
		await page.getByRole('link', { name: 'Consumer Health Data Privacy Policy' }).click();
		await expect(
			page.getByRole('heading', { level: 1, name: 'Consumer Health Data Privacy Policy' })
		).toBeVisible();
	});
});
