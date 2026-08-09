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

import type { SupabaseClient } from '@supabase/supabase-js';

import { coachSseStream, handleCoach, supabaseErrorFields, type CoachStreamDeps } from './handler';
import { emptyUsage, type CoachConfig, type ProviderStream } from './types';

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

// ─────────── supabaseErrorFields (PII-safe error logging) ───────────

test('supabaseErrorFields keeps only code + message, drops details/hint', () => {
	// Reason: the AI-coach path logs Supabase errors on the Art 9
	// health/injury chat flow. A raw PostgrestError carries `.details`
	// and `.hint`, which can echo row fragments (the caller's chat
	// content, emails, injury free text) straight into CloudWatch.
	// This helper is the scrub every log site routes through — pin
	// that it never carries the leaky fields through. /audit/pii-in-logs.
	const raw = {
		code: '23505',
		message: 'duplicate key value violates unique constraint',
		details: "Key (user_id, content)=(uuid, 'left knee ITB flare, DNF at mile 62') already exists.",
		hint: 'runner@example.com',
	};
	const safe = supabaseErrorFields(raw);
	assert.deepEqual(safe, {
		code: '23505',
		message: 'duplicate key value violates unique constraint',
	});
	// The scrubbed object, serialised the way console.error would emit
	// it, must not carry any PII fragment from details/hint.
	const serialised = JSON.stringify(safe);
	assert.doesNotMatch(serialised, /ITB flare/);
	assert.doesNotMatch(serialised, /runner@example\.com/);
	assert.doesNotMatch(serialised, /details|hint/);
});

test('supabaseErrorFields tolerates null / undefined / empty errors', () => {
	assert.deepEqual(supabaseErrorFields(null), { code: undefined, message: undefined });
	assert.deepEqual(supabaseErrorFields(undefined), { code: undefined, message: undefined });
	assert.deepEqual(supabaseErrorFields({}), { code: undefined, message: undefined });
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

// ─────────── regenerate/edit anchor-miss (fail-closed 409) ───────────

/// A chainable Supabase-query-builder stub. Every filter/modifier method
/// returns the builder; the builder is thenable (so a bare `await` on the
/// chain resolves) and `.maybeSingle()` / `.single()` resolve too. Insert /
/// delete calls are recorded on `calls` so a test can assert nothing was
/// written. `coach_messages.maybeSingle()` returns `{ data: null }` — the
/// anchor-miss the fail-closed path must catch.
function makeSupabaseStub(
	calls: { inserts: string[]; deletes: string[] },
	profileOverride?: Record<string, unknown> | null,
) {
	function builder(table: string): Record<string, unknown> {
		const result = { data: null as unknown, error: null };
		const b: Record<string, unknown> = {
			select: () => b,
			eq: () => b,
			is: () => b,
			gte: () => b,
			lte: () => b,
			in: () => b,
			order: () => b,
			limit: () => b,
			insert: () => {
				calls.inserts.push(table);
				return b;
			},
			delete: () => {
				calls.deletes.push(table);
				return b;
			},
			maybeSingle: async () => result,
			single: async () => ({ data: { id: 'new-row-id' }, error: null }),
			then: (resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) =>
				Promise.resolve(result).then(resolve, reject),
		};
		return b;
	}
	return {
		auth: {
			getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }),
		},
		rpc: (name: string) => {
			if (name === 'get_my_profile') {
				return {
					maybeSingle: async () => ({
						data:
							profileOverride === undefined
								? {
										coach_consent_at: '2026-01-01T00:00:00Z',
										ai_disclosure_version: 1,
										display_name: 'Test Runner',
										preferred_unit: 'km',
										health_data_consent_at: null,
									}
								: profileOverride,
						error: null,
					}),
				};
			}
			return Promise.resolve({ data: null, error: null });
		},
		from: (table: string) => builder(table),
	} as unknown as SupabaseClient;
}

test('regenerate with a missing anchor fails closed with 409 and inserts nothing', async () => {
	// Reason: issue #406. When the regenerate/edit anchor lookup returns no
	// row (stale id from a race with another tab, or the row is gone), the
	// old code silently skipped the truncate and still inserted a new user
	// message + streamed a reply — leaving the un-truncated originals beside
	// the new turn (a duplicated history, no error surfaced). The handler now
	// fails closed: a missing anchor returns a 409 BEFORE any insert or
	// stream, and logs `regenerate_anchor_miss` so the miss is operationally
	// visible.
	const calls = { inserts: [] as string[], deletes: [] as string[] };
	const lines = await captureConsoleError(async () => {
		const result = await handleCoach(
			'Bearer fake-token',
			{
				messages: [{ role: 'user', content: 'try again' }],
				mode: 'regenerate',
				anchor_message_id: 'stale-anchor-id',
			},
			{
				...baseConfig(),
				// Bypass the paywall so the is_pro / increment_coach_usage RPCs
				// are skipped — the stub only needs to satisfy auth + consent +
				// buildContext + the anchor lookup.
				bypassPaywallEnabled: true,
				createClient: () => makeSupabaseStub(calls),
			},
		);
		// (a) Fail-closed error, no stream started.
		assert.equal(result.kind, 'json', 'must NOT start an SSE stream on an anchor miss');
		const { status, body } = parseJsonResult(result);
		assert.equal(status, 409, 'stale anchor must fail closed with 409 Conflict');
		assert.match(String(body.error ?? ''), /out of date|reload/i);
	});

	// (b) NO new user message was inserted (no partial write).
	assert.deepEqual(
		calls.inserts,
		[],
		`no coach_messages insert must fire on an anchor miss, got: ${JSON.stringify(calls.inserts)}`,
	);

	// (c) The miss is logged for operational visibility.
	assert.ok(
		lines.some((l) => l.includes('regenerate_anchor_miss')),
		`expected a "regenerate_anchor_miss" log line, got: ${JSON.stringify(lines)}`,
	);
});

// ───────────── AI-disclosure consent gate (issue #734) ─────────────

async function coachWithProfile(
	profileOverride: Record<string, unknown> | null,
): Promise<{ status: number; body: Record<string, unknown> }> {
	const calls = { inserts: [] as string[], deletes: [] as string[] };
	let result!: Awaited<ReturnType<typeof handleCoach>>;
	await captureConsoleError(async () => {
		result = await handleCoach(
			'Bearer fake-token',
			{ messages: [{ role: 'user', content: 'hi' }] },
			{
				...baseConfig(),
				bypassPaywallEnabled: true,
				createClient: () => makeSupabaseStub(calls, profileOverride),
			},
		);
	});
	assert.equal(result.kind, 'json', 'a consent denial must not start an SSE stream');
	assert.deepEqual(calls.inserts, [], 'no message may be persisted on a consent denial');
	return parseJsonResult(result) as { status: number; body: Record<string, unknown> };
}

test('coach refuses when no consent record is on file', async () => {
	// Reason: audit/gdpr (2026-05-25) + issue #734. The record is now
	// versioned, so "consented" means a known version at or above the
	// Coach minimum — not merely a non-null timestamp.
	const { status, body } = await coachWithProfile({
		coach_consent_at: null,
		ai_disclosure_version: null,
		display_name: 'Test Runner',
		preferred_unit: 'km',
	});
	assert.equal(status, 403);
	assert.equal(body.code, 'ai_disclosure_required');
	assert.equal(body.required_version, 1);
});

test('coach refuses a half-written or unknown-version consent record', async () => {
	// A timestamp with no version (or a version this build cannot render)
	// is not proof of an affirmative act — deny rather than assume.
	for (const profile of [
		{ coach_consent_at: '2026-01-01T00:00:00Z', ai_disclosure_version: null },
		{ coach_consent_at: '2026-01-01T00:00:00Z', ai_disclosure_version: 99 },
		{ coach_consent_at: null, ai_disclosure_version: 1 },
	]) {
		const { status, body } = await coachWithProfile({
			...profile,
			display_name: 'Test Runner',
			preferred_unit: 'km',
		});
		assert.equal(status, 403, `expected 403 for ${JSON.stringify(profile)}`);
		assert.equal(body.code, 'ai_disclosure_required');
	}
});

test('coach accepts the widened disclosure as well as the Coach one', async () => {
	// The ladder is monotone: v2 is a superset of v1, so a route-AI
	// acceptance must not lock the caller out of the Coach. Asserted via
	// the regenerate anchor-miss branch, which sits after the consent gate
	// and before the provider — a 409 here proves the gate let v2 through
	// without spending a real Anthropic call to find out.
	const calls = { inserts: [] as string[], deletes: [] as string[] };
	let result!: Awaited<ReturnType<typeof handleCoach>>;
	await captureConsoleError(async () => {
		result = await handleCoach(
			'Bearer fake-token',
			{
				messages: [{ role: 'user', content: 'try again' }],
				mode: 'regenerate',
				anchor_message_id: 'stale-anchor-id',
			},
			{
				...baseConfig(),
				bypassPaywallEnabled: true,
				createClient: () =>
					makeSupabaseStub(calls, {
						coach_consent_at: '2026-01-01T00:00:00Z',
						ai_disclosure_version: 2,
						display_name: 'Test Runner',
						preferred_unit: 'km',
					}),
			},
		);
	});
	const { status, body } = parseJsonResult(result);
	assert.equal(status, 409, 'a v2 holder must clear the Coach consent gate');
	assert.equal((body as Record<string, unknown>).code, undefined);
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

// ───────────── coachSseStream — quota × persistence branches ─────────────
//
// The SSE body is extracted from handleCoach so its quota/persistence
// branch logic is unit-testable without a live Supabase: a fake
// ProviderStream + spy persistAssistant / refundSlot make the "who paid,
// who got persisted" contract assertable directly. Issue #391 — a
// mid-stream failure with a non-empty partial used to consume a daily-cap
// slot but return before any persistence, so the streamed reply was lost
// on the next loadThread re-read. It must now persist the partial.

/// A ProviderStream that yields `chunks` then optionally throws mid-stream.
function fakeStream(
	chunks: string[],
	throwAfter: boolean,
	throwMessage = 'upstream connection reset',
): ProviderStream {
	return {
		tokens: (async function* () {
			for (const c of chunks) yield c;
			if (throwAfter) throw new Error(throwMessage);
		})(),
		finalUsage: async () => emptyUsage(),
	};
}

/// Drain the SSE byte stream into one decoded string.
async function drain(stream: AsyncIterable<Uint8Array>): Promise<string> {
	const decoder = new TextDecoder();
	let out = '';
	for await (const chunk of stream) out += decoder.decode(chunk);
	return out;
}

/// Build deps with recording spies; the caller overrides `providerStream`.
function streamDeps(overrides: Partial<CoachStreamDeps> = {}): {
	deps: CoachStreamDeps;
	persisted: string[];
	refunds: string[];
} {
	const persisted: string[] = [];
	const refunds: string[] = [];
	const deps: CoachStreamDeps = {
		providerStream: fakeStream([], false),
		meta: {
			user_message_id: 'user-msg-1',
			tier: 'free',
			limits: { daily_limit: 2, max_tokens: 768, max_runs_limit: 30 },
		},
		usedToday: 1,
		persistAssistant: async (content) => {
			persisted.push(content);
			return 'assistant-row-1';
		},
		refundSlot: async (reason) => {
			refunds.push(reason);
		},
		logMidStreamError: () => {},
		...overrides,
	};
	return { deps, persisted, refunds };
}

test('mid-stream failure with a partial reply persists the partial and does NOT refund', async () => {
	// Reason: issue #391. The user was streamed "Hello there" (consuming a
	// daily-cap slot) before the provider dropped. That partial must be
	// written to coach_messages so a reload / second device recovers it;
	// the slot is not refunded because the user genuinely received content.
	const { deps, persisted, refunds } = streamDeps({
		providerStream: fakeStream(['Hello ', 'there'], true),
	});
	const out = await drain(coachSseStream(deps));

	assert.deepEqual(persisted, ['Hello there'], 'partial must be persisted verbatim');
	assert.deepEqual(refunds, [], 'a consumed slot with content must NOT be refunded');
	assert.match(out, /event: error/, 'client still gets the error event');
	assert.doesNotMatch(out, /event: done/, 'no done event on a failed stream');
});

test('the mid-stream error event carries no upstream detail', async () => {
	// Reason: the handler used to put the caught error's `.message` straight
	// on the wire. On the Anthropic path that string is the upstream status
	// envelope (model id, error taxonomy, and the `messages.N` index that
	// counts the turns injected ahead of the caller's); on the OpenAI-
	// compatible path `humaniseUpstreamError` falls back to the raw upstream
	// body. A zero-token failure also refunds the slot, so probing it was
	// free and repeatable. The client renders its own localized copy when the
	// event carries no message.
	const { deps } = streamDeps({
		providerStream: fakeStream([], true, 'Coach upstream 400: {"type":"error",' +
			'"error":{"type":"invalid_request_error","message":"messages.2.role: ' +
			'Input tag \'system\' found using \'role\' does not match any of the ' +
			'expected tags"}} model=claude-sonnet-4-5'),
	});
	const out = await drain(coachSseStream(deps));

	assert.match(out, /event: error/, 'the error event still fires');
	assert.doesNotMatch(out, /messages\.2\.role/, 'no upstream message index on the wire');
	assert.doesNotMatch(out, /invalid_request_error/, 'no upstream error taxonomy on the wire');
	assert.doesNotMatch(out, /claude-sonnet/, 'no model id on the wire');
});

test('mid-stream failure with ZERO tokens refunds the slot and persists nothing', async () => {
	// Reason: the complementary contract — a total failure (no content
	// streamed) refunds the slot and writes no row. Pins that the partial
	// fix didn't turn every failure into a persist.
	const { deps, persisted, refunds } = streamDeps({
		providerStream: fakeStream([], true),
	});
	const out = await drain(coachSseStream(deps));

	assert.deepEqual(persisted, [], 'nothing to persist when the stream yielded nothing');
	assert.deepEqual(refunds, ['mid_stream_error_zero_tokens'], 'the empty slot must be refunded');
	assert.match(out, /event: error/);
});

test('happy path persists the full reply, emits done, refunds nothing', async () => {
	// Reason: the extraction must not regress the success path — the full
	// accumulated reply persists once, the done event carries the row id,
	// and no refund fires.
	const { deps, persisted, refunds } = streamDeps({
		providerStream: fakeStream(['Run ', 'easy ', 'today'], false),
	});
	const out = await drain(coachSseStream(deps));

	assert.deepEqual(persisted, ['Run easy today']);
	assert.deepEqual(refunds, []);
	assert.match(out, /event: done/);
	assert.match(out, /assistant-row-1/, 'done event carries the persisted assistant_message_id');
	assert.match(out, /"used_today":1/);
});
