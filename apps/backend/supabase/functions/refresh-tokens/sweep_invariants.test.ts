/// What the cron sweep ASKS the database for, and what it does with the
/// integrations it cannot refresh.
///
/// The sibling suite drives the sweep end to end and proves the CAS write
/// and the 4xx/5xx classification, but its mock builder answers every
/// `.select` / `.eq` / `.lt` / `.order` / `.limit` with itself and records
/// none of them — so the whole query is unmeasured. Three regressions are
/// invisible from there and all three are expensive: a sweep that stopped
/// filtering on `provider` would push every Garmin and parkrun row through
/// Strava's OAuth endpoint, a sweep that stopped bounding `token_expiry`
/// would refresh the entire table every hour, and a sweep that stopped
/// ordering by expiry would spend its 500-row budget on an arbitrary slice
/// while the tokens actually about to die went untouched.
///
/// The disconnect write has the same shape: `lib.test.ts` asserts the
/// payload it carries and nothing about who it lands on. Dropping the
/// provider predicate there would disconnect a runner's Garmin because
/// their Strava grant died.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/refresh-tokens/sweep_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { refreshExpiringStravaTokens } from './lib.ts';

interface QueryCall {
	fn: string;
	args: unknown[];
}

interface RecordedQuery {
	table: string;
	calls: QueryCall[];
	isUpdate: boolean;
}

interface RpcCall {
	name: string;
	args: Record<string, unknown>;
}

interface MockOpts {
	expiring: Array<{ id: string; user_id: string }>;
	/// Vault answer per user id. A missing entry answers as an RPC error,
	/// which is how a revoked grant or a Vault outage reads to the sweep.
	vault: Record<string, { refresh_token: string } | 'error' | 'empty'>;
}

function makeMock(opts: MockOpts) {
	const queries: RecordedQuery[] = [];
	const rpcCalls: RpcCall[] = [];

	const builder = (table: string) => {
		const q: RecordedQuery = { table, calls: [], isUpdate: false };
		queries.push(q);
		// deno-lint-ignore no-explicit-any
		const b: any = {};
		for (const fn of ['select', 'eq', 'lt', 'gt', 'order', 'limit']) {
			b[fn] = (...args: unknown[]) => {
				q.calls.push({ fn, args });
				return b;
			};
		}
		b.update = (...args: unknown[]) => {
			q.isUpdate = true;
			q.calls.push({ fn: 'update', args });
			return b;
		};
		b.then = (onF: (v: unknown) => unknown, onR?: (e: unknown) => unknown) =>
			Promise.resolve(
				q.isUpdate ? { data: null, error: null } : { data: opts.expiring, error: null },
			).then(onF, onR);
		return b;
	};

	const supabase = {
		from: (table: string) => builder(table),
		rpc: (name: string, args: Record<string, unknown>) => {
			rpcCalls.push({ name, args });
			if (name === 'get_integration_tokens') {
				const answer = opts.vault[args.p_user_id as string];
				if (answer === undefined || answer === 'error') {
					return Promise.resolve({ data: null, error: { code: '42501', message: 'denied' } });
				}
				if (answer === 'empty') return Promise.resolve({ data: [], error: null });
				return Promise.resolve({
					data: [{ refresh_token: answer.refresh_token, access_token: 'at', token_expiry: 'x' }],
					error: null,
				});
			}
			if (name === 'set_integration_tokens_cas') {
				return Promise.resolve({ data: true, error: null });
			}
			return Promise.resolve({ data: null, error: null });
		},
	};

	// deno-lint-ignore no-explicit-any
	return { supabase: supabase as any, queries, rpcCalls };
}

function stubFetch(responder: (body: string) => Response) {
	const orig = globalThis.fetch;
	globalThis.fetch = ((_url: string, init?: RequestInit) =>
		Promise.resolve(responder(String(init?.body ?? '')))) as typeof fetch;
	return () => {
		globalThis.fetch = orig;
	};
}

const FUTURE_EPOCH_S = Math.floor(Date.now() / 1000) + 3600;

function issuedToken(refreshToken: string): Response {
	return Response.json({
		access_token: `at-for-${refreshToken}`,
		refresh_token: `rt-for-${refreshToken}`,
		expires_at: FUTURE_EPOCH_S,
	});
}

function argsOf(q: RecordedQuery, fn: string): unknown[][] {
	return q.calls.filter((c) => c.fn === fn).map((c) => c.args);
}

Deno.test('the sweep asks only for Strava integrations, and only the expiring ones', async () => {
	const { supabase, queries } = makeMock({ expiring: [], vault: {} });
	const before = Date.now();
	await refreshExpiringStravaTokens(supabase);
	const after = Date.now();

	assertEquals(queries.length, 1);
	const q = queries[0];
	assertEquals(q.table, 'integrations');

	// The provider predicate is the one that keeps a Garmin or parkrun row
	// out of Strava's OAuth endpoint entirely.
	assertEquals(argsOf(q, 'eq'), [['provider', 'strava']]);

	// A single upper bound on token_expiry, an hour out. Bracketed against
	// the test's own clock rather than recomputed from the subject's, so a
	// sweep that widened the horizon to a day — or dropped it and refreshed
	// the whole table every tick — fails here.
	const lt = argsOf(q, 'lt');
	assertEquals(lt.length, 1);
	assertEquals(lt[0][0], 'token_expiry');
	const horizonMs = Date.parse(String(lt[0][1]));
	assert(Number.isFinite(horizonMs), `token_expiry bound is not a timestamp: ${lt[0][1]}`);
	assert(
		horizonMs >= before + 3600_000 && horizonMs <= after + 3600_000,
		`horizon ${new Date(horizonMs).toISOString()} is not one hour out`,
	);
});

Deno.test('the bounded sweep spends its budget on the tokens closest to dying', async () => {
	const { supabase, queries } = makeMock({ expiring: [], vault: {} });
	await refreshExpiringStravaTokens(supabase);
	const q = queries[0];

	// The order and the limit are one invariant, not two: a cap with no
	// order refreshes an arbitrary 500 of the expiring set and can leave
	// the soonest-to-expire untouched run after run.
	assertEquals(argsOf(q, 'order'), [['token_expiry', { ascending: true }]]);
	assertEquals(argsOf(q, 'limit'), [[500]]);
});

Deno.test('the sweep reads the two columns it uses, and no token material', async () => {
	const { supabase, queries } = makeMock({ expiring: [], vault: {} });
	await refreshExpiringStravaTokens(supabase);
	const select = argsOf(queries[0], 'select');
	assertEquals(select.length, 1);
	const cols = String(select[0][0]);
	assertEquals(cols.split(',').map((c) => c.trim()).sort(), ['id', 'user_id']);
	// Tokens live in Vault and come back through `get_integration_tokens`.
	// A select that started dragging them through the table read would put
	// refresh tokens in a PostgREST response for every expiring row.
	assert(!cols.includes('token'), `the sweep must not select token columns: ${cols}`);
});

Deno.test('a dead grant disconnects that provider for that user, and nothing else', async () => {
	const { supabase, queries } = makeMock({
		expiring: [{ id: 'i1', user_id: 'u1' }],
		vault: { u1: { refresh_token: 'rt-1' } },
	});
	const restore = stubFetch(() => Response.json({ error: 'invalid_grant' }, { status: 400 }));
	try {
		await refreshExpiringStravaTokens(supabase);
	} finally {
		restore();
	}

	const updates = queries.filter((q) => q.isUpdate);
	assertEquals(updates.length, 1);
	assertEquals(updates[0].table, 'integrations');
	// Both predicates, or a runner loses their Garmin connection because
	// their Strava grant expired.
	const eqs = argsOf(updates[0], 'eq');
	assertEquals(eqs.length, 2);
	assertEquals(new Set(eqs.map((a) => `${a[0]}=${a[1]}`)), new Set(['user_id=u1', 'provider=strava']));
});

Deno.test('an unreadable vault row skips that integration and the sweep carries on', async () => {
	// The Vault read is per-integration. A sweep that let one failure escape
	// would stop at the first revoked grant and never reach the rows behind
	// it — every hour, at the same row.
	const { supabase, rpcCalls } = makeMock({
		expiring: [{ id: 'i1', user_id: 'u1' }, { id: 'i2', user_id: 'u2' }],
		vault: { u1: 'error', u2: { refresh_token: 'rt-2' } },
	});
	const restore = stubFetch((body) => issuedToken(JSON.parse(body).refresh_token));
	try {
		const { refreshed } = await refreshExpiringStravaTokens(supabase);
		assertEquals(refreshed, 1);
	} finally {
		restore();
	}

	// The unreadable one never reached Strava, and the readable one did.
	const cas = rpcCalls.filter((c) => c.name === 'set_integration_tokens_cas');
	assertEquals(cas.length, 1);
	assertEquals(cas[0].args.p_user_id, 'u2');
	assertEquals(cas[0].args.p_expected_refresh_token, 'rt-2');
});

Deno.test('a vault row with no refresh token is skipped before Strava is called at all', async () => {
	const { supabase, rpcCalls } = makeMock({
		expiring: [{ id: 'i1', user_id: 'u1' }],
		vault: { u1: 'empty' },
	});
	let fetches = 0;
	const restore = stubFetch(() => {
		fetches++;
		return issuedToken('never');
	});
	try {
		const { refreshed } = await refreshExpiringStravaTokens(supabase);
		assertEquals(refreshed, 0);
	} finally {
		restore();
	}
	assertEquals(fetches, 0);
	assert(!rpcCalls.some((c) => c.name === 'set_integration_tokens_cas'));
});

Deno.test('each integration is refreshed with its OWN token, and the count is the successes', async () => {
	const { supabase, rpcCalls } = makeMock({
		expiring: [
			{ id: 'i1', user_id: 'u1' },
			{ id: 'i2', user_id: 'u2' },
			{ id: 'i3', user_id: 'u3' },
		],
		vault: { u1: { refresh_token: 'rt-1' }, u2: 'error', u3: { refresh_token: 'rt-3' } },
	});
	const restore = stubFetch((body) => issuedToken(JSON.parse(body).refresh_token));
	try {
		const { refreshed } = await refreshExpiringStravaTokens(supabase);
		assertEquals(refreshed, 2);
	} finally {
		restore();
	}

	// Stated as a per-row pairing rather than a count: a sweep that reused
	// one row's token for every integration would satisfy any equality
	// between two of its own outputs, and would rotate one runner's grant
	// onto another's row.
	const cas = rpcCalls.filter((c) => c.name === 'set_integration_tokens_cas');
	assertEquals(
		cas.map((c) => [c.args.p_user_id, c.args.p_expected_refresh_token, c.args.p_refresh_token]),
		[
			['u1', 'rt-1', 'rt-for-rt-1'],
			['u3', 'rt-3', 'rt-for-rt-3'],
		],
	);
	assert(cas.every((c) => c.args.p_provider === 'strava'));
});
