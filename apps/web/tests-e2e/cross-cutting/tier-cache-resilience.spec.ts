import { existsSync, readFileSync } from 'node:fs';

import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { USER_C_PRO } from '../fixtures/users';

/**
 * The /api/coach handler reads `subscription_tier` on every
 * request — never cached, never warmed at startup. This test pins
 * that property by flipping morgan's tier in the DB and watching
 * the very next /api/coach call observe the new state.
 *
 * Why this matters: a regression that cached the tier (e.g. an
 * accidental module-level memo of the user_profiles row, or a JWT
 * claim that's only minted at sign-in) would silently let a
 * downgraded user keep firing Pro-shape requests, OR keep an
 * upgraded user behind the free cap until they re-signed in.
 * Either is a paywall correctness bug.
 *
 * Companion to `cross-cutting/paywall-wire.spec.ts` which pins the
 * static states (free vs pro). That covers "the gate works at all";
 * this covers "the gate is dynamic across requests".
 *
 * The flip uses a service-role write — the lock_subscription_columns
 * trigger only blocks user-self-upgrades; service-role can still
 * modify the column (RevenueCat's webhook does this in production).
 */

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

const TODAY = new Date().toISOString().slice(0, 10);

async function freshAccessToken(email: string, password: string): Promise<string> {
	const client = await getUserClient({ email, password });
	const { data } = await client.auth.getSession();
	return data.session?.access_token ?? '';
}

async function postCoach(token: string, prompt: string) {
	return await fetch('http://localhost:7777/api/coach', {
		method: 'POST',
		headers: {
			'content-type': 'application/json',
			'x-supabase-authorization': `Bearer ${token}`
		},
		body: JSON.stringify({
			messages: [{ role: 'user', content: prompt }],
			plan_id: null,
			recent_runs_limit: 10
		})
	});
}

test.describe('paywall — tier check is dynamic, not cached', () => {
	test.skip(
		bypassPaywallActive,
		'BYPASS_PAYWALL=true; the cap is intentionally off in this environment'
	);

	test('flipping morgan free → pro mid-session lifts the daily cap on the next request', async ({}) => {
		// 1) Service-role flip morgan to free + plant message_count=5.
		//    Morgan starts seeded as pro; we flip them down so the free
		//    cap applies, then back up to pro and re-fire.
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ subscription_tier: 'free' })
			.eq('id', USER_C_PRO.id);
		await admin
			.from('user_coach_usage')
			.upsert(
				{ user_id: USER_C_PRO.id, usage_date: TODAY, message_count: 5 },
				{ onConflict: 'user_id,usage_date' }
			);

		try {
			const token = await freshAccessToken(
				USER_C_PRO.email,
				USER_C_PRO.password
			);
			expect(token.length).toBeGreaterThan(20);

			// 2) First request: morgan is free, used 5/5 today → 429
			//    `tier: 'free'`. If the handler had cached the tier at
			//    sign-in (when morgan was pro), this would NOT 429.
			const r1 = await postCoach(token, 'first poke — should hit free cap');
			expect(r1.status, 'morgan-as-free with 5/5 used must hit the cap')
				.toBe(429);
			const b1 = await r1.json();
			expect(b1.tier).toBe('free');
			expect(b1.error).toBe('daily_limit');

			// 3) Service-role flips morgan back to pro. SAME JWT — no
			//    re-sign-in, so a regression that read the tier from a
			//    JWT claim or a startup-time cache would NOT see the
			//    change.
			await admin
				.from('user_profiles')
				.update({ subscription_tier: 'pro' })
				.eq('id', USER_C_PRO.id);

			// 4) Second request with the SAME token: tier is now pro,
			//    daily-cap branch must NOT fire. We tolerate any non-429
			//    OR a 429 whose payload is NOT `tier: 'free'` (the Pro
			//    per-hour rate limit lives at a different ceiling and
			//    surfaces differently — same tolerance the static-state
			//    paywall test uses).
			const r2 = await postCoach(token, 'second poke — should pass cap');
			if (r2.status === 429) {
				const b2 = await r2.json();
				expect(
					b2.tier,
					'after flipping back to pro, the same JWT must NOT see the free cap on the next request — ' +
						'this would mean the handler cached the tier'
				).not.toBe('free');
			} else {
				// Anything non-429 is fine — the only thing under test
				// is that the free cap didn't fire.
				expect(r2.status).not.toBe(429);
			}
		} finally {
			// Restore canonical state: morgan is pro, no usage row.
			await admin
				.from('user_profiles')
				.update({ subscription_tier: 'pro' })
				.eq('id', USER_C_PRO.id);
			await admin
				.from('user_coach_usage')
				.delete()
				.eq('user_id', USER_C_PRO.id)
				.eq('usage_date', TODAY);
		}
	});
});
