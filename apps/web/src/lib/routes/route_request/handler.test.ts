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

import { EXTRACT_TOOL, handleRouteRequest, MAX_REQUEST_TEXT_CHARS } from './handler';
import type { RouteRequestConfig } from './handler';
import { validateConstraints } from './constraints';

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
	body: {
		error?: string;
		upgrade?: boolean;
		constraints?: unknown;
		code?: string;
		required_version?: number;
	};
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

test('every preference the tool advertises is one the validator accepts', () => {
	// The schema is what the model is told it may emit; `validateConstraints`
	// is what survives the trust boundary. A value on only the schema side is
	// silently dropped after being billed for — the runner asks for a scenic
	// route, the model complies, and the generator never hears about it.
	const props = EXTRACT_TOOL.input_schema.properties as Record<
		string,
		{ enum?: string[] }
	>;
	const advertised = props.preference?.enum;
	assert.ok(Array.isArray(advertised) && advertised.length > 0);
	for (const p of advertised) {
		assert.equal(validateConstraints({ preference: p }).preference, p);
	}
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
const VALID_REQUEST = { request: 'a flat 10k loop', location_label: 'Boston, MA' };

test('refuses a caller who accepted only the Coach disclosure', async () => {
	// Reason: issue #734. This endpoint ships the typed request AND the
	// location label to Anthropic — neither is in the v1 Coach copy.
	const r = parse(
		await handleRouteRequest('Bearer x', VALID_REQUEST, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: 1, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
	assert.equal(r.body.required_version, 2);
	// Not the paywall upsell — the client must not show "upgrade to Pro"
	// to someone whose problem is a missing consent record.
	assert.equal(r.body.upgrade, undefined);
});

test('refuses a caller with no consent record at all', async () => {
	const r = parse(
		await handleRouteRequest('Bearer x', VALID_REQUEST, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: null, coach_consent_at: null }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});

test('refuses a version this build does not know — fail closed, never grant', async () => {
	const r = parse(
		await handleRouteRequest('Bearer x', VALID_REQUEST, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: 99, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});

test('an unreadable consent record is a 500, not a silent pass', async () => {
	const r = parse(
		await handleRouteRequest('Bearer x', VALID_REQUEST, {
			...baseConfig(),
			createClient: stubClient(null, { profileError: { code: '42501', message: 'denied' } }),
		}),
	);
	assert.equal(r.status, 500);
	assert.equal(r.body.error, 'consent check failed');
});

test('the widened acceptance clears the consent gate — the tier gate is what answers next', async () => {
	const r = parse(
		await handleRouteRequest('Bearer x', VALID_REQUEST, {
			...baseConfig(),
			createClient: stubClient(
				{ ai_disclosure_version: 2, coach_consent_at: ACCEPTED_AT },
				{ isPro: false },
			),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.error, 'pro required');
	assert.equal(r.body.upgrade, true);
	assert.equal(r.body.code, undefined);
});

test('the dev paywall bypass does not bypass the consent gate', async () => {
	// Reason: BYPASS_PAYWALL exists to skip a billing check in local dev.
	// A lawful basis for sending a real person's data to a real
	// sub-processor is not a billing check.
	const r = parse(
		await handleRouteRequest('Bearer x', VALID_REQUEST, {
			...baseConfig(),
			bypassPaywallEnabled: true,
			createClient: stubClient({ ai_disclosure_version: 1, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});
