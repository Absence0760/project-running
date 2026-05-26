import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Paywall — per-feature UI gates and tier-aware behaviour.
 *
 * paywall-wire.spec.ts pins the API-level 429 gate on /api/coach.
 * coach.spec.ts pins the 429 → "Daily limit reached" banner with a
 * mocked route. This file pins the OTHER direction: the user-facing
 * "you're on Free vs Pro" UI differences a single human would see
 * across surfaces — the tier badges, the upgrade CTAs, the limit
 * banner when a free user runs out of messages.
 *
 *   1. /coach as free user — tier badge reads "Free", "N of 2 messages
 *      remaining" copy.
 *   2. /coach as Pro user — tier badge reads "Pro", "N of 10 messages
 *      remaining" copy, plus the priority context-window note.
 *   3. Free user with usage planted at the daily cap → composer is
 *      replaced by the limit-bar banner.
 *   4. Pro user with the same usage row keeps the composer enabled —
 *      symmetry test that the free cap doesn't apply to Pro (Pro has
 *      its own higher cap at TIER_LIMITS.pro.dailyLimit).
 *   5. /settings/upgrade as free user — "Get Pro" CTA visible, page
 *      surfaces the AI Coach higher-cap bullet.
 *   6. /settings/upgrade as Pro user — "Active" badge visible, "Manage
 *      subscription" CTA visible, "Get Pro" CTA absent.
 *
 * `PRO_ONLY_FEATURES` in `apps/web/src/lib/features.ts` is empty today
 * — `isLocked()` returns `false` for every key, so /coach is reachable
 * by every signed-in user regardless of tier. The Pro tier is
 * delivered through behaviour changes inside the surface (higher
 * daily cap, wider context budget). See [docs/paywall.md] for the
 * current model and [docs/decisions.md § 23] for the rationale.
 */

const TODAY = new Date().toISOString().slice(0, 10);

test.describe('paywall — per-feature gates', () => {
	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test.describe('AI Coach — free tier', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test.afterEach(async () => {
			const admin = getAdminClient();
			await admin
				.from('user_coach_usage')
				.delete()
				.eq('user_id', USER_A.id)
				.eq('usage_date', TODAY);
		});

		test('/coach shows Free badge + remaining-count copy', async ({ page }) => {
			const admin = getAdminClient();
			await admin
				.from('user_coach_usage')
				.delete()
				.eq('user_id', USER_A.id)
				.eq('usage_date', TODAY);

			await page.goto('/coach');
			const usageBar = page.locator('.usage-bar');
			await expect(usageBar).toBeVisible({ timeout: 10_000 });

			await expect(usageBar.locator('.tier-badge.tier-free')).toBeVisible();
			await expect(usageBar.locator('.tier-badge.tier-pro')).toHaveCount(0);
			await expect(usageBar).toContainText(/of 2 messages remaining/);
			await expect(usageBar).not.toContainText(/priority context window/i);
		});

		test('hitting the free daily cap replaces composer with limit-bar', async ({
			page,
		}) => {
			const admin = getAdminClient();
			await admin.from('user_coach_usage').upsert(
				{ user_id: USER_A.id, usage_date: TODAY, message_count: 2 },
				{ onConflict: 'user_id,usage_date' },
			);

			await page.goto('/coach');
			await expect(page.locator('.limit-bar')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.limit-bar')).toContainText(/used all 2 messages/i);
			await expect(page.locator('.limit-bar')).toContainText(/Upgrade to Pro/i);
			await expect(page.locator('form.composer')).toHaveCount(0);
		});
	});

	test.describe('AI Coach — Pro tier', () => {
		test.use({ storageState: USER_C_PRO.storageStatePath });

		test.afterEach(async () => {
			const admin = getAdminClient();
			await admin
				.from('user_coach_usage')
				.delete()
				.eq('user_id', USER_C_PRO.id)
				.eq('usage_date', TODAY);
		});

		test('/coach shows Pro badge + higher-cap remaining copy', async ({ page }) => {
			await page.goto('/coach');
			const usageBar = page.locator('.usage-bar');
			await expect(usageBar).toBeVisible({ timeout: 10_000 });

			await expect(usageBar.locator('.tier-badge.tier-pro')).toBeVisible();
			await expect(usageBar.locator('.tier-badge.tier-free')).toHaveCount(0);
			await expect(usageBar).toContainText(/of 10 messages remaining/);
			await expect(usageBar).toContainText(/priority context window/i);
		});

		test('usage at the free cap does NOT lock the composer for Pro', async ({
			page,
		}) => {
			// Planted at 2 (= free cap, but well under Pro's 10/day cap).
			// Pro must not see the limit-bar; the composer stays live and
			// the usage bar continues to show the Pro remaining count.
			const admin = getAdminClient();
			await admin.from('user_coach_usage').upsert(
				{ user_id: USER_C_PRO.id, usage_date: TODAY, message_count: 2 },
				{ onConflict: 'user_id,usage_date' },
			);

			await page.goto('/coach');
			await expect(page.getByPlaceholder(/Ask about today/))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.limit-bar')).toHaveCount(0);
			await expect(page.locator('.usage-bar')).toContainText(/of 10 messages remaining/);
		});
	});

	test.describe('/settings/upgrade — tier-aware CTA surface', () => {
		test('free user sees Get-Pro CTA + AI Coach higher-cap bullet', async ({
			browser,
		}) => {
			const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
			const page = await ctx.newPage();
			try {
				await ctx.addInitScript(() => {
					localStorage.setItem(
						'cookie_consent',
						JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
					);
				});
				await page.goto('/settings/upgrade');
				const proCard = page.locator('.tier-pro');
				await expect(proCard).toBeVisible({ timeout: 10_000 });
				await expect(proCard.getByRole('button', { name: /Get Pro/ }))
					.toBeVisible();
				await expect(proCard).toContainText(/10\s*\/\s*day.*AI Coach|AI Coach.*10\s*\/\s*day/i);
				await expect(proCard.locator('.pro-badge', { hasText: 'Active' }))
					.toHaveCount(0);
			} finally {
				await ctx.close();
			}
		});

		test('Pro user sees Active badge + Manage-subscription CTA', async ({
			browser,
		}) => {
			const ctx = await browser.newContext({
				storageState: USER_C_PRO.storageStatePath,
			});
			const page = await ctx.newPage();
			try {
				await ctx.addInitScript(() => {
					localStorage.setItem(
						'cookie_consent',
						JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
					);
				});
				await page.goto('/settings/upgrade');
				const proCard = page.locator('.tier-pro');
				await expect(proCard).toBeVisible({ timeout: 10_000 });
				await expect(proCard.locator('.pro-badge', { hasText: 'Active' }))
					.toBeVisible();
				await expect(proCard.getByRole('button', { name: /Manage subscription/ }))
					.toBeVisible();
				await expect(proCard.getByRole('button', { name: /Get Pro/ }))
					.toHaveCount(0);
			} finally {
				await ctx.close();
			}
		});
	});

	test.describe('Free user reaches /coach directly (no Pro screen-gate)', () => {
		test('free user lands on /coach -> sees the chat surface, not a <ProGate>', async ({
			browser,
		}) => {
			// The AI Coach used to be a hard Pro screen-gate (`isLocked`
			// returned true for free users). It was flipped back to a
			// budget model per decisions.md § 23: free users get the
			// chat UI plus a 2-msg/day cap. This test pins the surface
			// is reachable without Pro. The `paywall_force_locked`
			// localStorage override is still set so a future regression
			// that re-arms a screen gate would also be caught by the
			// usage-bar-visible assertion.
			const ctx = await browser.newContext({
				storageState: USER_A.storageStatePath,
			});
			const page = await ctx.newPage();
			try {
				await ctx.addInitScript(() => {
					localStorage.setItem(
						'cookie_consent',
						JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
					);
					localStorage.setItem('paywall_force_locked', '1');
				});
				await page.goto('/coach');

				await expect(page.locator('.pro-gate')).toHaveCount(0);
				await expect(page.locator('.usage-bar'))
					.toBeVisible({ timeout: 10_000 });
				await expect(page.locator('form.composer'))
					.toBeVisible({ timeout: 10_000 });
			} finally {
				await ctx.close();
			}
		});
	});
});
