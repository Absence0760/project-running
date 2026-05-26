import { expect, test } from '@playwright/test';

import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * /settings/upgrade — two-tier Free vs Pro comparison + one-off donate
 * card.
 *
 * paywall-feature-gates.spec.ts covers the Free / Pro CTA matrix
 * (Get Pro vs Manage subscription, Active badge). This file pins the
 * polished structure: tier-grid layout, per-tier feature-list shape,
 * "Most popular" flag, donate-link URL, and the responsive stack at
 * narrow widths.
 */

test.describe('/settings/upgrade — free user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test('Pro pricing card renders for a free user', async ({ page }) => {
		// USER_A is on the free tier. The page renders the Pro card
		// with the monthly price. A regression would either crash
		// the page (PRO_PRICE_MONTHLY import broken) or the active
		// state would flip incorrectly (lock_subscription_columns
		// trigger + RPC drift).
		await page.goto('/settings/upgrade');

		// `exact: true` because case-insensitive substring matching
		// otherwise pulls in "Support the project" (contains "pro").
		await expect(
			page.getByRole('heading', { name: 'Pro', exact: true })
		).toBeVisible();
		// Monthly price is rendered as $N / month — assert the
		// "/ month" half is present (PRO_PRICE_MONTHLY is a number
		// constant, so the literal is robust to price changes).
		await expect(page.getByText('/ month')).toBeVisible();
	});

	test('two-tier grid: Free tier shows $0 forever + 4 features; Pro tier shows the price + 4 features + "Most popular" flag', async ({
		page,
	}) => {
		// Pin the polished two-card structure. Each tier carries a
		// `check_circle` icon per feature — count must be 4 on both
		// (Recording, Routes/plans/clubs, Strava/parkrun/Garmin, AI
		// Coach for Free; AI Coach 10/day, Priority map-matching,
		// Priority exports, Everything in Free for Pro). The Pro
		// daily Coach cap was lowered from Unlimited to 10/day in
		// May 2026 to bound worst-case Anthropic spend per the
		// cost-controls hardening pass — see TIER_LIMITS.pro.dailyLimit
		// in src/lib/coach/types.ts.
		await page.goto('/settings/upgrade');

		const freeCard = page.locator('.tier-free');
		await expect(freeCard).toBeVisible({ timeout: 10_000 });
		await expect(freeCard.locator('.price-amount')).toHaveText('$0');
		await expect(freeCard.locator('.price-period')).toHaveText('forever');
		await expect(freeCard.locator('.tier-features > li')).toHaveCount(4);
		await expect(freeCard.locator('.tier-features .check')).toHaveCount(4);

		const proCard = page.locator('.tier-pro');
		await expect(proCard).toBeVisible();
		await expect(proCard.locator('.tier-flag')).toHaveText(/Most popular/i);
		await expect(proCard.locator('.price-amount')).toContainText(/9\.99|9,99/);
		await expect(proCard.locator('.price-period')).toHaveText('/ month');
		await expect(proCard.locator('.tier-features > li')).toHaveCount(4);
		await expect(proCard.locator('.tier-features .check')).toHaveCount(4);
		await expect(proCard).toContainText(/AI Coach\s+—\s+10\/day/i);

		// Free tier carries the "You're on Free." note and NO active
		// flag; Pro tier carries the CTA + cancel-anytime fine print.
		await expect(freeCard.locator('.tier-note')).toContainText(/You're on Free/i);
		await expect(proCard.getByRole('button', { name: /Get Pro — /i }))
			.toBeVisible();
		await expect(proCard.locator('.tier-fine')).toContainText(/Cancel anytime/i);
	});

	test('donate card renders heart icon + button + the configured GitHub Sponsors link target', async ({
		page,
	}) => {
		// The bottom card is the "not ready for Pro? chip in" path.
		// DONATE_URL is set to GitHub Sponsors in
		// src/routes/settings/upgrade/+page.svelte — assert the click
		// opens that URL in a new tab.
		await page.goto('/settings/upgrade');

		const donateCard = page.locator('.donate-card');
		await expect(donateCard).toBeVisible({ timeout: 10_000 });
		await expect(donateCard.getByRole('heading', { name: /Not ready for a subscription/i }))
			.toBeVisible();

		const donateBtn = donateCard.getByRole('button', { name: /Donate/i });
		await expect(donateBtn).toBeVisible();
		// Heart icon ligature.
		await expect(donateBtn.locator('.material-symbols')).toHaveText('favorite');

		// Click opens DONATE_URL in a new tab. The page uses
		// window.open(url, '_blank', 'noopener,noreferrer'), so we
		// intercept the call instead of waiting for `popup` — the
		// noopener flag makes the popup unreliable on the Playwright
		// side. Stubbing window.open guarantees the URL was passed.
		const donateUrl = await page.evaluate(() => {
			const calls: string[] = [];
			(window as unknown as { __donateUrls: string[] }).__donateUrls = calls;
			window.open = ((url?: string | URL) => {
				calls.push(String(url ?? ''));
				return null;
			}) as typeof window.open;
			return null;
		});
		void donateUrl;
		await donateBtn.click();
		const urls = await page.evaluate(
			() => (window as unknown as { __donateUrls: string[] }).__donateUrls,
		);
		expect(urls.length).toBe(1);
		expect(urls[0]).toMatch(/^https:\/\/github\.com\/sponsors/);
	});

	test('tier grid stacks (single column) at narrow widths', async ({ page }) => {
		// `.tier-grid` uses `grid-template-columns: repeat(auto-fit,
		// minmax(20rem, 1fr))`. At a viewport narrower than two
		// 20-rem columns can fit, the two tiers should occupy one
		// column. Detect by comparing the bounding boxes — tier-pro
		// must sit BELOW tier-free, not beside it.
		await page.setViewportSize({ width: 480, height: 1000 });
		await page.goto('/settings/upgrade');
		// Needed: boundingBox() returns null immediately if the element
		// isn't laid out yet — no auto-retry like expect() has.
		await page.waitForLoadState('networkidle');

		const freeBox = await page.locator('.tier-free').boundingBox();
		const proBox = await page.locator('.tier-pro').boundingBox();
		expect(freeBox).not.toBeNull();
		expect(proBox).not.toBeNull();
		// Pro card's top edge sits at or below the Free card's bottom
		// edge when stacked. A small overlap margin (-2px) absorbs
		// sub-pixel rounding.
		expect(proBox!.y).toBeGreaterThanOrEqual(freeBox!.y + freeBox!.height - 2);
	});
});

test.describe('/settings/upgrade — Pro user', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test('Pro tier card flips to active state: "Active" badge + Manage subscription CTA + no Get Pro button', async ({
		page,
	}) => {
		// USER_C_PRO is seeded with subscription_tier='pro'. The page
		// should swap CTAs accordingly — the polished page replaces
		// the "Get Pro" button with "Manage subscription" and adds
		// the "Active" badge.
		await page.goto('/settings/upgrade');

		const proCard = page.locator('.tier-pro');
		await expect(proCard).toBeVisible({ timeout: 10_000 });
		await expect(proCard).toHaveClass(/active/);
		await expect(proCard.locator('.pro-badge', { hasText: 'Active' }))
			.toBeVisible();
		await expect(proCard.getByRole('button', { name: /Manage subscription/i }))
			.toBeVisible();
		await expect(proCard.getByRole('button', { name: /Get Pro/ }))
			.toHaveCount(0);

		// "You're on Free." note disappears on the Free card.
		await expect(page.locator('.tier-free .tier-note')).toHaveCount(0);

		// Pro user still sees the pro-note explaining where to manage
		// the subscription.
		await expect(proCard.locator('.pro-note')).toContainText(
			/App Store, Play Store, or the web billing portal/i,
		);
	});
});

test.describe('/settings/upgrade — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor is auth-walled to /login', async ({ page, context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
		// /settings/upgrade is NOT in the anon-allowed list — anon
		// users must be redirected to /login with a return_to.
		await page.goto('/settings/upgrade');
		await page.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
	});
});
