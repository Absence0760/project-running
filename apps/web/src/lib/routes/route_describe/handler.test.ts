// Unit tests for the pre-Supabase early-return paths in
// handleRouteDescribe. Run via
// `npx tsx --test apps/web/src/lib/routes/route_describe/handler.test.ts`.
//
// Like the coach handler, this short-circuits on two branches BEFORE
// it ever instantiates a Supabase client or calls Anthropic:
//   - 400 when the body has no numeric distance_m (unparseable input)
//   - 401 when there's no Authorization header
// Those are mock-free. The downstream branches (auth.getUser, is_pro
// RPC, the Anthropic call, the templated fallback on each failure mode)
// need a real local Supabase + the Pro/free dev accounts and are
// exercised by the Playwright spec in
// `tests-e2e/routes/route-describe.spec.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handleRouteDescribe, MAX_ROUTE_NAME_CHARS } from './handler';
import type { RouteDescribeConfig } from './handler';

function baseConfig(): RouteDescribeConfig {
	return {
		anthropicApiKey: 'sk-ant-test-FAKE-KEY-NEVER-USED',
		publicSupabaseUrl: 'http://127.0.0.1:54321',
		publicSupabaseAnonKey: 'sb_publishable_fake_local_anon_key',
		bypassPaywallEnabled: false,
	};
}

function parse(result: Awaited<ReturnType<typeof handleRouteDescribe>>): {
	status: number;
	body: { error?: string; description?: string; source?: string; upgrade?: boolean };
} {
	return { status: result.status, body: JSON.parse(result.body) };
}

test('returns 400 when the body is not an object', async () => {
	const r = parse(await handleRouteDescribe('Bearer x', null, baseConfig()));
	assert.equal(r.status, 400);
	assert.equal(r.body.error, 'invalid route input');
});

test('returns 400 when distance_m is missing or non-numeric', async () => {
	const r1 = parse(await handleRouteDescribe('Bearer x', { name: 'x' }, baseConfig()));
	assert.equal(r1.status, 400);
	const r2 = parse(
		await handleRouteDescribe('Bearer x', { name: 'x', distance_m: '10000' }, baseConfig()),
	);
	assert.equal(r2.status, 400);
});

test('returns 401 when there is no auth header (body is otherwise valid)', async () => {
	const r = parse(
		await handleRouteDescribe(null, { name: 'Park loop', distance_m: 5000 }, baseConfig()),
	);
	assert.equal(r.status, 401);
	assert.equal(r.body.error, 'not authenticated');
});

test('returns 401 for an empty Bearer token', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer ', { name: 'x', distance_m: 5000 }, baseConfig()),
	);
	assert.equal(r.status, 401);
});

test('input parse accepts a valid route shape (no early 400) — fails later on auth', async () => {
	// A fully-formed body must NOT 400; it should fall through to the
	// auth check (401 here, since the fake token can't resolve a user
	// against the unreachable local stack — but the point is it's past
	// input validation, returning 401 not 400).
	const r = parse(
		await handleRouteDescribe(
			null,
			{
				name: 'Riverside 10K',
				distance_m: 10000,
				elevation_m: 150,
				surface: 'mixed',
				start: { lat: 51.5, lng: -0.12 },
				end: { lat: 51.5, lng: -0.12 },
			},
			baseConfig(),
		),
	);
	assert.equal(r.status, 401);
});

test('MAX_ROUTE_NAME_CHARS is a sane cap', () => {
	// Guards against an accidental 0 / negative that would blank every
	// name. Not a behavioural assertion on the handler, but pins the
	// constant the prompt-injection guard depends on.
	assert.ok(MAX_ROUTE_NAME_CHARS >= 100 && MAX_ROUTE_NAME_CHARS <= 1000);
});
