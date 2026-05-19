// Unit tests for the postgres P0001 rate-limit-error parser. Run via
//   npx tsx --test apps/web/src/lib/rate_limit_errors.test.ts
// or by the workspace `test:web:unit` script.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { rateLimitErrorMessage } from './rate_limit_errors';

test('returns null for null / undefined / non-P0001 errors', () => {
	assert.equal(rateLimitErrorMessage(null), null);
	assert.equal(rateLimitErrorMessage(undefined), null);
	assert.equal(
		rateLimitErrorMessage({ code: '23505', message: 'duplicate key' }),
		null,
	);
	assert.equal(rateLimitErrorMessage({ code: 'P0001' }), null);
	assert.equal(
		rateLimitErrorMessage({ code: 'P0001', message: 'something unrelated' }),
		null,
	);
});

test('parses create_club bucket with sub-90s wait → "X seconds"', () => {
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club, retry in 42s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 42 seconds and try again.");
});

test('parses create_route bucket with > 90s wait → rounded "X minutes"', () => {
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_route, retry in 1234s',
	});
	// 1234s → ceil(1234 / 60) = 21 minutes.
	assert.equal(msg, "You're creating routes too quickly — please wait 21 minutes and try again.");
});

test('exactly 90s rolls up to "2 minutes" (the cutoff)', () => {
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club, retry in 90s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 2 minutes and try again.");
});

test('89s stays as seconds (the cutoff boundary, other side)', () => {
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club, retry in 89s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 89 seconds and try again.");
});

test('1s uses singular "second"', () => {
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club, retry in 1s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 1 second and try again.");
});

test('unknown bucket falls back to generic verb', () => {
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_widget, retry in 30s',
	});
	assert.equal(msg, "You're doing that too quickly — please wait 30 seconds and try again.");
});

test('zero / negative seconds defaults to "a few seconds"', () => {
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club, retry in 0s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait a few seconds and try again.");
});

test('mismatched format returns null (fail safe — don\'t pretend to parse)', () => {
	assert.equal(
		rateLimitErrorMessage({ code: 'P0001', message: 'rate limit exceeded' }),
		null,
	);
});

test('tolerates extra whitespace between "retry in" and the seconds', () => {
	// The postgres `raise exception '..., retry in %s'` literal uses a
	// single space, but a future migration tweak could land tab / two-
	// space variants. The regex's `\s*` keeps the parse tolerant.
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club,  retry in  42s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 42 seconds and try again.");
});

test('parse is case-insensitive (mixed case still matches)', () => {
	// Postgres' raise is case-sensitive at write-time, but case-insensitive
	// at parse-time guards against a future copy-edit that capitalises
	// "Rate Limit Exceeded" — the helper still recognises and translates.
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'Rate Limit Exceeded for create_club, retry in 10s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 10 seconds and try again.");
});

test('rejects a wrong SQLSTATE even with matching message text', () => {
	// Defensive: a CHECK-constraint violation (23514) or RLS deny (42501)
	// must never get the friendly-rate-limit treatment, even on the
	// hypothetical case that something else surfaces a near-identical
	// "rate limit" string. Only P0001 + matching format is a match.
	assert.equal(
		rateLimitErrorMessage({
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
		rateLimitErrorMessage({
			message: 'rate limit exceeded for create_club, retry in 42s',
		}),
		null,
	);
});

test('3540s → "59 minutes" (just-under-one-hour boundary)', () => {
	// The create_club / create_route bucket window is 3600s, so the
	// trigger's `retry in` value can land anywhere in [0, 3600). Pin
	// the upper-edge wording so a future tweak to the rounding logic
	// can't silently make us say "59.something" or "1 hour" without
	// a passing test.
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club, retry in 3540s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 59 minutes and try again.");
});

test('3600s → "60 minutes" (hour-exact boundary)', () => {
	// Practically unreachable from the trigger (window resets at this
	// boundary), but pinning the deterministic output keeps the helper
	// from accidentally regressing if a future migration widens the
	// window past 3600 (e.g., 6-hour anti-abuse cap).
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club, retry in 3600s',
	});
	assert.equal(msg, "You're creating clubs too quickly — please wait 60 minutes and try again.");
});

test('decimal seconds in message → null (only integer matches \\d+)', () => {
	// Defensive: the trigger always emits an integer (postgres `%s` of
	// a numeric interval), but if a future change inserts a decimal,
	// we'd rather fall through to the raw error than pretend to parse.
	assert.equal(
		rateLimitErrorMessage({
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
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_route, retry in 30s, please wait',
	});
	assert.equal(msg, "You're creating routes too quickly — please wait 30 seconds and try again.");
});

test('numeric chars inside the bucket name parse to the seconds, not the bucket', () => {
	// `\w+` is greedy and would happily eat digits — but the regex
	// requires a comma right after the bucket, so a bucket name with
	// an embedded number (`create_club_v2`) still parses the bucket
	// correctly and pulls the seconds out of the `retry in` clause.
	// The unknown-bucket fallback then maps it to "doing that".
	const msg = rateLimitErrorMessage({
		code: 'P0001',
		message: 'rate limit exceeded for create_club_v2, retry in 30s',
	});
	assert.equal(msg, "You're doing that too quickly — please wait 30 seconds and try again.");
});
