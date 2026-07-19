import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { SupabaseClient } from '@supabase/supabase-js';

import { checkRouteRateLimit } from './rate_limit';

/// Minimal fake that records the `check_rate_limit` RPC args and returns
/// a scripted `{ data, error }`. Only `.rpc` is exercised by the helper.
function fakeClient(
	respond: (args: Record<string, unknown>) => { data: unknown; error: unknown },
): { client: SupabaseClient; calls: Record<string, unknown>[] } {
	const calls: Record<string, unknown>[] = [];
	const client = {
		rpc: async (_fn: string, args: Record<string, unknown>) => {
			calls.push(args);
			return respond(args);
		},
	} as unknown as SupabaseClient;
	return { client, calls };
}

test('checkRouteRateLimit passes the caller id + bucket + window to the RPC', async () => {
	const { client, calls } = fakeClient(() => ({ data: [{ allowed: true }], error: null }));
	const v = await checkRouteRateLimit(client, 'user-1', 'generate-route', 60, 3600);
	assert.equal(v, 'ok');
	assert.deepEqual(calls[0], {
		p_user_id: 'user-1',
		p_bucket: 'generate-route',
		p_max: 60,
		p_window_seconds: 3600,
	});
});

test('checkRouteRateLimit denies once the per-user ceiling is passed', async () => {
	// Simulate the SECURITY DEFINER counter: allowed while count <= max,
	// denied after. The helper must flip to 'limited' on the (max+1)th call.
	const MAX = 3;
	let count = 0;
	const { client } = fakeClient(() => {
		count += 1;
		return { data: [{ allowed: count <= MAX, retry_after_seconds: count <= MAX ? 0 : 42 }], error: null };
	});

	const verdicts: string[] = [];
	for (let i = 0; i < MAX + 2; i++) {
		verdicts.push(await checkRouteRateLimit(client, 'user-1', 'generate-route', MAX, 3600));
	}
	assert.deepEqual(verdicts, ['ok', 'ok', 'ok', 'limited', 'limited']);
});

test('checkRouteRateLimit fails closed on an RPC error', async () => {
	const { client } = fakeClient(() => ({ data: null, error: { message: 'db down' } }));
	assert.equal(await checkRouteRateLimit(client, 'user-1', 'osrm-proxy', 1200, 3600), 'error');
});

test('checkRouteRateLimit fails closed on a malformed / empty result row', async () => {
	const empty = fakeClient(() => ({ data: [], error: null }));
	assert.equal(await checkRouteRateLimit(empty.client, 'u', 'osrm-proxy', 10, 3600), 'error');

	const notArray = fakeClient(() => ({ data: { allowed: true }, error: null }));
	assert.equal(await checkRouteRateLimit(notArray.client, 'u', 'osrm-proxy', 10, 3600), 'error');
});

test('checkRouteRateLimit treats a non-true allowed field as limited (fail-closed shape)', async () => {
	// A row that isn't a genuine `allowed: true` must never be read as ok —
	// a missing/garbled field is a denial, not a grant.
	const missing = fakeClient(() => ({ data: [{ retry_after_seconds: 5 }], error: null }));
	assert.equal(await checkRouteRateLimit(missing.client, 'u', 'osrm-proxy', 10, 3600), 'limited');

	const stringy = fakeClient(() => ({ data: [{ allowed: 'true' }], error: null }));
	assert.equal(await checkRouteRateLimit(stringy.client, 'u', 'osrm-proxy', 10, 3600), 'limited');
});
