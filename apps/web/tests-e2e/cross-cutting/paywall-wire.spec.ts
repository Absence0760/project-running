import { existsSync, readFileSync } from 'node:fs';

import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

// Locally, dev sessions often run with BYPASS_PAYWALL=true in
// apps/web/.env.local so the cap doesn't block ad-hoc coach prompts.
// The wire test can only meaningfully assert the 429 path when the
// bypass is OFF. CI writes apps/web/.env from supabase-status with
// no BYPASS_PAYWALL line, so it skips correctly there. Skip locally
// when bypass is on.
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

/**
 * Paywall enforcement at the API boundary, not the UI gate.
 *
 * The CoachChat UI shows a "Daily limit reached" banner once the
 * server returns 429. That flow is covered in coach.spec.ts. This
 * file pins the OTHER direction: a curl-from-devtools attack that
 * bypasses the UI must still be rejected at the wire by
 * `/api/coach` against the same `user_coach_usage.message_count`
 * counter the UI relies on. The handler reads the daily count via
 * the `increment_coach_usage` SECURITY DEFINER RPC; if that gate
 * ever softened (or BYPASS_PAYWALL leaked into a non-dev env), this
 * test would catch it.
 */

const TODAY = new Date().toISOString().slice(0, 10);

async function freshAccessToken(email: string, password: string): Promise<string> {
	// Mint a fresh JWT via getUserClient + supabase.auth.getSession.
	// This is the canonical way to read the access_token in tests
	// without coupling to the page's localStorage shape (which
	// supabase-js controls and has rewritten between minor versions).
	const client = await getUserClient({ email, password });
	const { data } = await client.auth.getSession();
	return data.session?.access_token ?? '';
}

test.describe('paywall — at the wire', () => {
	test.skip(bypassPaywallActive, 'BYPASS_PAYWALL=true in apps/web/.env.local; the cap is intentionally off in this environment');

	test('free user at the free cap gets 429 from /api/coach (UI bypass)', async ({
		request
	}) => {
		// Plant 2 coach_usage entries via service-role so the next
		// request is the 3rd of the day. The handler reads after-
		// increment; on a real 3rd increment it lands at 3 and fails
		// the `usedToday > TIER_LIMITS.free.dailyLimit` gate.
		const admin = getAdminClient();
		await admin
			.from('user_coach_usage')
			.upsert(
				{ user_id: USER_A.id, usage_date: TODAY, message_count: 2 },
				{ onConflict: 'user_id,usage_date' }
			);

		const token = await freshAccessToken(USER_A.email, USER_A.password);
		expect(token.length).toBeGreaterThan(20);

		// curl the endpoint directly with a benign prompt. The handler
		// will increment to 3, fail the gate, and return 429.
		const res = await request.post('http://localhost:7777/api/coach', {
			headers: {
				'content-type': 'application/json',
				'x-supabase-authorization': `Bearer ${token}`
			},
			data: {
				messages: [{ role: 'user', content: 'e2e wire test' }],
				plan_id: null,
				recent_runs_limit: 10
			}
		});

		expect(res.status()).toBe(429);
		const body = await res.json();
		expect(body.error).toBe('daily_limit');
		expect(body.tier).toBe('free');
		expect(body.limit).toBe(2);
		expect(body.message).toMatch(/Daily|coach messages|Upgrade to Pro/i);

		// Cleanup so other tests don't see runner sitting at the limit.
		await admin
			.from('user_coach_usage')
			.delete()
			.eq('user_id', USER_A.id)
			.eq('usage_date', TODAY);
	});

	test('Pro user at the free cap keeps going (Pro has a higher daily cap)', async ({
		request
	}) => {
		// Symmetry test: morgan is on the Pro tier per seed. Planted at
		// the free cap (= 2 messages), which is well under Pro's daily
		// cap (10). A Pro user must NOT see 429 at this usage level —
		// either the LLM streams or some upstream non-429 status comes
		// back. A 429 from `tier: 'free'` would mean the free-cap branch
		// fired for a Pro caller (regression).
		const admin = getAdminClient();
		await admin
			.from('user_coach_usage')
			.upsert(
				{ user_id: USER_C_PRO.id, usage_date: TODAY, message_count: 2 },
				{ onConflict: 'user_id,usage_date' }
			);

		try {
			const token = await freshAccessToken(USER_C_PRO.email, USER_C_PRO.password);
			expect(token.length).toBeGreaterThan(20);

			// We don't care if the LLM call succeeds (no API key in
			// CI); we only care that the free-cap branch didn't fire.
			const res = await request.post('http://localhost:7777/api/coach', {
				headers: {
					'content-type': 'application/json',
					'x-supabase-authorization': `Bearer ${token}`
				},
				data: {
					messages: [{ role: 'user', content: 'e2e pro wire test' }],
					plan_id: null,
					recent_runs_limit: 10
				}
			});

			if (res.status() === 429) {
				const body = await res.json();
				// Pin: the only 429 a Pro caller can legitimately see is
				// their OWN cap (`tier: 'pro'`). A `tier: 'free'` 429
				// means the free branch leaked to a Pro user.
				expect(body.tier, 'pro user must not hit free-tier cap').not.toBe(
					'free'
				);
			} else {
				expect(res.status()).not.toBe(429);
			}
		} finally {
			await admin
				.from('user_coach_usage')
				.delete()
				.eq('user_id', USER_C_PRO.id)
				.eq('usage_date', TODAY);
		}
	});

	test('Pro user at the Pro cap gets 429 from /api/coach (Pro is now finite)', async ({
		request
	}) => {
		// Plant 10 usage entries for the Pro user — the next request
		// is the 11th and must trip the daily-cap gate. This pins the
		// Pro daily cap as a real ceiling rather than the previous
		// "unlimited" branch. See decisions.md § 23 for the policy
		// change.
		const admin = getAdminClient();
		await admin
			.from('user_coach_usage')
			.upsert(
				{ user_id: USER_C_PRO.id, usage_date: TODAY, message_count: 10 },
				{ onConflict: 'user_id,usage_date' }
			);

		try {
			const token = await freshAccessToken(USER_C_PRO.email, USER_C_PRO.password);
			expect(token.length).toBeGreaterThan(20);

			const res = await request.post('http://localhost:7777/api/coach', {
				headers: {
					'content-type': 'application/json',
					'x-supabase-authorization': `Bearer ${token}`
				},
				data: {
					messages: [{ role: 'user', content: 'e2e pro at-cap test' }],
					plan_id: null,
					recent_runs_limit: 10
				}
			});

			expect(res.status()).toBe(429);
			const body = await res.json();
			expect(body.error).toBe('daily_limit');
			expect(body.tier).toBe('pro');
			expect(body.limit).toBe(10);
		} finally {
			await admin
				.from('user_coach_usage')
				.delete()
				.eq('user_id', USER_C_PRO.id)
				.eq('usage_date', TODAY);
		}
	});

	test('anon POST to /api/coach is rejected (no Supabase auth header)', async ({
		request
	}) => {
		// Defence in depth: even before we hit the daily-cap branch,
		// the handler must reject anon callers. Hit /api/coach with
		// no auth header and assert 401.
		const res = await request.post('http://localhost:7777/api/coach', {
			headers: { 'content-type': 'application/json' },
			data: {
				messages: [{ role: 'user', content: 'anon attempt' }],
				plan_id: null,
				recent_runs_limit: 10
			}
		});
		expect(res.status()).toBe(401);
	});
});
