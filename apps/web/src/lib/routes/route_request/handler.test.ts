// Unit tests for the pre-Supabase early-return paths in
// handleRouteRequest. Run via
// `npx tsx --test apps/web/src/lib/routes/route_request/handler.test.ts`.
//
// Like the route-describe + coach handlers, this short-circuits on two
// branches BEFORE it instantiates a Supabase client or calls Anthropic:
//   - 400 when the body has no usable `request` string
//   - 401 when there's no Authorization header
// Those are mock-free. The downstream branches (auth.getUser, is_pro
// gate, the forced-tool Anthropic call, the validate/clamp of the
// returned constraints) need a real local Supabase + the Pro/free dev
// accounts and are exercised by the Playwright spec
// `tests-e2e/routes/route-request.spec.ts`. The validate/clamp logic
// itself — the security-critical trust boundary — is unit-tested
// exhaustively in `constraints.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handleRouteRequest, MAX_REQUEST_TEXT_CHARS } from './handler';
import type { RouteRequestConfig } from './handler';

function baseConfig(): RouteRequestConfig {
	return {
		anthropicApiKey: 'sk-ant-test-FAKE-KEY-NEVER-USED',
		publicSupabaseUrl: 'http://127.0.0.1:54321',
		publicSupabaseAnonKey: 'sb_publishable_fake_local_anon_key',
		bypassPaywallEnabled: false,
	};
}

function parse(result: Awaited<ReturnType<typeof handleRouteRequest>>): {
	status: number;
	body: { error?: string; upgrade?: boolean; constraints?: unknown };
} {
	return { status: result.status, body: JSON.parse(result.body) };
}

test('returns 400 when the body is not an object', async () => {
	const r = parse(await handleRouteRequest('Bearer x', null, baseConfig()));
	assert.equal(r.status, 400);
	assert.equal(r.body.error, 'invalid route request');
});

test('returns 400 when `request` is missing or non-string', async () => {
	const r1 = parse(await handleRouteRequest('Bearer x', {}, baseConfig()));
	assert.equal(r1.status, 400);
	const r2 = parse(await handleRouteRequest('Bearer x', { request: 123 }, baseConfig()));
	assert.equal(r2.status, 400);
});

test('returns 400 when `request` is empty / whitespace only', async () => {
	const r = parse(await handleRouteRequest('Bearer x', { request: '   ' }, baseConfig()));
	assert.equal(r.status, 400);
});

test('returns 401 when there is no auth header (body is otherwise valid)', async () => {
	const r = parse(
		await handleRouteRequest(null, { request: 'a flat 10k loop' }, baseConfig()),
	);
	assert.equal(r.status, 401);
	assert.equal(r.body.error, 'not authenticated');
});

test('returns 401 for an empty Bearer token', async () => {
	const r = parse(
		await handleRouteRequest('Bearer ', { request: 'a flat 10k loop' }, baseConfig()),
	);
	assert.equal(r.status, 401);
});

test('a valid request shape passes input validation (no 400) — fails later on auth', async () => {
	// A fully-formed body must NOT 400; it should fall through to the auth
	// check (401 here, since the fake token can't resolve a user against
	// the unreachable local stack). The point is it's past input
	// validation.
	const r = parse(
		await handleRouteRequest(
			null,
			{ request: 'a quiet 5k avoiding main roads', location_label: 'Boston, MA' },
			baseConfig(),
		),
	);
	assert.equal(r.status, 401);
});

test('MAX_REQUEST_TEXT_CHARS is a sane cap', () => {
	assert.ok(MAX_REQUEST_TEXT_CHARS >= 200 && MAX_REQUEST_TEXT_CHARS <= 2000);
});
