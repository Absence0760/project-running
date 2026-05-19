import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * `parkrun-import` Edge Function guards — pre-side-effect gates
 * that protect the parkrun.org.uk scraper from malformed input
 * before the outbound fetch + Cheerio parse runs.
 *
 * The athleteNumber regex `/^A\d{1,12}$/` is the load-bearing
 * gate. Per the comment in index.ts: "parkrun's real numbers top
 * out at 7-8 digits today; cap the regex at 12 so an attacker
 * can't post a 1 MB digit string and force the URL build +
 * outbound fetch to walk through it before parkrun's own server
 * rejects." A regression that loosened any of the regex's three
 * pieces (anchor at start, the literal `A`, the digit cap) would
 * surface as outbound traffic to a URL parkrun would 414 on, with
 * our IP eating the consequences.
 *
 * Mirror of clip-public-track / delete-account / export-data
 * guards for the last of five JWT-gated EFs. (strava-import has
 * its own dedicated guards spec.)
 *
 * Tests deliberately stop at the validation gate; the 502 +
 * happy-path branches would hit parkrun.org.uk in CI which is
 * polite to avoid.
 */

const FUNCTION_URL_PATH = '/functions/v1/parkrun-import';

async function callEf(opts: {
	body?: unknown;
	authHeader?: string;
	rawBody?: string;
}): Promise<{ status: number; json: Record<string, unknown> | null }> {
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
		method: 'POST',
		headers,
		body
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
	if (!tok) throw new Error('failed to mint user JWT for parkrun-import test');
	return `Bearer ${tok}`;
}

async function clearParkrunRateLimit(): Promise<void> {
	// Bucket cap is 4/h free (line 35 of parkrun-import/index.ts).
	// Each of the 400-branch tests below consumes one slot because
	// the rate-limit check fires before the athleteNumber regex.
	// Reset between tests so the spec is deterministic across reruns.
	const admin = getAdminClient();
	await admin
		.from('rate_limits')
		.delete()
		.eq('user_id', USER_A.id)
		.eq('bucket', 'parkrun-import');
}

test.describe('parkrun-import — pre-side-effect guards', () => {
	test.beforeEach(async () => {
		await clearParkrunRateLimit();
	});

	test('POST without Authorization → 401 (platform gate)', async () => {
		// verify_jwt=true → platform 401s before the handler runs.
		// Pin status only. A regression flipping verify_jwt=false
		// would expose the scraper-trigger endpoint as anon-callable,
		// burning our IP reputation with parkrun.
		const r = await callEf({ body: { athleteNumber: 'A123456' } });
		expect(r.status).toBe(401);
	});

	test('POST with auth + oversized body → 413 (body limit cap)', async () => {
		// Body cap is 1 KB (line 9). The cap fires before
		// auth.getUser so it doesn't consume a rate-limit slot.
		const auth = await freshUserToken();
		const oversized = JSON.stringify({ athleteNumber: 'A1', pad: 'a'.repeat(2048) });
		const r = await callEf({ rawBody: oversized, authHeader: auth });
		expect(r.status).toBe(413);
	});

	test('POST with auth + missing athleteNumber → 400 Invalid athlete number', async () => {
		// `typeof athleteNumber !== 'string'` catches undefined.
		const auth = await freshUserToken();
		const r = await callEf({ body: {}, authHeader: auth });
		expect(r.status).toBe(400);
		expect(r.json?.error).toBe('Invalid athlete number');
	});

	test('POST with auth + non-string athleteNumber → 400', async () => {
		// Number / boolean / array all fail the typeof check.
		const auth = await freshUserToken();
		const r = await callEf({
			body: { athleteNumber: 123456 },
			authHeader: auth
		});
		expect(r.status).toBe(400);
	});

	test('POST with auth + missing "A" prefix → 400', async () => {
		// `/^A\d{1,12}$/` anchors on a literal `A`. parkrun athlete
		// numbers are always prefixed `A`; a regression that
		// loosened the anchor to optional would let arbitrary
		// numeric IDs through (the URL build wouldn't 404 on the
		// parkrun side but would land at a non-result page).
		const auth = await freshUserToken();
		const r = await callEf({
			body: { athleteNumber: '123456' },
			authHeader: auth
		});
		expect(r.status).toBe(400);
		expect(r.json?.error).toBe('Invalid athlete number');
	});

	test('POST with auth + >12-digit athleteNumber → 400 (the 1 MB attack guard)', async () => {
		// The `\d{1,12}` upper bound is THE attack-surface guard.
		// Without it an attacker could POST `A` + a 1 MB digit
		// string and force the EF to build the URL + fire the
		// outbound fetch before parkrun's own server rejects with
		// 414. Pinning the boundary keeps the regex's `{1,12}`
		// upper bound from drifting open in a future copy-edit.
		const auth = await freshUserToken();
		// 13 digits is one past the limit.
		const r = await callEf({
			body: { athleteNumber: 'A1234567890123' },
			authHeader: auth
		});
		expect(r.status).toBe(400);
	});

	test('POST with auth + lowercase "a" prefix → 400 (case-sensitive anchor)', async () => {
		// The regex `/^A\d.../` is case-sensitive. A regression that
		// added the `i` flag would accept 'a123456' AND
		// 'AaA123456'-type variations, broadening the input space
		// the URL builder accepts. Pin so the case-sensitivity is
		// load-bearing, not incidental.
		const auth = await freshUserToken();
		const r = await callEf({
			body: { athleteNumber: 'a123456' },
			authHeader: auth
		});
		expect(r.status).toBe(400);
	});
});
