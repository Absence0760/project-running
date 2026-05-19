import { expect, test } from '@playwright/test';

import { getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * `delete-account` Edge Function guards — pre-side-effect gates
 * that protect the destructive account-deletion endpoint from
 * malformed requests before the rate-limit + Storage walk + auth
 * admin delete chain runs.
 *
 * Care: every successful POST here would actually drain the
 * seed user's data on the local stack. The tests below stop at
 * the gates that fire BEFORE auth.getUser() — method check,
 * body-limit check, and the platform's JWT-verify gate. Pinning
 * just these is enough to catch the regression vectors that
 * matter (a refactor that accepted GET; a body-limit loosening
 * that let a chunked payload bypass the cap; a verify_jwt = false
 * flip that exposed the URL anon-callable).
 *
 * Mirror of strava-import-guards.spec.ts + clip-public-track-
 * guards.spec.ts for the third of five JWT-gated EFs.
 */

const FUNCTION_URL_PATH = '/functions/v1/delete-account';

async function callEf(opts: {
	method?: string;
	body?: unknown;
	authHeader?: string;
	rawBody?: string;
}): Promise<{ status: number }> {
	const { url, anonKey } = loadSupabaseEnv();
	const headers: Record<string, string> = {
		'content-type': 'application/json',
		apikey: anonKey
	};
	if (opts.authHeader) headers['Authorization'] = opts.authHeader;
	const body =
		opts.rawBody !== undefined
			? opts.rawBody
			: opts.body === undefined
				? undefined
				: JSON.stringify(opts.body);
	const res = await fetch(`${url}${FUNCTION_URL_PATH}`, {
		method: opts.method ?? 'POST',
		headers,
		body
	});
	await res.body?.cancel();
	return { status: res.status };
}

async function freshUserToken(): Promise<string> {
	const client = await getUserClient({
		email: USER_A.email,
		password: USER_A.password
	});
	const { data } = await client.auth.getSession();
	const tok = data.session?.access_token;
	if (!tok) throw new Error('failed to mint user JWT for delete-account test');
	return `Bearer ${tok}`;
}

test.describe('delete-account — pre-side-effect guards', () => {
	test('GET (with auth) → 405 method not allowed', async () => {
		// Method check is the first gate in the handler (line 63). A
		// regression that loosened it (e.g. accepted GET for a
		// debug-only "preview" path) would expose the destructive
		// endpoint to URL-only browsing — the worst possible failure
		// mode. The GET request never reaches auth.getUser() so the
		// seed user's data is safe to exercise.
		const auth = await freshUserToken();
		const r = await callEf({ method: 'GET', authHeader: auth });
		expect(r.status).toBe(405);
	});

	test('PUT (with auth) → 405 method not allowed', async () => {
		// Same gate, different verb. A `!== 'POST'` → `!== 'PUT'`
		// drive-by edit would pass the GET test alone.
		const auth = await freshUserToken();
		const r = await callEf({ method: 'PUT', authHeader: auth });
		expect(r.status).toBe(405);
	});

	test('POST without Authorization → 401 (platform gate)', async () => {
		// config.toml line 30-33 leaves delete-account on the default
		// verify_jwt=true so the platform 401s before the handler
		// runs. The handler also has its own 401 for defence-in-depth
		// (line 73-76); the platform's response shape is what reaches
		// the wire. Pin status only — a regression that flipped
		// verify_jwt to false WITHOUT keeping the handler-side gate
		// equivalent would surface the destructive endpoint as
		// anon-callable.
		const r = await callEf({ body: {} });
		expect(r.status).toBe(401);
	});

	test('POST with auth + oversized body → 413 (body limit cap)', async () => {
		// delete-account takes no body — readJsonWithLimit caps at
		// 256 bytes (line 70). The cap exists to close the
		// chunked-transfer-encoding bypass that the bare Content-
		// Length header check left open. A regression that widened
		// the cap (e.g. accidentally bumped to 1 MB during a copy-
		// paste) would let an attacker stream a malformed body to
		// stall the handler's body reader. The reader returns the
		// tooLarge response BEFORE auth.getUser() so this fires
		// without consuming a rate-limit slot on the seed user.
		const auth = await freshUserToken();
		// 512 bytes of junk — past the 256-byte cap.
		const oversized = JSON.stringify({ pad: 'a'.repeat(512) });
		const r = await callEf({
			rawBody: oversized,
			authHeader: auth
		});
		expect(r.status).toBe(413);
	});
});
