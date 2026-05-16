import { existsSync, readFileSync } from 'node:fs';

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
 * across surfaces — the tier badges, the upgrade CTAs, the per-feature
 * gate when actually wired.
 *
 *   1. /coach as free user — tier badge reads "Free", "5 messages
 *      remaining" copy, no "Unlimited" string.
 *   2. /coach as Pro user — tier badge reads "Pro", "Unlimited
 *      messages" copy, no remaining-count copy.
 *   3. Free user with usage planted at the daily cap → composer is
 *      replaced by the limit-bar banner.
 *   4. Pro user with the same usage row keeps the composer enabled —
 *      symmetry test that the cap is per-tier, not per-user.
 *   5. /settings/upgrade as free user — "Get Pro" CTA visible, page
 *      surfaces the AI Coach unlimited bullet.
 *   6. /settings/upgrade as Pro user — "Active" badge visible, "Manage
 *      subscription" CTA visible, "Get Pro" CTA absent.
 *
 * Tests for a true `<ProGate>` lock-card on a feature page are
 * test.skip-with-TODO today: `lib/features.ts::isLocked()` is
 * hard-coded to return `false` for every key, so no screen renders the
 * ProGate. When a future feature flips that, replace the skip with the
 * lock-card assertion + the `<a href="/settings/upgrade">Upgrade</a>`
 * CTA check.
 */

const TODAY = new Date().toISOString().slice(0, 10);

function bypassPaywallActive(): boolean {
	for (const path of ['.env', '.env.local']) {
		if (!existsSync(path)) continue;
		const txt = readFileSync(path, 'utf-8');
		if (/^BYPASS_PAYWALL\s*=\s*['"]?true['"]?\s*$/m.test(txt)) {
			return true;
		}
	}
	return false;
}

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
			await expect(usageBar).toContainText(/of 5 messages remaining/);
			await expect(usageBar).not.toContainText(/Unlimited/i);
		});

		test('hitting the 5-msg daily cap replaces composer with limit-bar', async ({
			page,
		}) => {
			test.skip(
				bypassPaywallActive(),
				'BYPASS_PAYWALL=true in apps/web/.env.local; the cap is intentionally off in this environment',
			);

			const admin = getAdminClient();
			await admin.from('user_coach_usage').upsert(
				{ user_id: USER_A.id, usage_date: TODAY, message_count: 5 },
				{ onConflict: 'user_id,usage_date' },
			);

			await page.goto('/coach');
			await expect(page.locator('.limit-bar')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.limit-bar')).toContainText(/used all 5 messages/i);
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

		test('/coach shows Pro badge + Unlimited copy', async ({ page }) => {
			await page.goto('/coach');
			const usageBar = page.locator('.usage-bar');
			await expect(usageBar).toBeVisible({ timeout: 10_000 });

			await expect(usageBar.locator('.tier-badge.tier-pro')).toBeVisible();
			await expect(usageBar.locator('.tier-badge.tier-free')).toHaveCount(0);
			await expect(usageBar).toContainText(/Unlimited messages/i);
			await expect(usageBar).not.toContainText(/of 5 messages remaining/);
		});

		test('5 messages already used does NOT lock the composer for Pro', async ({
			page,
		}) => {
			const admin = getAdminClient();
			await admin.from('user_coach_usage').upsert(
				{ user_id: USER_C_PRO.id, usage_date: TODAY, message_count: 5 },
				{ onConflict: 'user_id,usage_date' },
			);

			await page.goto('/coach');
			await expect(page.getByPlaceholder(/Ask about today/))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.limit-bar')).toHaveCount(0);
			await expect(page.locator('.usage-bar')).toContainText(/Unlimited/i);
		});
	});

	test.describe('/settings/upgrade — tier-aware CTA surface', () => {
		test('free user sees Get-Pro CTA + AI Coach unlimited bullet', async ({
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
				await expect(proCard).toContainText(/Unlimited AI Coach/i);
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

	test.describe('ProGate per-feature lock-cards', () => {
		test.skip(
			true,
			'TODO: lib/features.ts::isLocked() is hard-coded to return false for every feature today (see docs/paywall.md — Pro is a perks-only tier, no gated screens). When a future feature flips isLocked() to !isPro(), replace this skip with: free user navigates to the gated feature → asserts <ProGate> renders (.pro-gate locator) → asserts the <a href="/settings/upgrade"> CTA is present → negative path with BYPASS_PAYWALL or USER_C_PRO storageState verifies the feature is reachable.',
		);

		test('placeholder — ProGate not wired to any feature today', () => {
			// Intentional no-op; the describe-level skip above is the
			// signal. Keep the test() call so the file always reports a
			// known-skipped row in the test summary.
		});
	});
});
