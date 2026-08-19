import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { SupabaseClient } from '@supabase/supabase-js';

import { lookupSharedWorkout } from './share_workout_lookup';

const WORKOUT_ID = '11111111-2222-4333-8444-555555555555';
const config = { supabaseUrl: 'http://localhost', supabaseAnonKey: 'anon' };

interface FakeOpts {
	workout?: unknown;
	workoutError?: unknown;
	sets?: unknown;
	setsError?: unknown;
}

function fakeClient(opts: FakeOpts): SupabaseClient {
	return {
		from(table: string) {
			return {
				select() {
					if (table === 'public_gym_workouts') {
						return {
							eq() {
								return {
									eq() {
										return {
											maybeSingle: async () => ({
												data: opts.workout ?? null,
												error: opts.workoutError ?? null,
											}),
										};
									},
								};
							},
						};
					}
					return {
						eq() {
							return {
								order: async () => ({
									data: opts.sets ?? [],
									error: opts.setsError ?? null,
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

const WORKOUT = {
	id: WORKOUT_ID,
	user_id: null,
	title: 'Push day',
	started_at: '2026-08-01T06:00:00Z',
	set_count: 12,
	volume_kg: 4200,
	is_public: true,
};

test('a clean not-found stays silent', async () => {
	const lines = await captureErrors(() =>
		lookupSharedWorkout(WORKOUT_ID, config, () => fakeClient({ workout: null })),
	);
	assert.deepEqual(lines, []);
});

test('a workout-query error surfaces the tagged upstream line', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedWorkout>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedWorkout(WORKOUT_ID, config, () =>
			fakeClient({ workoutError: { message: 'upstream connect error' } }),
		);
	});
	assert.equal(result?.workout, null);
	assert.deepEqual(lines, ['[share-workout] upstream_unreachable']);
});

test('a sets error surfaces the tagged line rather than a hollow page', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedWorkout>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedWorkout(WORKOUT_ID, config, () =>
			fakeClient({ workout: WORKOUT, setsError: { message: 'upstream connect error' } }),
		);
	});
	assert.equal(result?.workout, null);
	assert.deepEqual(lines, ['[share-workout] upstream_unreachable']);
});

test('a thrown fetch surfaces the tagged line', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedWorkout>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedWorkout(WORKOUT_ID, config, () => {
			throw new Error('fetch failed');
		});
	});
	assert.equal(result?.workout, null);
	assert.equal(lines.length, 1);
	assert.match(lines[0], /^\[share-workout\] upstream_unreachable/);
});

test('a non-uuid id is a clean not-found, never an alarm', async () => {
	const lines = await captureErrors(() =>
		lookupSharedWorkout('hello', config, () => {
			throw new Error('should not have queried');
		}),
	);
	assert.deepEqual(lines, []);
});
