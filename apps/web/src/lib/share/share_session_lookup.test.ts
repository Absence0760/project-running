import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { SupabaseClient } from '@supabase/supabase-js';

import { lookupSharedSession } from './share_session_lookup';

const PLAN_ID = '11111111-2222-4333-8444-555555555555';
const config = { supabaseUrl: 'http://localhost', supabaseAnonKey: 'anon' };

interface FakeOpts {
	plan?: unknown;
	planError?: unknown;
	blocks?: unknown;
	blocksError?: unknown;
	items?: unknown;
	itemsError?: unknown;
}

function fakeClient(opts: FakeOpts): SupabaseClient {
	return {
		from(table: string) {
			return {
				select() {
					if (table === 'session_plans') {
						return {
							eq() {
								return {
									eq() {
										return {
											maybeSingle: async () => ({
												data: opts.plan ?? null,
												error: opts.planError ?? null,
											}),
										};
									},
								};
							},
						};
					}
					const isBlocks = table === 'session_plan_blocks';
					return {
						eq() {
							return {
								order: async () => ({
									data: isBlocks ? (opts.blocks ?? []) : (opts.items ?? []),
									error: isBlocks
										? (opts.blocksError ?? null)
										: (opts.itemsError ?? null),
								}),
							};
						},
					};
				},
			};
		},
		async rpc() {
			return { data: null, error: null };
		},
	} as unknown as SupabaseClient;
}

async function captureErrors(fn: () => Promise<unknown>): Promise<string[]> {
	const lines: string[] = [];
	const original = console.error;
	console.error = (...args: unknown[]) => {
		lines.push(args.map((a) => String(a)).join(' '));
	};
	try {
		await fn();
	} finally {
		console.error = original;
	}
	return lines;
}

const PLAN = {
	id: PLAN_ID,
	author_id: null,
	title: 'Morning flow',
	discipline: 'yoga',
	equipment: null,
	est_duration_min: 30,
	is_public: true,
};

test('a clean not-found stays silent', async () => {
	const lines = await captureErrors(() =>
		lookupSharedSession(PLAN_ID, config, () => fakeClient({ plan: null })),
	);
	assert.deepEqual(lines, []);
});

test('a plan-query error surfaces the tagged upstream line', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedSession>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedSession(PLAN_ID, config, () =>
			fakeClient({ planError: { message: 'upstream connect error' } }),
		);
	});
	assert.equal(result?.session, null);
	assert.deepEqual(lines, ['[share-session] upstream_unreachable']);
});

test('a blocks/items error surfaces the tagged line rather than a hollow page', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedSession>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedSession(PLAN_ID, config, () =>
			fakeClient({ plan: PLAN, itemsError: { message: 'upstream connect error' } }),
		);
	});
	assert.equal(result?.session, null);
	assert.deepEqual(lines, ['[share-session] upstream_unreachable']);
});

test('a thrown fetch surfaces the tagged line', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedSession>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedSession(PLAN_ID, config, () => {
			throw new Error('fetch failed');
		});
	});
	assert.equal(result?.session, null);
	assert.equal(lines.length, 1);
	assert.match(lines[0], /^\[share-session\] upstream_unreachable/);
});

test('a non-uuid id is a clean not-found, never an alarm', async () => {
	const lines = await captureErrors(() =>
		lookupSharedSession('hello', config, () => {
			throw new Error('should not have queried');
		}),
	);
	assert.deepEqual(lines, []);
});
