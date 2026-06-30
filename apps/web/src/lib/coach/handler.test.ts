// Unit tests for the pre-Supabase early-return paths in handleCoach.
// Run via `npx tsx --test apps/web/src/lib/coach/handler.test.ts`.
//
// `handleCoach` short-circuits on four error paths BEFORE it ever
// instantiates a Supabase client or calls a provider stream. Those
// branches are 100% testable without any mocks — construct a config
// + bad input and assert the JSON envelope. The downstream branches
// (auth.getUser, is_pro RPC, provider stream) are exercised by the
// e2e mocked-route tests in `tests-e2e/coach/page.spec.ts` and would
// need a heavy DI refactor to unit-test (no plans to do that today).
//
// What this file covers:
//   - 503 when provider=anthropic + no API key
//   - 401 when no Authorization header
//   - 400 when body isn't a parsed JSON object
//   - 400 when body.messages is empty / oversized / malformed
// What it deliberately doesn't cover:
//   - Anything past line 87 of handler.ts (supabase.auth.getUser).
//     Those paths need either a refactor to accept an injected
//     Supabase client OR a real local Supabase + network — out of
//     scope for a unit test.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handleCoach } from './handler';
import type { CoachConfig } from './types';

/// Run `fn` with console.error captured, returning every line emitted.
/// Used to assert the bypass-paywall alarm log without a real Supabase
/// (the tagged line fires in the pre-Supabase branch of handleCoach).
async function captureConsoleError(fn: () => Promise<unknown>): Promise<string[]> {
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

/// A minimal valid config for the Anthropic happy path. Each test
/// shallow-overrides the field it's exercising.
function baseConfig(): CoachConfig {
	return {
		provider: 'anthropic',
		anthropicApiKey: 'sk-ant-test-FAKE-KEY-NEVER-USED',
		publicSupabaseUrl: 'http://127.0.0.1:54321',
		publicSupabaseAnonKey: 'sb_publishable_fake_local_anon_key',
		bypassPaywallEnabled: false,
	};
}

/// Parse a `kind: 'json'` CoachResult body. The body is a JSON
/// string by contract — tests need the parsed shape.
function parseJsonResult(result: Awaited<ReturnType<typeof handleCoach>>): {
	status: number;
	body: { error?: string; [k: string]: unknown };
} {
	if (result.kind !== 'json') {
		throw new Error(`expected JSON result, got kind=${result.kind}`);
	}
	return { status: result.status, body: JSON.parse(result.body) };
}

// ──────────────────────── 503 ────────────────────────

test('returns 503 when provider=anthropic but anthropicApiKey is unset', async () => {
	// Reason: the handler refuses to construct an Anthropic client
	// without an API key — without this gate the provider stream
	// would throw mid-pipeline + leak the failure as a 500. The 503
	// is the operator signal "the deployment is misconfigured".
	const result = await handleCoach('Bearer fake-token', { messages: [] }, {
		...baseConfig(),
		anthropicApiKey: undefined,
	});
	const { status, body } = parseJsonResult(result);
	assert.equal(status, 503);
	assert.match(body.error as string, /not configured/i);
});

test('503 message does NOT leak the COACH_PROVIDER value to the wire', async () => {
	// Reason: security_guards.test.ts pins that the 503 doesn't
	// interpolate the provider name (that's an operator hint that
	// goes to console.error). The contract is "the wire sees a
	// generic 'not configured'; the operator reads the logs". Pin
	// the wire shape so a future copy-edit can't slip the leak back.
	const result = await handleCoach('Bearer fake-token', { messages: [] }, {
		...baseConfig(),
		anthropicApiKey: undefined,
	});
	const { body } = parseJsonResult(result);
	const errStr = String(body.error ?? '');
	assert.doesNotMatch(errStr, /anthropic/i);
	assert.doesNotMatch(errStr, /openai/i);
	assert.doesNotMatch(errStr, /\bprovider\b/i);
});

test('does NOT 503 when provider=openai + no anthropicApiKey (separate gate)', async () => {
	// Reason: the 503 gate is anthropic-specific. An openai-provider
	// deployment without an anthropicApiKey is valid (local Ollama
	// setup, for instance). It MUST fall through to the next gate
	// (401 for the missing auth header), not 503.
	const result = await handleCoach(null, { messages: [] }, {
		...baseConfig(),
		provider: 'openai',
		anthropicApiKey: undefined,
		openaiBaseUrl: 'http://127.0.0.1:11434/v1',
		openaiApiKey: 'ollama',
		openaiModel: 'llama3',
	});
	const { status } = parseJsonResult(result);
	assert.equal(status, 401, '503 must not fire for openai providers');
});

// ──────────────────────── 401 ────────────────────────

test('returns 401 when the Authorization header is null', async () => {
	// Reason: every request must carry a Bearer JWT — `parseAuthHeader`
	// returns null on missing/empty/non-Bearer input and the handler
	// short-circuits without ever calling Supabase. A regression that
	// allowed null through would attempt a Supabase call with an
	// undefined token, get an auth error, and surface a different
	// (more leaky) code path.
	const result = await handleCoach(null, { messages: [] }, baseConfig());
	const { status, body } = parseJsonResult(result);
	assert.equal(status, 401);
	assert.equal(body.error, 'not authenticated');
});

test('returns 401 when Authorization is empty / non-Bearer', async () => {
	// The parseAuthHeader helper has its own unit tests (case-
	// insensitive, bare "Bearer ", etc.) — this pins the integration
	// with handleCoach so a swap to a different parser would surface.
	for (const bad of ['', 'Basic abc', 'Bearer ', 'Token xyz']) {
		const result = await handleCoach(bad, { messages: [] }, baseConfig());
		const { status } = parseJsonResult(result);
		assert.equal(status, 401, `expected 401 for "${bad}"`);
	}
});

test('401 wire message is the static "not authenticated" string', async () => {
	// Reason: security_guards.test.ts pins this so the GoTrue
	// internal-identifier oracle stays closed. Reverify here for
	// the no-token path specifically — a different upstream string
	// would change the wire shape clients depend on.
	const result = await handleCoach(null, { messages: [] }, baseConfig());
	const { body } = parseJsonResult(result);
	assert.equal(body.error, 'not authenticated');
	// And nothing else interesting — no internal identifiers, no
	// JWT-shape oracles.
	assert.doesNotMatch(String(body.error), /eyJ|jwt|token/i);
});

// ──────────── bypass-paywall alarm log (CloudWatch metric filter) ───

test('bypassPaywallEnabled=true emits the bypass_paywall_active alarm log line', async () => {
	// Reason: the prod CloudWatch metric-filter alarm `coach-bypass-
	// paywall-active` (alarms.tf) keys on this exact tagged line — a
	// single hit in production fires PagerDuty because it means the
	// daily-cap + cost gates are off (a billing emergency). The line is
	// emitted in the pre-Supabase branch, so a no-auth call (which 401s
	// before any Supabase client is built) still exercises it. Pin the
	// tag so a copy-edit can't silently break the alarm's trigger string.
	// The metric filter (alarms.tf) matches the literal "[coach]
	// bypass_paywall_active", so pin the prefix too — dropping it would
	// leave the alarm armed but never firing.
	const lines = await captureConsoleError(() =>
		handleCoach(null, { messages: [] }, { ...baseConfig(), bypassPaywallEnabled: true }),
	);
	assert.ok(
		lines.some((l) => l.includes('[coach] bypass_paywall_active')),
		`expected a "[coach] bypass_paywall_active" log line, got: ${JSON.stringify(lines)}`,
	);
});

test('bypassPaywallEnabled=false does NOT emit the bypass_paywall_active line', async () => {
	// The alarm must only fire when the bypass is genuinely on — the
	// off path (the production default) must stay silent, or the alarm
	// would page on every normal request.
	const lines = await captureConsoleError(() =>
		handleCoach(null, { messages: [] }, { ...baseConfig(), bypassPaywallEnabled: false }),
	);
	assert.ok(
		!lines.some((l) => l.includes('bypass_paywall_active')),
		`bypass-off must not log the alarm tag, got: ${JSON.stringify(lines)}`,
	);
});

// ──────────────────────── 400 (body shape) ────────────────────────

test('returns 400 when rawBody is null', async () => {
	const result = await handleCoach('Bearer x', null, baseConfig());
	const { status, body } = parseJsonResult(result);
	assert.equal(status, 400);
	assert.equal(body.error, 'invalid JSON');
});

test('returns 400 when rawBody is a primitive (string, number, boolean)', async () => {
	for (const bad of ['hello', 42, true, false]) {
		const result = await handleCoach('Bearer x', bad, baseConfig());
		const { status } = parseJsonResult(result);
		assert.equal(status, 400, `expected 400 for ${typeof bad}: ${bad}`);
	}
});

test('returns 400 when body.messages is invalid (missing, wrong shape)', async () => {
	// `validateCoachMessages` has its own unit tests in limits.test.ts;
	// this confirms a failed validation surfaces as 400 from the
	// handler rather than crashing the request pipeline.
	for (const bad of [
		{},                         // missing messages key
		{ messages: 'not-array' },  // wrong type
		{ messages: null },         // wrong type
	]) {
		const result = await handleCoach('Bearer x', bad, baseConfig());
		const { status, body } = parseJsonResult(result);
		assert.equal(status, 400, `expected 400 for ${JSON.stringify(bad)}`);
		assert.equal(body.error, 'invalid messages');
	}
});

test('returns 400 with the canonical jsonError shape (kind + content-type)', async () => {
	// Reason: the production Lambda wrapper relies on `kind: 'json'`
	// + `headers['content-type']` to set the response shape. A
	// regression that dropped either would make CloudFront forward
	// an unset Content-Type + the Lambda wrapper would mis-route
	// the response, breaking the client's error-banner rendering
	// (which expects to JSON.parse the body).
	// 401-check fires before the 400 on body shape; pass a valid-shaped
	// Bearer header so we hit the body-shape branch.
	const result = await handleCoach('Bearer x', null, baseConfig());
	if (result.kind !== 'json') {
		assert.fail(`expected json result, got ${result.kind}`);
	}
	assert.equal(result.headers['content-type'], 'application/json');
	assert.equal(result.status, 400);
});
