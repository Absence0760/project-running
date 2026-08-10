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
	body: {
		error?: string;
		description?: string;
		source?: string;
		upgrade?: boolean;
		code?: string;
		required_version?: number;
	};
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

// ─────────────── AI-disclosure consent gate (issue #734) ───────────────

/// Minimal Supabase stand-in: enough for auth.getUser + the two RPCs the
/// gates read. Injected through `config.createClient`, which exists so the
/// post-auth branches are reachable without a live stack.
function stubClient(profileRow: unknown, opts: { isPro?: boolean; profileError?: unknown } = {}) {
	return () =>
		({
			auth: {
				getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }),
			},
			rpc: (name: string) => {
				if (name === 'get_my_profile') {
					return {
						maybeSingle: async () => ({
							data: profileRow,
							error: opts.profileError ?? null,
						}),
					};
				}
				return Promise.resolve({ data: opts.isPro === true, error: null });
			},
		}) as never;
}

const ACCEPTED_AT = '2026-01-01T00:00:00Z';
const VALID_BODY = { name: 'Riverside 10K', distance_m: 10000 };

test('refuses a caller who accepted only the Coach disclosure', async () => {
	// Reason: issue #734. route-describe ships the route name + stats to
	// Anthropic, which the v1 Coach copy never described. A v1 acceptance
	// must not be read as covering it.
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: 1, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
	assert.equal(r.body.required_version, 2);
	// Layered resilience: the templated baseline still rides along.
	assert.equal(r.body.source, 'template');
	assert.ok((r.body.description ?? '').length > 0);
});

test('refuses a caller with no consent record at all', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: null, coach_consent_at: null }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});

test('refuses a version this build does not know — fail closed, never grant', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: 99, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});

test('an unreadable consent record is a 500, not a silent pass', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient(null, { profileError: { code: '42501', message: 'denied' } }),
		}),
	);
	assert.equal(r.status, 500);
	assert.equal(r.body.error, 'consent check failed');
	assert.equal(r.body.source, 'template');
});

test('the widened acceptance clears the consent gate — the tier gate is what answers next', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient(
				{ ai_disclosure_version: 2, coach_consent_at: ACCEPTED_AT },
				{ isPro: false },
			),
		}),
	);
	assert.equal(r.status, 200);
	assert.equal(r.body.upgrade, true);
	assert.equal(r.body.code, undefined);
});

test('the dev paywall bypass does not bypass the consent gate', async () => {
	// Reason: BYPASS_PAYWALL exists to skip a billing check in local dev.
	// A lawful basis for sending a real person's data to a real
	// sub-processor is not a billing check.
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			bypassPaywallEnabled: true,
			createClient: stubClient({ ai_disclosure_version: 1, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});
