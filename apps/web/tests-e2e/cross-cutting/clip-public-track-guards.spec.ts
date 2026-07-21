import { expect, test } from '@playwright/test';

import { getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * `clip-public-track` Edge Function guards — the pre-Supabase-work
 * gates that protect the EF from malformed / abusive requests
 * before they consume any DB / Storage / clip-walk budget.
 *
 * Coverage gap rationale: the function shape (decisions §33,
 * migration 20260619_001) wraps three downstream costs — a
 * PostgREST lookup, a Storage download (up to 5 MB), and a
 * clip-walk over up to 50k points — behind an anon-or-user-JWT
 * surface. Without these guards every malformed POST would drain
 * the per-user / per-IP rate-limit budget AND consume a slice of
 * the function's CPU / memory. Pin the early-return shape so a
 * refactor that loosened any of the gates would fail loud.
 *
 * Mirror of `strava-import-guards.spec.ts`. Unlike strava-import,
 * this function runs `verify_jwt = false` (decisions §280 — a
 * logged-out spectator's bearer is the non-JWT publishable key, which
 * the platform gate would reject), so every guard below is the
 * handler's own work, not the platform's.
 */

const FUNCTION_URL_PATH = '/functions/v1/clip-public-track';

async function callEf(opts: {
	method?: string;
	body?: unknown;
	authHeader?: string;
}): Promise<{ status: number; json: Record<string, unknown> | null }> {
	const { url, anonKey } = loadSupabaseEnv();
	const headers: Record<string, string> = {
		'content-type': 'application/json',
		apikey: anonKey
	};
	if (opts.authHeader) headers['Authorization'] = opts.authHeader;
	const res = await fetch(`${url}${FUNCTION_URL_PATH}`, {
		method: opts.method ?? 'POST',
		headers,
		body: opts.body === undefined ? undefined : JSON.stringify(opts.body)
	});
	const text = await res.text();
	let json: Record<string, unknown> | null = null;
	try {
		json = text ? (JSON.parse(text) as Record<string, unknown>) : null;
	} catch {
		json = null;
	}
	return { status: res.status, json };
}

async function freshUserToken(): Promise<string> {
	const client = await getUserClient({
		email: USER_A.email,
		password: USER_A.password
	});
	const { data } = await client.auth.getSession();
	const tok = data.session?.access_token;
	if (!tok) throw new Error('failed to mint user JWT for clip-public-track test');
	return `Bearer ${tok}`;
}

test.describe('clip-public-track — pre-side-effect guards', () => {
	test('GET (with auth) → 405 method not allowed', async () => {
		// The handler short-circuits any non-POST before reading the
		// body. Pin this so a refactor that accepted GET (e.g. for a
		// debug-side endpoint) would fail loud — GET would let a
		// querystring `?run_id=...` slip past the body-shape guard
		// in step 2 and bypass the 1 KB body-limit cap.
		const auth = await freshUserToken();
		const r = await callEf({ method: 'GET', authHeader: auth });
		expect(r.status).toBe(405);
	});

	test('PUT (with auth) → 405 method not allowed', async () => {
		// Belt-and-braces for any non-POST. A future refactor that
		// flipped `!== 'POST'` to `!== 'PUT'` (rare but real) would
		// pass the GET test alone.
		const auth = await freshUserToken();
		const r = await callEf({ method: 'PUT', authHeader: auth });
		expect(r.status).toBe(405);
	});

	test('POST without Authorization header → guards still fire in-handler', async () => {
		// verify_jwt = false (decisions §280), so an Authorization-less
		// POST reaches the handler instead of dying at the platform
		// 401. The local functions relay injects the stack's anon key
		// as Authorization, which means the handler's own missing-auth
		// 401 branch is NOT reachable over the wire here — it is
		// pinned at source level by
		// functions/_shared/verify_jwt_config.test.ts instead. What
		// this test CAN pin: an unauthenticated caller's request still
		// hits every pre-side-effect body gate before any DB / Storage
		// cost — the UUID gate rejects it exactly as it does for an
		// authenticated caller.
		const r = await callEf({ body: { run_id: 'whatever' } });
		expect(r.status).toBe(400);
		expect(r.json?.error).toBe('run_id must be a UUID');
	});

	test('POST with auth + missing run_id → 400 run_id required', async () => {
		// Body shape gate. A regression that loosened the typeof check
		// would let undefined run_id pass through and hit a 500 inside
		// the PostgREST .eq('id', undefined) call, which is a leakier
		// failure mode (PostgREST exposes its internal error format).
		const auth = await freshUserToken();
		const r = await callEf({ body: {}, authHeader: auth });
		expect(r.status).toBe(400);
		expect(r.json?.error).toBe('run_id required');
	});

	test('POST with auth + non-string run_id → 400 run_id required', async () => {
		// `typeof runId !== 'string'` — numbers, booleans, arrays, and
		// objects must all be rejected at the gate. Pin a couple of
		// the shapes that an upstream client typo could plausibly
		// emit.
		const auth = await freshUserToken();
		for (const bad of [42, true, ['a'], { id: 'x' }]) {
			const r = await callEf({ body: { run_id: bad }, authHeader: auth });
			expect(r.status).toBe(400);
			expect(r.json?.error).toBe('run_id required');
		}
	});

	test('POST with auth + empty-string run_id → 400 run_id required', async () => {
		// `runId.length === 0` is the second half of the gate. A
		// regression that dropped the length check would let an empty
		// string through and waste a PostgREST lookup that will
		// always 404. Pin both halves separately so either alone
		// breaks loud.
		const auth = await freshUserToken();
		const r = await callEf({ body: { run_id: '' }, authHeader: auth });
		expect(r.status).toBe(400);
		expect(r.json?.error).toBe('run_id required');
	});

	test('POST with auth + unknown run_id uuid → 404 not found', async () => {
		// The post-Supabase visibility gate. A valid-shape request
		// against an id that doesn't exist (or that the caller can't
		// see via RLS) must surface 404, not 500 / 502. Pin this so a
		// future code path that leaked the row absence as an
		// undefined-access throws caught error doesn't break the
		// contract.
		const auth = await freshUserToken();
		const r = await callEf({
			body: { run_id: '00000000-0000-0000-0000-000000000bad' },
			authHeader: auth
		});
		expect(r.status).toBe(404);
		expect(r.json?.error).toBe('not found');
	});
});
