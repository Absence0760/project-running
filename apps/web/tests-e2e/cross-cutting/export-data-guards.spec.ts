import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * `export-data` Edge Function guards — pre-side-effect gates that
 * protect the export endpoint from malformed requests before the
 * multi-MB GPX-zip build + Storage upload runs.
 *
 * The 400-invalid-format gate sits AFTER the rate-limit check
 * (line 100 → 107 of export-data/index.ts), so each invalid-
 * format test consumes one of the seed user's 2/hour free-tier
 * slots. `beforeEach` wipes the user's `export-data` rate-limit
 * row via service-role so the spec is deterministic — without
 * the wipe, two reruns within an hour would 429 instead of 400
 * and tests would flake.
 *
 * Mirror of clip-public-track-guards + delete-account-guards
 * for the fourth of five JWT-gated EFs.
 */

const FUNCTION_URL_PATH = '/functions/v1/export-data';

async function callEf(opts: {
	method?: string;
	body?: unknown;
	authHeader?: string;
	rawBody?: string;
}): Promise<{ status: number; text: string }> {
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
	const text = await res.text();
	return { status: res.status, text };
}

async function freshUserToken(): Promise<string> {
	const client = await getUserClient({
		email: USER_A.email,
		password: USER_A.password
	});
	const { data } = await client.auth.getSession();
	const tok = data.session?.access_token;
	if (!tok) throw new Error('failed to mint user JWT for export-data test');
	return `Bearer ${tok}`;
}

async function clearExportDataRateLimit(): Promise<void> {
	// Wipe the seed user's export-data rate-limit row so each test
	// starts at count=0. The bucket is keyed by user_id + bucket
	// name; the next legitimate INSERT will repopulate at count=1.
	const admin = getAdminClient();
	await admin
		.from('rate_limits')
		.delete()
		.eq('user_id', USER_A.id)
		.eq('bucket', 'export-data');
}

test.describe('export-data — pre-side-effect guards', () => {
	test.beforeEach(async () => {
		await clearExportDataRateLimit();
	});

	test('GET (with auth) → 405 method not allowed', async () => {
		// Method check is the very first gate (line 68). GET would
		// otherwise let a future "stream the export inline" refactor
		// land without going through the rate-limit + Storage path,
		// breaking the fail-closed throttling that prevents the EF
		// from being used as a free zip-builder.
		const auth = await freshUserToken();
		const r = await callEf({ method: 'GET', authHeader: auth });
		expect(r.status).toBe(405);
	});

	test('PUT (with auth) → 405 method not allowed', async () => {
		const auth = await freshUserToken();
		const r = await callEf({ method: 'PUT', authHeader: auth });
		expect(r.status).toBe(405);
	});

	test('POST without Authorization → 401 (platform gate)', async () => {
		// verify_jwt=true on this function; platform 401s before the
		// handler runs. Pin status only.
		const r = await callEf({ body: { format: 'gpx' } });
		expect(r.status).toBe(401);
	});

	test('POST with auth + oversized body → 413 (body limit cap)', async () => {
		// Body cap is 1 KB (line 73). The cap fires before
		// auth.getUser so this test doesn't consume the rate-limit
		// slot — the wipe before each test handles the other side.
		const auth = await freshUserToken();
		const oversized = JSON.stringify({ pad: 'a'.repeat(2048), format: 'csv' });
		const r = await callEf({ rawBody: oversized, authHeader: auth });
		expect(r.status).toBe(413);
	});

	test('POST with auth + invalid format → 400', async () => {
		// 400 fires AFTER the rate-limit check (lines 100-108) so
		// each invalid-format call consumes one slot. The beforeEach
		// wipe keeps the test deterministic. A regression that
		// loosened the `format !== 'csv' && format !== 'gpx'` check
		// would let a misspelled format string fall through to the
		// CSV builder branch (line 132), shipping a CSV under the
		// wrong content-type when the client asked for 'fit'.
		const auth = await freshUserToken();
		const r = await callEf({
			body: { format: 'fit' }, // valid-shape but unsupported
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.text).toContain('csv');
		expect(r.text).toContain('gpx');
	});

	test('POST with auth + non-string format → 400', async () => {
		// The cast `body.format ?? 'csv'` followed by `!== 'csv' &&
		// !== 'gpx'` catches non-string formats too (numbers, bools,
		// arrays — all surface as "not csv && not gpx"). Pin to
		// confirm the cast/compare combo is the right shape — a
		// regression that did `String(body.format)` early would let
		// e.g. `format: 0` cast to "0" and fall through cleanly to
		// the comparison, which still rejects but with a less
		// helpful error path.
		const auth = await freshUserToken();
		const r = await callEf({
			body: { format: 42 },
			authHeader: auth
		});
		expect(r.status).toBe(400);
	});
});
