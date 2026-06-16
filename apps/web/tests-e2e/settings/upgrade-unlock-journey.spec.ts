import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Upgrade-unlock journey — one free user walks the whole "I hit a
 * paywalled behaviour → I upgrade → it unlocks → my account shows Pro"
 * loop across the two surfaces that actually move when the tier flips:
 * the AI Coach daily-cap gate and the /settings/upgrade plan card.
 *
 * The paywall here is a BUDGET model, not a screen-gate
 * (`PRO_ONLY_FEATURES` is empty; `isLocked()` is always false — see
 * docs/features/paywall.md + cross-cutting/paywall-feature-gates.spec.ts).
 * So the "paywalled feature" a free user runs into is the AI Coach's
 * 2-message/day cap: at the cap, CoachChat replaces the composer with a
 * `.limit-bar` "Upgrade to Pro" banner. The Pro perk is the SAME surface
 * with a 10/day ceiling — at 2 used, a Pro user's composer stays live.
 *
 *   1. FREE USER_A on /coach, planted at the free cap (message_count=2):
 *      tier badge reads "Free", the composer is gone, the `.limit-bar`
 *      shows "used all 2 messages" + "Upgrade to Pro". This is the gate.
 *   2. "Upgrade." There is no exercisable Stripe/RevenueCat checkout in
 *      e2e — a real purchase needs store credentials we don't have. The
 *      established test path (tier-cache-resilience.spec.ts) is a
 *      SERVICE-ROLE write to user_profiles.subscription_tier, which is
 *      exactly what the revenuecat-webhook does in production (and the
 *      ONLY writer the lock_subscription_columns trigger allows besides
 *      direct SQL). So the upgrade is modelled as that backend transition
 *      free → pro.
 *   3. Re-fetch so the new tier takes effect. CoachChat resolves tier on
 *      mount via the live `is_pro` RPC (CoachChat.svelte onMount), so a
 *      fresh navigation to /coach reflects pro immediately — no
 *      re-sign-in. /settings/upgrade instead reads `auth.isPro` from the
 *      module-singleton auth store, which only re-runs `get_my_profile`
 *      on the store's initial `getSession()` at full page load; a
 *      `page.reload()` (full document nav, not SPA pushState) re-inits
 *      the store and pulls the new tier. Both are exercised below.
 *   4. The previously-gated /coach is now usable: tier badge reads "Pro",
 *      the same usage row (2 used) is under the Pro 10/day cap so the
 *      composer is back and the bar reads "of 10 messages remaining".
 *   5. /settings/upgrade shows the Pro card in its `active` state:
 *      "Active" badge + "Manage subscription", no "Get Pro".
 *   6. Backend cross-check: user_profiles.subscription_tier === 'pro'.
 *   7. finally: RESET USER_A to 'free' (service-role) AND delete the
 *      planted usage row. USER_A is the shared free subject for the whole
 *      suite — a leaked Pro tier or a leftover cap row would poison every
 *      later spec that assumes runner@test.com is a fresh free user.
 */

// Coach usage is keyed by UTC day; CoachChat's get_coach_usage RPC reads
// the same bucket. Match the column the handler writes.
const TODAY = new Date().toISOString().slice(0, 10);

test.describe('upgrade-unlock journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		// Pre-accept consent so the GDPR banner can't float over the
		// composer / usage bar (mirrors the paywall specs).
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test('free user hits the coach cap → upgrade flips tier → coach unlocks + settings shows Pro', async ({
		page,
	}) => {
		const admin = getAdminClient();

		try {
			// ── 1. Free user at the AI Coach daily cap sees the gate ────
			await test.step('free USER_A at the coach cap sees the limit-bar gate', async () => {
				// Plant the free cap (2/2 used today) via service-role so the
				// composer is replaced by the upgrade banner on first paint.
				await admin.from('user_coach_usage').upsert(
					{ user_id: USER_A.id, usage_date: TODAY, message_count: 2 },
					{ onConflict: 'user_id,usage_date' },
				);

				await page.goto('/coach');
				const usageBar = page.locator('.usage-bar');
				await expect(usageBar).toBeVisible({ timeout: 10_000 });

				// Free tier badge, no Pro badge.
				await expect(usageBar.locator('.tier-badge.tier-free')).toBeVisible();
				await expect(usageBar.locator('.tier-badge.tier-pro')).toHaveCount(0);

				// At the cap, the composer is gone and the limit-bar carries
				// the "Upgrade to Pro" CTA — this is the paywall surface.
				const limitBar = page.locator('.limit-bar');
				await expect(limitBar).toBeVisible({ timeout: 10_000 });
				await expect(limitBar).toContainText(/used all 2 messages/i);
				await expect(limitBar).toContainText(/Upgrade to Pro/i);
				await expect(page.locator('form.composer')).toHaveCount(0);
			});

			// ── 2. Upgrade: service-role tier flip (= the webhook path) ──
			await test.step('upgrade flips the tier free → pro (the RevenueCat-webhook path)', async () => {
				// This is the upgrade. A real purchase isn't exercisable in
				// e2e (no Stripe/RevenueCat store credentials), so we model
				// it as the backend transition the webhook performs — a
				// service-role write, the only non-SQL writer the
				// lock_subscription_columns trigger permits.
				const { error } = await admin
					.from('user_profiles')
					.update({ subscription_tier: 'pro' })
					.eq('id', USER_A.id);
				expect(error).toBeNull();
			});

			// ── 3+4. The previously-gated /coach is now usable ──────────
			await test.step('after the flip /coach unlocks: Pro badge + composer back + 10/day cap', async () => {
				// Fresh navigation: CoachChat re-resolves tier on mount via
				// the live `is_pro` RPC, so the pro tier is seen without any
				// re-sign-in (the same property tier-cache-resilience pins
				// at the API layer). The SAME usage row (2 used) is now well
				// under the Pro 10/day cap, so the gate lifts.
				await page.goto('/coach');
				const usageBar = page.locator('.usage-bar');
				await expect(usageBar).toBeVisible({ timeout: 10_000 });

				await expect(usageBar.locator('.tier-badge.tier-pro')).toBeVisible();
				await expect(usageBar.locator('.tier-badge.tier-free')).toHaveCount(0);
				await expect(usageBar).toContainText(/of 10 messages remaining/);
				await expect(usageBar).toContainText(/priority context window/i);

				// The feature that was gated is usable again: composer back,
				// limit-bar gone.
				await expect(page.locator('form.composer')).toBeVisible({
					timeout: 10_000,
				});
				await expect(page.locator('.limit-bar')).toHaveCount(0);
			});

			// ── 5. /settings shows the Pro plan as Active ───────────────
			await test.step('/settings/upgrade reflects Pro: Active badge + Manage subscription', async () => {
				await page.goto('/settings/upgrade');
				// /settings/upgrade reads `auth.isPro` off the module-singleton
				// auth store, which hydrates the tier on the store's initial
				// `getSession()`→get_my_profile. A plain client-side nav reuses
				// the already-initialised store (still 'free' from sign-in), so
				// force a full document reload to re-init it against the flipped
				// DB row. This is the UI-side tier-cache invalidation.
				await page.reload();

				const proCard = page.locator('.tier-pro');
				await expect(proCard).toBeVisible({ timeout: 10_000 });
				await expect(proCard).toHaveClass(/active/);
				await expect(proCard.locator('.pro-badge', { hasText: 'Active' }))
					.toBeVisible();
				await expect(
					proCard.getByRole('button', { name: /Manage subscription/i }),
				).toBeVisible();
				await expect(proCard.getByRole('button', { name: /Get Pro/ }))
					.toHaveCount(0);

				// The Free card's "You're on Free." note disappears once Pro.
				await expect(page.locator('.tier-free .tier-note')).toHaveCount(0);
			});

			// ── 6. Backend cross-check of the authoritative column ──────
			await test.step('backend confirms subscription_tier is pro', async () => {
				const { data: row } = await admin
					.from('user_profiles')
					.select('subscription_tier')
					.eq('id', USER_A.id)
					.single();
				expect(row?.subscription_tier).toBe('pro');
			});
		} finally {
			// ── 7. RESTORE: USER_A must go back to free, usage row gone ──
			// USER_A is the shared free subject across the suite. Reset
			// unconditionally so a failure mid-journey can't leave Pro (or
			// the planted cap row) leaking into every later spec.
			await admin
				.from('user_profiles')
				.update({ subscription_tier: 'free' })
				.eq('id', USER_A.id);
			await admin
				.from('user_coach_usage')
				.delete()
				.eq('user_id', USER_A.id)
				.eq('usage_date', TODAY);
		}
	});
});
