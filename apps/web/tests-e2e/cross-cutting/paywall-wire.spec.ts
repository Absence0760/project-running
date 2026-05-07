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

	test('free user with 5 messages used today gets 429 from /api/coach (UI bypass)', async ({
		request
	}) => {
		// Plant 5 coach_usage entries via service-role so the next
		// request is the 6th of the day. The handler reads after-
		// increment; on a real 6th increment it lands at 6 and fails
		// the `usedToday > dailyLimit` gate.
		const admin = getAdminClient();
		await admin
			.from('user_coach_usage')
			.upsert(
				{ user_id: USER_A.id, usage_date: TODAY, message_count: 5 },
				{ onConflict: 'user_id,usage_date' }
			);

		const token = await freshAccessToken(USER_A.email, USER_A.password);
		expect(token.length).toBeGreaterThan(20);

		// curl the endpoint directly with a benign prompt. The handler
		// will increment to 6, fail the gate, and return 429.
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
		expect(body.limit).toBe(5);
		expect(body.message).toMatch(/Daily|coach messages|Upgrade to Pro/i);

		// Cleanup so other tests don't see runner sitting at the limit.
		await admin
			.from('user_coach_usage')
			.delete()
			.eq('user_id', USER_A.id)
			.eq('usage_date', TODAY);
	});

	test('Pro user with the same 5-message count keeps going (free cap doesn\'t apply)', async ({
		request
	}) => {
		// Symmetry test: morgan is on the Pro tier per seed.
		// subscription_tier='pro' lifts the daily-cap branch entirely
		// — the handler routes Pro callers through the per-hour
		// rate-limit which has a much higher ceiling. With 5 messages
		// already used, a Pro user must NOT see 429.
		const admin = getAdminClient();
		await admin
			.from('user_coach_usage')
			.upsert(
				{ user_id: USER_C_PRO.id, usage_date: TODAY, message_count: 5 },
				{ onConflict: 'user_id,usage_date' }
			);

		try {
			const token = await freshAccessToken(USER_C_PRO.email, USER_C_PRO.password);
			expect(token.length).toBeGreaterThan(20);

			// We don't care if the LLM call succeeds (no API key in
			// CI); we only care that the daily-cap gate didn't fire.
			// A 200 with SSE OR a 4xx that's NOT 429 OR a 5xx upstream
			// error all prove the gate let us through.
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

			// The free-cap branch returns 429 with `limit: 5`; the
			// Pro per-hour branch can also return 429 (different
			// payload, no `limit: 5`). Tolerate either non-429 OR a
			// 429 whose payload is NOT the free-cap shape.
			if (res.status() === 429) {
				const body = await res.json();
				expect(body.tier, 'pro user should not hit free-tier cap').not.toBe(
					'free'
				);
			} else {
				// 200 / 4xx / 5xx — anything that proves the free cap
				// didn't fire. Pin the negative.
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
