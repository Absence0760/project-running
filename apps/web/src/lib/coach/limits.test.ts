import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	DEFAULT_RUNS_LIMIT,
	MAX_COACH_ASSISTANT_CONTENT_BYTES,
	MAX_COACH_MESSAGES,
	MAX_COACH_TOTAL_CONTENT_BYTES,
	MAX_COACH_USER_CONTENT_BYTES,
	clampRunsLimit,
	jsonError,
	parseAuthHeader,
	personalityAddendum,
	rateLimitHeaders,
	validateCoachMessages,
} from './limits';

// ─────────────── parseAuthHeader ───────────────

test('parseAuthHeader — strips the `Bearer ` prefix and returns the token', () => {
	assert.equal(parseAuthHeader('Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig'), 'eyJhbGciOiJIUzI1NiJ9.payload.sig');
});

test('parseAuthHeader — case-insensitive on the prefix', () => {
	assert.equal(parseAuthHeader('bearer abc'), 'abc');
	assert.equal(parseAuthHeader('BEARER abc'), 'abc');
	assert.equal(parseAuthHeader('Bearer abc'), 'abc');
});

test('parseAuthHeader — null / undefined / empty input returns null', () => {
	assert.equal(parseAuthHeader(null), null);
	assert.equal(parseAuthHeader(undefined), null);
	assert.equal(parseAuthHeader(''), null);
});

test('parseAuthHeader — bare `Bearer ` with no token returns null', () => {
	assert.equal(parseAuthHeader('Bearer '), null);
	assert.equal(parseAuthHeader('Bearer  '), null);
});

test('parseAuthHeader — token without `Bearer ` is returned verbatim', () => {
	// Some clients omit the prefix. Pass through so the upstream
	// supabase client can decide whether to accept or reject.
	assert.equal(parseAuthHeader('eyJraw.token.value'), 'eyJraw.token.value');
});

// ─────────────── clampRunsLimit ───────────────

test('clampRunsLimit — undefined / null returns the default', () => {
	assert.equal(clampRunsLimit(undefined, 'free'), DEFAULT_RUNS_LIMIT);
	assert.equal(clampRunsLimit(null, 'free'), DEFAULT_RUNS_LIMIT);
});

test('clampRunsLimit — non-finite input returns the default', () => {
	// Infinity / NaN / non-numeric strings all fall through to the
	// default rather than the tier cap. Matches the original handler
	// behaviour: a malformed request shouldn't silently get the
	// largest allowed window.
	assert.equal(clampRunsLimit('not a number', 'free'), DEFAULT_RUNS_LIMIT);
	assert.equal(clampRunsLimit(Number.NaN, 'free'), DEFAULT_RUNS_LIMIT);
	assert.equal(clampRunsLimit(Number.POSITIVE_INFINITY, 'free'), DEFAULT_RUNS_LIMIT);
});

test('clampRunsLimit — caps at the tier max (free=30, pro=75)', () => {
	// Pro cap was 200 pre-pass-3; lowered to 75 to bound input-token
	// cost on a stolen Pro session token. See coach/types.ts.
	assert.equal(clampRunsLimit(500, 'free'), 30);
	assert.equal(clampRunsLimit(500, 'pro'), 75);
});

test('clampRunsLimit — floors at 1 (zero-runs context is never useful)', () => {
	assert.equal(clampRunsLimit(0, 'free'), 1);
	assert.equal(clampRunsLimit(-5, 'free'), 1);
});

test('clampRunsLimit — fractional input is truncated, not rounded', () => {
	assert.equal(clampRunsLimit(15.9, 'free'), 15);
	assert.equal(clampRunsLimit(0.5, 'free'), 1); // truncates to 0, then floor to 1
});

test('clampRunsLimit — string-typed integer is coerced', () => {
	assert.equal(clampRunsLimit('25', 'free'), 25);
});

test('clampRunsLimit — pro tier honours larger requests up to its cap', () => {
	assert.equal(clampRunsLimit(70, 'pro'), 70);
	assert.equal(clampRunsLimit(50, 'pro'), 50);
});

// ─────────────── jsonError ───────────────

test('jsonError — produces the canonical pre-stream response shape', () => {
	const out = jsonError(401, 'not authenticated');
	assert.equal(out.kind, 'json');
	assert.equal(out.status, 401);
	assert.equal(out.headers['content-type'], 'application/json');
	assert.deepEqual(JSON.parse(out.body), { error: 'not authenticated' });
});

test('jsonError — extra fields land alongside `error` in the body', () => {
	const out = jsonError(429, 'daily_limit', { used: 11, limit: 10, tier: 'free' });
	assert.deepEqual(JSON.parse(out.body), {
		error: 'daily_limit',
		used: 11,
		limit: 10,
		tier: 'free',
	});
});

test('jsonError — `error` field cannot be overridden by extra', () => {
	// `extra` is spread AFTER the `error` literal, so a caller passing
	// `error: 'mismatch'` in extra would clobber the message. Pin the
	// current behaviour so a refactor that flips the spread order is
	// caught.
	const out = jsonError(400, 'invalid', { error: 'something else' });
	assert.equal(JSON.parse(out.body).error, 'something else');
});

// ─────────────── rateLimitHeaders ───────────────

test('rateLimitHeaders — free tier reports finite limit and remaining', () => {
	const headers = rateLimitHeaders('free', 3);
	assert.equal(headers['X-Coach-Tier'], 'free');
	assert.equal(headers['X-RateLimit-Limit'], '5');
	assert.equal(headers['X-RateLimit-Remaining'], '2');
	assert.equal(headers['X-RateLimit-MaxTokens'], '768');
	assert.equal(headers['X-RateLimit-MaxRuns'], '30');
});

test('rateLimitHeaders — free tier remaining clamps to 0 when usage exceeds the cap', () => {
	const headers = rateLimitHeaders('free', 25);
	assert.equal(headers['X-RateLimit-Remaining'], '0');
});

test('rateLimitHeaders — pro tier reports unlimited daily', () => {
	const headers = rateLimitHeaders('pro', 999);
	assert.equal(headers['X-Coach-Tier'], 'pro');
	assert.equal(headers['X-RateLimit-Limit'], 'unlimited');
	assert.equal(headers['X-RateLimit-Remaining'], 'unlimited');
	assert.equal(headers['X-RateLimit-MaxTokens'], '2048');
	assert.equal(headers['X-RateLimit-MaxRuns'], '75');
});

// ─────────────── personalityAddendum ───────────────

test('personalityAddendum — drill_sergeant tone override', () => {
	const out = personalityAddendum('drill_sergeant');
	assert.match(out, /blunt|demanding|military/i);
	// Leading newlines so the addendum cleanly chains onto the system
	// prompt without smashing the last paragraph.
	assert.ok(out.startsWith('\n\n'));
});

test('personalityAddendum — analytical tone override', () => {
	const out = personalityAddendum('analytical');
	assert.match(out, /data-driven|sports scientist|trends/i);
	assert.ok(out.startsWith('\n\n'));
});

test('personalityAddendum — default / unknown / null styles return empty', () => {
	assert.equal(personalityAddendum(null), '');
	assert.equal(personalityAddendum(undefined), '');
	assert.equal(personalityAddendum(''), '');
	assert.equal(personalityAddendum('encouraging'), ''); // unknown style
});

// ─────────────── validateCoachMessages ───────────────
//
// Pinned because the per-message cap split by role is the regression fix
// that lets long assistant messages flow through while keeping a tight
// anti-abuse cap on user input. Conflating them again (single 8 KB cap
// for everything) silently breaks conversation resumption.

test('validateCoachMessages — rejects non-array body.messages', () => {
	assert.deepEqual(validateCoachMessages(null), { ok: false, reason: 'not-array' });
	assert.deepEqual(validateCoachMessages(undefined), { ok: false, reason: 'not-array' });
	assert.deepEqual(validateCoachMessages('hi'), { ok: false, reason: 'not-array' });
	assert.deepEqual(validateCoachMessages({ length: 0 }), { ok: false, reason: 'not-array' });
});

test('validateCoachMessages — accepts a normal multi-turn conversation', () => {
	const messages = [
		{ role: 'user', content: 'plan my next 4 weeks' },
		{ role: 'assistant', content: 'Sure — here is a 4-week base plan…' },
		{ role: 'user', content: 'swap thursday for a long run' },
	];
	assert.deepEqual(validateCoachMessages(messages), { ok: true });
});

test('validateCoachMessages — caps the total list length', () => {
	const messages = Array.from({ length: MAX_COACH_MESSAGES + 1 }, (_, i) => ({
		role: i % 2 === 0 ? 'user' : 'assistant',
		content: 'x',
	}));
	assert.deepEqual(validateCoachMessages(messages), { ok: false, reason: 'too-many' });
});

test('validateCoachMessages — rejects a non-string message.content', () => {
	assert.deepEqual(
		validateCoachMessages([{ role: 'user', content: 123 }]),
		{ ok: false, reason: 'content-not-string' },
	);
	assert.deepEqual(
		validateCoachMessages([{ role: 'user' }]),
		{ ok: false, reason: 'content-not-string' },
	);
});

test('validateCoachMessages — long assistant message OK (the pass-3 regression fix)', () => {
	// 32 KB is well above the 8 KB user cap but under the 64 KB
	// assistant cap. Pre-fix, this would have been rejected uniformly.
	const longAssistant = 'a'.repeat(32 * 1024);
	assert.ok(longAssistant.length > MAX_COACH_USER_CONTENT_BYTES);
	assert.ok(longAssistant.length < MAX_COACH_ASSISTANT_CONTENT_BYTES);
	const messages = [
		{ role: 'user', content: 'give me a full plan' },
		{ role: 'assistant', content: longAssistant },
	];
	assert.deepEqual(validateCoachMessages(messages), { ok: true });
});

test('validateCoachMessages — rejects an oversized user message (anti-abuse)', () => {
	const tooLongUser = 'a'.repeat(MAX_COACH_USER_CONTENT_BYTES + 1);
	const messages = [{ role: 'user', content: tooLongUser }];
	assert.deepEqual(validateCoachMessages(messages), {
		ok: false,
		reason: 'per-message-too-long',
	});
});

test('validateCoachMessages — rejects an oversized assistant message', () => {
	const tooLongAssistant = 'a'.repeat(MAX_COACH_ASSISTANT_CONTENT_BYTES + 1);
	const messages = [{ role: 'assistant', content: tooLongAssistant }];
	assert.deepEqual(validateCoachMessages(messages), {
		ok: false,
		reason: 'per-message-too-long',
	});
});

test('validateCoachMessages — rejects when aggregate exceeds the total cap', () => {
	// Each assistant chunk is just under the per-message cap; together
	// they push past the aggregate cap.
	const chunkSize = MAX_COACH_ASSISTANT_CONTENT_BYTES - 1;
	const chunkCount = Math.ceil(MAX_COACH_TOTAL_CONTENT_BYTES / chunkSize) + 1;
	const messages = Array.from({ length: chunkCount }, () => ({
		role: 'assistant',
		content: 'a'.repeat(chunkSize),
	}));
	// Sanity-check we are still under the list-length cap so the
	// failure mode is the aggregate cap, not 'too-many'.
	assert.ok(messages.length <= MAX_COACH_MESSAGES);
	assert.deepEqual(validateCoachMessages(messages), {
		ok: false,
		reason: 'aggregate-too-long',
	});
});
