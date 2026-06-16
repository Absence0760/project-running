import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Paywall — full tier LIFECYCLE on one user: gated → upgrade →
 * unlocked → DOWNGRADE → re-locked.
 *
 * What's already covered (and what this deliberately does NOT repeat):
 *   - paywall-feature-gates.spec.ts pins the static free-vs-pro UI
 *     differences (two different seeded users, no transition).
 *   - paywall-wire.spec.ts pins the API 429 gate per static tier.
 *   - tier-cache-resilience.spec.ts pins the API handler reads the tier
 *     fresh on every request (free → pro flip mid-session at the wire).
 *   - upgrade-unlock-journey.spec.ts walks free → pro ONCE, one
 *     direction, and stops at Pro.
 *
 * The uncovered arc is the FULL round-trip on a SINGLE user across the
 * real gated SURFACES: free user blocked → upgraded → the same surfaces
 * unlock → DOWNGRADED → the same surfaces RE-LOCK. The downgrade leg is
 * the genuinely new coverage — no existing spec asserts that pulling a
 * user's Pro tier (a lapsed subscription / RevenueCat expiry webhook)
 * actually re-arms the gate on the next page load. A regression where a
 * once-Pro user keeps the lifted cap (a stale client-side tier, or a
 * gate that only ever upgrades and never downgrades) would leak Pro to
 * a non-paying account — this catches it.
 *
 * The paywall is a BUDGET model, not a screen-gate (`PRO_ONLY_FEATURES`
 * is empty; `isLocked()` is always false — features.ts + paywall.md).
 * The "gated surface" a free user runs into is therefore the AI Coach
 * 2-msg/day cap (CoachChat.svelte): planted at the cap, the composer is
 * replaced by the `.limit-bar` "Upgrade to Pro" banner; the Pro perk is
 * the SAME surface with a 10/day ceiling, so at 2 used the composer
 * stays live. The second gated surface is the /settings/upgrade plan
 * card, which swaps Get-Pro ↔ Active by tier.
 *
 * Two distinct tier-read paths are exercised across the flips (both
 * must track the DB without a re-sign-in):
 *   - /coach resolves tier on mount via the live `is_pro` RPC
 *     (CoachChat.svelte onMount, lines 295-306) — a fresh navigation
 *     reflects the flipped tier with no reload trick.
 *   - /settings/upgrade reads `auth.isPro` off the module-singleton
 *     auth store, hydrated by `get_my_profile` on the store's initial
 *     `getSession()`. A plain SPA nav reuses the stale store, so a full
 *     `page.reload()` re-inits it against the flipped row.
 *
 * Subject: an EPHEMERAL saga user, not a seeded one — we flip its tier
 * twice and delete it at the end, so there is no seeded-tier snapshot to
 * restore and no risk of leaking a flipped tier into a later spec (the
 * way mutating USER_A / USER_C_PRO would). Cleanup is unconditional in
 * finally: delete the planted usage row, then deleteSagaUsers.
 */

const TODAY = new Date().toISOString().slice(0, 10);

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

test.describe('paywall — tier lifecycle (gated → upgrade → unlocked → downgrade → re-locked)', () => {
	test('one user walks the full tier round-trip across the real gated surfaces', async ({
		browser,
	}) => {
		const admin = getAdminClient();
		let users: SagaUser[] = [];

		try {
			users = await createSagaUsers(1, { displayNames: ['Tier Lifecycle'] });
			const subject = users[0];

			// Plant the free cap (2/2 used today) ONCE. The same usage row
			// rides through the whole journey: it gates a free user, lifts
			// for a Pro user (2 < 10), then re-gates after the downgrade —
			// so the only variable across the arc is subscription_tier.
			await admin.from('user_coach_usage').upsert(
				{ user_id: subject.id, usage_date: TODAY, message_count: 2 },
				{ onConflict: 'user_id,usage_date' },
			);

			// /coach render-gates the chat (usage-bar / limit-bar / composer)
			// behind a first-use AI-coach consent disclosure stamped on
			// user_profiles.coach_consent_at. A fresh saga user hasn't
			// consented, so the chat surface — the gated surface this spec
			// asserts on — never renders until it's stamped. Direct writes to
			// the column are DB-blocked; stamp it through the canonical
			// record_coach_consent RPC under the subject's own JWT. The
			// consent modal itself is out of scope here (the coach specs own
			// it); this spec is about the paywall, not the disclosure.
			const subjectClient = await getUserClient({
				email: subject.email,
				password: subject.password,
			});
			const { error: consentErr } = await subjectClient.rpc('record_coach_consent');
			if (consentErr) {
				throw new Error(`paywall lifecycle: record_coach_consent failed: ${consentErr.message}`);
			}

			const ctx = await browser.newContext({
				storageState: subject.storageStatePath,
			});
			// Saga users have not accepted the cookie banner — pre-accept so
			// the GDPR banner can't float over the composer / usage bar.
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();

			try {
				// ── 1. FREE: the gate is armed on both surfaces ─────────────
				await test.step('FREE user is blocked: coach limit-bar + Get-Pro CTA', async () => {
					await page.goto('/coach');
					const usageBar = page.locator('.usage-bar');
					await expect(usageBar).toBeVisible({ timeout: 10_000 });
					await expect(usageBar.locator('.tier-badge.tier-free')).toBeVisible();
					await expect(usageBar.locator('.tier-badge.tier-pro')).toHaveCount(0);

					// At the free cap the composer is gone, replaced by the
					// "Upgrade to Pro" limit-bar — this is the paywall surface.
					const limitBar = page.locator('.limit-bar');
					await expect(limitBar).toBeVisible({ timeout: 10_000 });
					await expect(limitBar).toContainText(/used all 2 messages/i);
					await expect(limitBar).toContainText(/Upgrade to Pro/i);
					await expect(page.locator('form.composer')).toHaveCount(0);

					// The upgrade page shows the Free state: Get-Pro CTA, no
					// Active badge.
					await page.goto('/settings/upgrade');
					const proCard = page.locator('.tier-pro');
					await expect(proCard).toBeVisible({ timeout: 10_000 });
					await expect(proCard.getByRole('button', { name: /Get Pro/ }))
						.toBeVisible();
					await expect(proCard.locator('.pro-badge', { hasText: 'Active' }))
						.toHaveCount(0);
					await expect(page.locator('.tier-free .tier-note')).toBeVisible();
				});

				// ── 2. UPGRADE free → pro (the RevenueCat-webhook path) ─────
				await test.step('upgrade flips tier free → pro (service-role = the webhook writer)', async () => {
					// A real purchase isn't exercisable in e2e; model it as the
					// backend transition the webhook performs — a service-role
					// write, the only non-SQL writer lock_subscription_columns
					// permits.
					const { error } = await admin
						.from('user_profiles')
						.update({ subscription_tier: 'pro' })
						.eq('id', subject.id);
					expect(error).toBeNull();
				});

				// ── 3. PRO: the same surfaces UNLOCK ────────────────────────
				await test.step('PRO unlocks coach (fresh `is_pro` read) + upgrade shows Active', async () => {
					// Fresh navigation: CoachChat re-resolves tier on mount via
					// the live `is_pro` RPC, so pro is seen with NO re-sign-in.
					// The SAME usage row (2 used) is under the Pro 10/day cap.
					await page.goto('/coach');
					const usageBar = page.locator('.usage-bar');
					await expect(usageBar).toBeVisible({ timeout: 10_000 });
					await expect(usageBar.locator('.tier-badge.tier-pro')).toBeVisible();
					await expect(usageBar.locator('.tier-badge.tier-free')).toHaveCount(0);
					await expect(usageBar).toContainText(/of 10 messages remaining/);
					await expect(usageBar).toContainText(/priority context window/i);

					// The gate has lifted: composer back, limit-bar gone.
					await expect(page.locator('form.composer'))
						.toBeVisible({ timeout: 10_000 });
					await expect(page.locator('.limit-bar')).toHaveCount(0);

					// /settings/upgrade reads auth.isPro off the singleton
					// store — a full reload re-inits it against the flipped row.
					await page.goto('/settings/upgrade');
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
					await expect(page.locator('.tier-free .tier-note')).toHaveCount(0);
				});

				// ── 4. DOWNGRADE pro → free (lapsed-sub / expiry webhook) ───
				await test.step('downgrade flips tier pro → free (the expiry-webhook path)', async () => {
					const { error } = await admin
						.from('user_profiles')
						.update({ subscription_tier: 'free' })
						.eq('id', subject.id);
					expect(error).toBeNull();
				});

				// ── 5. RE-LOCKED: the gate re-arms on both surfaces ─────────
				// This is the novel leg. A once-Pro user whose subscription
				// lapsed must lose the lifted cap on the next page load — the
				// gate is dynamic in BOTH directions, not a one-way upgrade.
				await test.step('RE-LOCKED: coach limit-bar returns + Get-Pro CTA returns', async () => {
					await page.goto('/coach');
					const usageBar = page.locator('.usage-bar');
					await expect(usageBar).toBeVisible({ timeout: 10_000 });
					// Back to the free badge — the fresh `is_pro` read saw the
					// downgrade with no re-sign-in.
					await expect(usageBar.locator('.tier-badge.tier-free')).toBeVisible();
					await expect(usageBar.locator('.tier-badge.tier-pro')).toHaveCount(0);

					// The SAME usage row (2 used) is once again at/over the free
					// cap, so the composer is gone and the limit-bar is back. A
					// regression that kept the Pro 10/day cap for a downgraded
					// user would leave the composer live and FAIL here.
					const limitBar = page.locator('.limit-bar');
					await expect(limitBar).toBeVisible({ timeout: 10_000 });
					await expect(limitBar).toContainText(/used all 2 messages/i);
					await expect(limitBar).toContainText(/Upgrade to Pro/i);
					await expect(page.locator('form.composer')).toHaveCount(0);
					await expect(usageBar).not.toContainText(/priority context window/i);

					// /settings/upgrade swings back to the Free state.
					await page.goto('/settings/upgrade');
					await page.reload();
					const proCard = page.locator('.tier-pro');
					await expect(proCard).toBeVisible({ timeout: 10_000 });
					await expect(proCard).not.toHaveClass(/active/);
					await expect(proCard.getByRole('button', { name: /Get Pro/ }))
						.toBeVisible();
					await expect(proCard.locator('.pro-badge', { hasText: 'Active' }))
						.toHaveCount(0);
					await expect(page.locator('.tier-free .tier-note')).toBeVisible();
				});

				// ── 6. Backend cross-check of the authoritative column ──────
				await test.step('backend confirms subscription_tier landed back at free', async () => {
					const { data: row } = await admin
						.from('user_profiles')
						.select('subscription_tier')
						.eq('id', subject.id)
						.single();
					expect(row?.subscription_tier).toBe('free');
				});
			} finally {
				await ctx.close();
			}
		} finally {
			// Unconditional cleanup: delete the planted usage row, then the
			// ephemeral user (CASCADE strips its child rows). The saga user is
			// disposable, so a mid-journey failure can't leak a flipped tier
			// into any later spec.
			if (users.length > 0) {
				await admin
					.from('user_coach_usage')
					.delete()
					.eq('user_id', users[0].id)
					.eq('usage_date', TODAY);
				await deleteSagaUsers(users);
			}
		}
	});
});
