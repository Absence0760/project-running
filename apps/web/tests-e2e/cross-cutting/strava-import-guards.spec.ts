import { expect, test } from '@playwright/test';

import { originOf } from '../fixtures/base-url';
import { getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * `strava-import` Edge Function guards — fail-closed behaviour at
 * each pre-side-effect gate. These are the contracts that protect
 * the OAuth handshake from misuse:
 *
 *   1. POST without Authorization → 401 (no anon path).
 *   2. POST with auth but no action / wrong action → 400.
 *   3. POST with auth + `connect` but missing `code` → 400.
 *   4. POST with auth + `connect` + scope wrong-typed → 400.
 *   5. POST with auth + `connect` + redirect_uri unset → 400.
 *   6. POST with auth + `connect` + redirect_uri set but the env's
 *      `STRAVA_ALLOWED_REDIRECTS` allowlist is empty/unset → 503
 *      `strava_not_configured`. (Fail-closed; a missing env var
 *      must NOT be treated as "allow any redirect".)
 *   7. POST with auth + `sync` + `lookbackDays` out of range → 400.
 *
 * Of the allowlist's three branches this lane can only ever reach
 * guard 6, and that is deliberate. The sharded suite runs against the
 * auto-started edge runtime, which carries no
 * `STRAVA_ALLOWED_REDIRECTS` — so every `connect` posted
 * here short-circuits at the 503 before the comparison, whatever
 * `redirect_uri` it claims. Setting the var in this job would flip
 * this test rather than add coverage. (The `edge-functions` CI job
 * does set it, for a separately-booted function host that no
 * `strava-import` test posts to.)
 *
 * The other two branches — a redirect IN the list accepted, one NOT
 * in it refused with 400 `invalid_redirect_uri` — are pinned pure, in
 * `apps/backend/supabase/functions/_shared/redirect_allowlist.test.ts`,
 * which also source-guards that this handler still routes through the
 * gate and still does so before the token exchange. Accepting means
 * proceeding to Strava's `/oauth/token`, so a wire-level positive test
 * would make CI depend on a third party.
 */

const FUNCTION_URL_PATH = '/functions/v1/strava-import';

async function postEf(opts: {
	body: unknown;
	authHeader?: string;
}): Promise<{ status: number; json: Record<string, unknown> }> {
	const { url, anonKey } = loadSupabaseEnv();
	const headers: Record<string, string> = {
		'content-type': 'application/json',
		apikey: anonKey
	};
	if (opts.authHeader) headers['Authorization'] = opts.authHeader;
	const res = await fetch(`${url}${FUNCTION_URL_PATH}`, {
		method: 'POST',
		headers,
		body: JSON.stringify(opts.body)
	});
	const json = (await res.json().catch(() => ({}))) as Record<string, unknown>;
	return { status: res.status, json };
}

async function freshUserToken(): Promise<string> {
	const client = await getUserClient({
		email: USER_A.email,
		password: USER_A.password
	});
	const { data } = await client.auth.getSession();
	const tok = data.session?.access_token;
	if (!tok) throw new Error('failed to mint user JWT for strava-import test');
	return `Bearer ${tok}`;
}

test.describe('strava-import — pre-side-effect guards', () => {
	test('no Authorization header → 401', async () => {
		const r = await postEf({ body: { action: 'connect' } });
		expect(r.status).toBe(401);
	});

	test('auth + missing action + missing code → 400 invalid_action', async () => {
		const auth = await freshUserToken();
		const r = await postEf({ body: {}, authHeader: auth });
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_action');
	});

	test('auth + bogus action → 400 invalid_action', async () => {
		const auth = await freshUserToken();
		const r = await postEf({
			body: { action: 'wipe-account' },
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_action');
	});

	test('auth + connect + missing code → 400 invalid_code', async ({ baseURL }) => {
		const auth = await freshUserToken();
		const r = await postEf({
			body: {
				action: 'connect',
				scope: 'read,activity:read_all',
				redirect_uri: `${originOf(baseURL)}/settings/integrations`
			},
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_code');
	});

	test('auth + connect + non-string scope → 400 invalid_scope', async ({ baseURL }) => {
		const auth = await freshUserToken();
		const r = await postEf({
			body: {
				action: 'connect',
				code: 'short_code_42',
				scope: 12345,
				redirect_uri: `${originOf(baseURL)}/settings/integrations`
			},
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_scope');
	});

	test('auth + connect + missing redirect_uri → 400 invalid_redirect_uri', async () => {
		const auth = await freshUserToken();
		const r = await postEf({
			body: {
				action: 'connect',
				code: 'short_code_42',
				scope: 'read,activity:read_all'
			},
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_redirect_uri');
	});

	test('auth + connect + valid shape but STRAVA_ALLOWED_REDIRECTS unset → 503 strava_not_configured (fail-closed)', async () => {
		// The local stack doesn't ship STRAVA_ALLOWED_REDIRECTS. The EF
		// must fail closed: 503 instead of falling through to "allow
		// any redirect". A regression that dropped this guard would
		// land here — the response would be 200 / 4xx-other-than-503 /
		// reach the upstream Strava token exchange.
		//
		// In production STRAVA_ALLOWED_REDIRECTS is set (via
		// supabase secrets), so this branch never fires there. Pinning
		// the local-dev / CI side ensures the guard EXISTS — that's the
		// regression-catching part.
		const auth = await freshUserToken();
		const r = await postEf({
			body: {
				action: 'connect',
				code: 'short_code_42',
				scope: 'read,activity:read_all',
				redirect_uri: 'https://attacker.example.com/cb'
			},
			authHeader: auth
		});
		expect(r.status).toBe(503);
		expect(r.json.error).toBe('strava_not_configured');
	});

	test('auth + sync + non-positive lookbackDays → 400 invalid_lookback_days', async () => {
		const auth = await freshUserToken();
		const r = await postEf({
			body: { action: 'sync', lookbackDays: 0 },
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_lookback_days');
	});

	test('auth + sync + lookbackDays > 365 → 400 invalid_lookback_days', async () => {
		const auth = await freshUserToken();
		const r = await postEf({
			body: { action: 'sync', lookbackDays: 999 },
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_lookback_days');
	});

	test('auth + sync + non-integer lookbackDays → 400 invalid_lookback_days', async () => {
		const auth = await freshUserToken();
		const r = await postEf({
			body: { action: 'sync', lookbackDays: 30.5 },
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json.error).toBe('invalid_lookback_days');
	});
});
