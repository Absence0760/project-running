import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { SupabaseClient } from '@supabase/supabase-js';

import { lookupSharedRoute } from './share_route_lookup';

const config = { supabaseUrl: 'http://localhost', supabaseAnonKey: 'anon' };

type RpcCall = { fn: string; args: unknown };

function fakeClient(opts: {
	route: unknown;
	routeError?: unknown;
	rpcData?: unknown;
	rpcCalls: RpcCall[];
}): SupabaseClient {
	return {
		from() {
			return {
				select() {
					return {
						eq() {
							return {
								maybeSingle: async () => ({
									data: opts.route,
									error: opts.routeError ?? null,
								}),
							};
						},
					};
				},
			};
		},
		async rpc(fn: string, args: unknown) {
			opts.rpcCalls.push({ fn, args });
			return { data: opts.rpcData ?? null, error: null };
		},
	} as unknown as SupabaseClient;
}

test('withTrack calls clip_route_for_viewer (not clip_track_for_user) with p_route_id', async () => {
	const rpcCalls: RpcCall[] = [];
	const route = { id: 'r1', name: 'Loop', distance_m: 5000, surface: 'road', elevation_m: 40 };
	await lookupSharedRoute('r1', config, { withTrack: true }, () =>
		fakeClient({ route, rpcData: [], rpcCalls }),
	);
	assert.equal(rpcCalls.length, 1);
	assert.equal(rpcCalls[0].fn, 'clip_route_for_viewer');
	assert.deepEqual(rpcCalls[0].args, { p_route_id: 'r1' });
});

test('clipped points flow through into the returned track', async () => {
	const rpcCalls: RpcCall[] = [];
	const route = { id: 'r1', name: 'Loop', distance_m: 5000, surface: 'road', elevation_m: 40 };
	const points = [
		{ lat: 1, lng: 2 },
		{ lat: 3, lng: 4 },
	];
	const result = await lookupSharedRoute('r1', config, { withTrack: true }, () =>
		fakeClient({ route, rpcData: points, rpcCalls }),
	);
	assert.deepEqual(result.track, points);
	assert.equal(result.route?.id, 'r1');
});

test('withTrack: false skips the clip RPC entirely', async () => {
	const rpcCalls: RpcCall[] = [];
	const route = { id: 'r1', name: 'Loop', distance_m: 5000, surface: 'road', elevation_m: 40 };
	const result = await lookupSharedRoute('r1', config, { withTrack: false }, () =>
		fakeClient({ route, rpcCalls }),
	);
	assert.equal(rpcCalls.length, 0);
	assert.deepEqual(result.track, []);
	assert.equal(result.route?.id, 'r1');
});

test('a non-array clip result degrades to an empty track', async () => {
	const rpcCalls: RpcCall[] = [];
	const route = { id: 'r1', name: 'Loop', distance_m: 5000, surface: 'road', elevation_m: 40 };
	const result = await lookupSharedRoute('r1', config, { withTrack: true }, () =>
		fakeClient({ route, rpcData: null, rpcCalls }),
	);
	assert.equal(rpcCalls[0].fn, 'clip_route_for_viewer');
	assert.deepEqual(result.track, []);
});
