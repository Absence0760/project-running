// Unit tests for the postgres P0001 rate-limit-error parser. Run via
//   npx tsx --test apps/web/src/lib/util/rate_limit_errors.test.ts
// or by the workspace `test:web:unit` script.
//
// The parser holds no prose since decisions § 744 — the sentence a
// reader sees is assembled from the catalogue in
// `i18n/rate_limit_message.ts`, whose own suite renders it per locale.
// Mirror suite: apps/mobile_android/test/rate_limit_errors_test.dart.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { parseRateLimitError } from './rate_limit_errors';

test('returns null for null / undefined / non-P0001 errors', () => {
	assert.equal(parseRateLimitError(null), null);
	assert.equal(parseRateLimitError(undefined), null);
	assert.equal(parseRateLimitError({ code: '23505', message: 'duplicate key' }), null);
	assert.equal(parseRateLimitError({ code: 'P0001' }), null);
	assert.equal(parseRateLimitError({ code: 'P0001', message: 'something unrelated' }), null);
});

test('parses the create_club bucket and its wait', () => {
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club, retry in 42s',
		}),
		{ bucket: 'create_club', seconds: 42 },
	);
});

test('parses the create_route bucket', () => {
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_route, retry in 1234s',
		}),
		{ bucket: 'create_route', seconds: 1234 },
	);
});

test('parses the create_report bucket', () => {
	// submit_report + report_comments + report_posts_and_runs +
	// report_route_reviews all debit this one bucket.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_report, retry in 600s',
		}),
		{ bucket: 'create_report', seconds: 600 },
	);
});

test('parses both plan-adopt buckets as themselves', () => {
	// clone_plan_template (club template) and clone_public_plan (public
	// library) are the same act from two libraries; collapsing them onto
	// one sentence is the render layer's decision, not the parser's.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for clone_plan_template, retry in 300s',
		}),
		{ bucket: 'clone_plan_template', seconds: 300 },
	);
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for clone_public_plan, retry in 45s',
		}),
		{ bucket: 'clone_public_plan', seconds: 45 },
	);
});

test('parses the clone_session_template bucket', () => {
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for clone_session_template, retry in 30s',
		}),
		{ bucket: 'clone_session_template', seconds: 30 },
	);
});

test('parses the clone_gym_routine_template bucket', () => {
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for clone_gym_routine_template, retry in 30s',
		}),
		{ bucket: 'clone_gym_routine_template', seconds: 30 },
	);
});

test('parses the publish_gym_routine_as_template bucket', () => {
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for publish_gym_routine_as_template, retry in 120s',
		}),
		{ bucket: 'publish_gym_routine_as_template', seconds: 120 },
	);
});

test('parses both direct-message buckets', () => {
	// Migration 20270608_001 debits two windows per send (decisions § 737):
	// a 30/60 s burst and a 250/3600 s hour cap, the hour one checked
	// first so the sender is told the binding wait. Both must parse — the
	// helper used to fall through to the generic sentence for them on
	// BOTH platforms, so a throttled sender read "You're doing that too
	// quickly" about a message they had just tried to send.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for send_direct_message, retry in 1800s',
		}),
		{ bucket: 'send_direct_message', seconds: 1800 },
	);
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for send_direct_message_burst, retry in 41s',
		}),
		{ bucket: 'send_direct_message_burst', seconds: 41 },
	);
});

test('an unrecognised bucket is returned verbatim, not swallowed', () => {
	// A bucket a later migration adds must reach the render layer as
	// itself so that layer can pick the honest generic sentence. Dropping
	// it here would leave the caller unable to tell a new bucket from a
	// parse failure.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_widget, retry in 30s',
		}),
		{ bucket: 'create_widget', seconds: 30 },
	);
});

test('a one-second wait is a plain 1, not rounded away', () => {
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club, retry in 1s',
		}),
		{ bucket: 'create_club', seconds: 1 },
	);
});

test('the seconds are passed through untouched either side of the minute cutoff', () => {
	// The 90 s seconds-vs-minutes cutoff is a rendering decision and lives
	// in rate_limit_message.ts. The parser reports what the trigger said.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club, retry in 89s',
		}),
		{ bucket: 'create_club', seconds: 89 },
	);
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club, retry in 90s',
		}),
		{ bucket: 'create_club', seconds: 90 },
	);
});

test('zero seconds becomes a null wait, not a literal 0', () => {
	// "retry in 0s" is the trigger saying the window is about to roll.
	// Null is "wait a moment"; a rendered "0 seconds" would invite an
	// immediate retry that fails again.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club, retry in 0s',
		}),
		{ bucket: 'create_club', seconds: null },
	);
});

test('mismatched format returns null (fail safe — don\'t pretend to parse)', () => {
	assert.equal(parseRateLimitError({ code: 'P0001', message: 'rate limit exceeded' }), null);
});

test('tolerates extra whitespace between "retry in" and the seconds', () => {
	// The postgres `raise exception '..., retry in %s'` literal uses a
	// single space, but a future migration tweak could land tab / two-
	// space variants. The regex's `\s*` keeps the parse tolerant.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club,  retry in  42s',
		}),
		{ bucket: 'create_club', seconds: 42 },
	);
});

test('parse is case-insensitive (mixed case still matches)', () => {
	// Postgres' raise is case-sensitive at write-time, but case-insensitive
	// at parse-time guards against a future copy-edit that capitalises
	// "Rate Limit Exceeded" — the helper still recognises it.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'Rate Limit Exceeded for create_club, retry in 10s',
		}),
		{ bucket: 'create_club', seconds: 10 },
	);
});

test('rejects a wrong SQLSTATE even with matching message text', () => {
	// Defensive: a CHECK-constraint violation (23514) or RLS deny (42501)
	// must never get the friendly-rate-limit treatment, even on the
	// hypothetical case that something else surfaces a near-identical
	// "rate limit" string. Only P0001 + matching format is a match.
	assert.equal(
		parseRateLimitError({
			code: '23514',
			message: 'rate limit exceeded for create_club, retry in 42s',
		}),
		null,
	);
});

test('returns null when message has the right shape but no SQLSTATE', () => {
	// A bare-string error (e.g. from a non-PostgrestError throw path)
	// must not be confused with the trigger's exception.
	assert.equal(
		parseRateLimitError({ message: 'rate limit exceeded for create_club, retry in 42s' }),
		null,
	);
});

test('decimal seconds in message → null (only integer matches \\d+)', () => {
	// Defensive: the trigger always emits an integer (postgres `%s` of
	// a numeric interval), but if a future change inserts a decimal,
	// we'd rather fall through to the raw error than pretend to parse.
	assert.equal(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club, retry in 1.5s',
		}),
		null,
	);
});

test('extra trailing message text doesn\'t break the parse', () => {
	// The regex doesn't anchor at end-of-string. A future migration
	// could append a `using` clause hint after the main message; the
	// bucket + seconds should still parse cleanly out of the prefix.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_route, retry in 30s, please wait',
		}),
		{ bucket: 'create_route', seconds: 30 },
	);
});

test('numeric chars inside the bucket name parse to the seconds, not the bucket', () => {
	// `\w+` is greedy and would happily eat digits — but the regex
	// requires a comma right after the bucket, so a bucket name with
	// an embedded number (`create_club_v2`) still parses the bucket
	// correctly and pulls the seconds out of the `retry in` clause.
	assert.deepEqual(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for create_club_v2, retry in 30s',
		}),
		{ bucket: 'create_club_v2', seconds: 30 },
	);
});

test('a hyphenated bucket cannot be parsed — the buckets are snake_case for that reason', () => {
	// decisions § 737: the filed DM entry proposed `'direct-messages'`.
	// `(\w+)` stops at the hyphen, the comma check then fails, and the
	// raw postgres string would have reached the sender. Pinned so a
	// later migration naming a bucket with a hyphen fails here rather
	// than in production.
	assert.equal(
		parseRateLimitError({
			code: 'P0001',
			message: 'rate limit exceeded for direct-messages, retry in 30s',
		}),
		null,
	);
});

test('the parser holds no user-facing sentence — the copy lives in the catalogue', () => {
	// The whole point of § 744. A helper that grows its own English back
	// is a helper a non-English reader gets English from, and neither the
	// catalogue guards nor the ARB parity suite can see it. Resolved off
	// import.meta.url rather than the cwd so it reads the same from the
	// repo root and from apps/web. Mirrored in the Dart suite against
	// lib/rate_limit_errors.dart.
	const source = readFileSync(
		fileURLToPath(new URL('./rate_limit_errors.ts', import.meta.url)),
		'utf-8',
	);
	const code = source
		.split('\n')
		.filter((line) => !line.trimStart().startsWith('///'))
		.join('\n');
	for (const phrase of ['too quickly', 'please wait', 'try again', 'a few seconds', 'doing that']) {
		assert.ok(
			!code.includes(phrase),
			`rate_limit_errors.ts contains the user-facing phrase "${phrase}" — the sentence belongs in the message catalogues.`,
		);
	}
});
