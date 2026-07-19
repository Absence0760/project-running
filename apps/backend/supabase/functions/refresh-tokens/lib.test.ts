/// Pins issue #362 — the deprecated `refresh-tokens` cron EF must route its
/// Strava token refresh through the CAS-protected `refreshStravaToken` helper
/// (`set_integration_tokens_cas`), NOT the unconditional `set_integration_tokens`
/// it used to hand-roll. Without the compare-and-swap, a cron refresh racing an
/// on-demand / webhook refresh could land after the CAS winner and clobber the
/// canonical token pair with a stale-old refresh token.
///
/// The mock supabase's vault implements CAS semantics (a `set_..._cas` succeeds
/// only when the expected refresh token still matches the stored one), so a
/// concurrency test can prove the winner's tokens survive.
///
/// Run with:
///   cd apps/backend && deno test --no-check supabase/functions/refresh-tokens/lib.test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { refreshExpiringStravaTokens } from './lib.ts';
import { refreshStravaToken } from '../_shared/strava.ts';

type RpcCall = { name: string; args: Record<string, unknown> };

interface VaultRow {
	refresh_token: string;
	access_token: string;
	token_expiry: string;
}

interface MockOpts {
	expiring: Array<{ id: string; user_id: string }>;
	vault: VaultRow;
}

function makeMock(opts: MockOpts) {
	const rpcCalls: RpcCall[] = [];
	const updates: Array<{ payload: Record<string, unknown> }> = [];
	const vault = { ...opts.vault };

	const builder = () => {
		let isUpdate = false;
		const b: Record<string, unknown> = {};
		const chain = () => b;
		b.select = chain;
		b.eq = chain;
		b.lt = chain;
		b.order = chain;
		b.limit = chain;
		b.update = (payload: Record<string, unknown>) => {
			isUpdate = true;
			updates.push({ payload });
			return b;
		};
		b.then = (
			onF: (v: unknown) => unknown,
			onR?: (e: unknown) => unknown,
		) => Promise.resolve(isUpdate ? { error: null } : { data: opts.expiring }).then(onF, onR);
		return b;
	};

	const supabase = {
		from: () => builder(),
		rpc: (name: string, args: Record<string, unknown>) => {
			rpcCalls.push({ name, args });
			if (name === 'get_integration_tokens') {
				return Promise.resolve({
					data: [{
						refresh_token: vault.refresh_token,
						access_token: vault.access_token,
						token_expiry: vault.token_expiry,
					}],
					error: null,
				});
			}
			if (name === 'set_integration_tokens_cas') {
				// CAS: the write applies only if the expected refresh token still
				// matches what's in the vault.
				if (args.p_expected_refresh_token === vault.refresh_token) {
					vault.refresh_token = args.p_refresh_token as string;
					vault.access_token = args.p_access_token as string;
					vault.token_expiry = args.p_token_expiry as string;
					return Promise.resolve({ data: true, error: null });
				}
				return Promise.resolve({ data: false, error: null });
			}
			if (name === 'set_integration_tokens') {
				// The pre-fix, non-CAS path — unconditional overwrite (the bug).
				vault.refresh_token = args.p_refresh_token as string;
				vault.access_token = args.p_access_token as string;
				vault.token_expiry = args.p_token_expiry as string;
				return Promise.resolve({ data: null, error: null });
			}
			return Promise.resolve({ data: null, error: null });
		},
	};

	// deno-lint-ignore no-explicit-any
	return { supabase: supabase as any, rpcCalls, updates, vault };
}

function stubFetch(responder: () => Response) {
	const orig = globalThis.fetch;
	globalThis.fetch = (() => Promise.resolve(responder())) as typeof fetch;
	return () => {
		globalThis.fetch = orig;
	};
}

const FUTURE_EPOCH_S = Math.floor(Date.now() / 1000) + 3600;

Deno.test('refresh-tokens routes through the CAS helper with the read refresh token', async () => {
	const { supabase, rpcCalls, vault } = makeMock({
		expiring: [{ id: 'i1', user_id: 'u1' }],
		vault: { refresh_token: 'stale-rt', access_token: 'old-at', token_expiry: 'x' },
	});
	const restore = stubFetch(() =>
		Response.json({ access_token: 'new-at', refresh_token: 'new-rt', expires_at: FUTURE_EPOCH_S })
	);
	try {
		const { refreshed } = await refreshExpiringStravaTokens(supabase);
		assertEquals(refreshed, 1);

		const cas = rpcCalls.find((c) => c.name === 'set_integration_tokens_cas');
		assert(cas, 'expected set_integration_tokens_cas to be called');
		// The CAS is keyed on the refresh token that was READ before the Strava
		// call — that is the compare-and-swap guard.
		assertEquals(cas.args.p_expected_refresh_token, 'stale-rt');
		assertEquals(cas.args.p_refresh_token, 'new-rt');

		// The unconditional, non-CAS setter must never be used.
		assert(
			!rpcCalls.some((c) => c.name === 'set_integration_tokens'),
			'set_integration_tokens (non-CAS) must not be called',
		);

		assertEquals(vault.refresh_token, 'new-rt');
	} finally {
		restore();
	}
});

Deno.test('CAS keeps the winner: a stale-token refresh cannot clobber the rotated pair', async () => {
	// Two refreshes both read the same stale refresh token, then race to write.
	const { supabase, vault } = makeMock({
		expiring: [],
		vault: { refresh_token: 'stale-rt', access_token: 'old-at', token_expiry: 'x' },
	});

	// Winner rotates stale-rt -> winner-rt.
	const restoreA = stubFetch(() =>
		Response.json({ access_token: 'winner-at', refresh_token: 'winner-rt', expires_at: FUTURE_EPOCH_S })
	);
	const winnerAccess = await refreshStravaToken(supabase, 'u1', 'stale-rt');
	restoreA();
	assertEquals(winnerAccess, 'winner-at');
	assertEquals(vault.refresh_token, 'winner-rt');

	// Loser also read stale-rt (before the rotation) and now tries to write.
	// Its CAS expected-token no longer matches, so it must NOT overwrite.
	const restoreB = stubFetch(() =>
		Response.json({ access_token: 'loser-at', refresh_token: 'loser-rt', expires_at: FUTURE_EPOCH_S })
	);
	const loserAccess = await refreshStravaToken(supabase, 'u1', 'stale-rt');
	restoreB();
	// Strava still issued a token for the loser, so the access token is returned,
	// but the vault holds the CAS winner's pair, not whichever finished last.
	assertEquals(loserAccess, 'loser-at');
	assertEquals(vault.refresh_token, 'winner-rt');
	assertEquals(vault.access_token, 'winner-at');
});

Deno.test('4xx on refresh stamps disconnected via the wired callback, no CAS write', async () => {
	const { supabase, rpcCalls, updates } = makeMock({
		expiring: [{ id: 'i1', user_id: 'u1' }],
		vault: { refresh_token: 'stale-rt', access_token: 'old-at', token_expiry: 'x' },
	});
	const restore = stubFetch(() =>
		Response.json({ error: 'invalid_grant' }, { status: 400 })
	);
	try {
		const { refreshed } = await refreshExpiringStravaTokens(supabase);
		assertEquals(refreshed, 0);
		assertEquals(updates.length, 1);
		assertEquals(updates[0].payload.disconnected_reason, 'invalid_grant');
		assert(typeof updates[0].payload.disconnected_at === 'string');
		assert(
			!rpcCalls.some((c) => c.name.startsWith('set_integration_tokens')),
			'no token write on a dead grant',
		);
	} finally {
		restore();
	}
});

Deno.test('other 4xx classifies as unauthorized', async () => {
	const { supabase, updates } = makeMock({
		expiring: [{ id: 'i1', user_id: 'u1' }],
		vault: { refresh_token: 'stale-rt', access_token: 'old-at', token_expiry: 'x' },
	});
	const restore = stubFetch(() => new Response('nope', { status: 401 }));
	try {
		await refreshExpiringStravaTokens(supabase);
		assertEquals(updates.length, 1);
		assertEquals(updates[0].payload.disconnected_reason, 'unauthorized');
	} finally {
		restore();
	}
});

Deno.test('5xx is transient: no disconnect, no token write', async () => {
	const { supabase, rpcCalls, updates } = makeMock({
		expiring: [{ id: 'i1', user_id: 'u1' }],
		vault: { refresh_token: 'stale-rt', access_token: 'old-at', token_expiry: 'x' },
	});
	const restore = stubFetch(() => new Response('boom', { status: 503 }));
	try {
		const { refreshed } = await refreshExpiringStravaTokens(supabase);
		assertEquals(refreshed, 0);
		assertEquals(updates.length, 0);
		assert(!rpcCalls.some((c) => c.name.startsWith('set_integration_tokens')));
	} finally {
		restore();
	}
});
