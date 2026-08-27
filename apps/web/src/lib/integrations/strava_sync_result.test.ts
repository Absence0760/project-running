import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { parseStravaSyncResult } from './strava_sync_result';

test('a finished walk is the only shape that reports complete', () => {
	const r = parseStravaSyncResult({
		imported: 12,
		skipped: 3,
		failed: 1,
		rate_limited: false,
		complete: true,
	});
	assert.equal(r.complete, true);
	assert.equal(r.rateLimited, false);
	assert.deepEqual([r.imported, r.skipped, r.failed], [12, 3, 1]);
});

test('a throttled walk is partial and names the cause', () => {
	const r = parseStravaSyncResult({
		imported: 40,
		skipped: 0,
		failed: 0,
		rate_limited: true,
		complete: false,
	});
	assert.equal(r.complete, false);
	assert.equal(r.rateLimited, true);
	assert.equal(r.imported, 40);
});

test('the other truncation causes are partial without a named cause', () => {
	// An upstream error, a malformed page and the 20-page cap all return
	// `rate_limited: false, complete: false`. Before `complete` existed they
	// were indistinguishable from a finished sync, which is the whole bug.
	const r = parseStravaSyncResult({
		imported: 1000,
		skipped: 0,
		failed: 0,
		rate_limited: false,
		complete: false,
	});
	assert.equal(r.complete, false);
	assert.equal(r.rateLimited, false);
});

test('an absent complete field reads as partial, not as finished', () => {
	// The fail-closed direction, and deliberately the opposite of
	// cloudExportShortfall's: a false "partial" costs one extra click, a
	// false "complete" costs the runs that aged out of the window.
	assert.equal(parseStravaSyncResult({ imported: 5, skipped: 0, failed: 0 }).complete, false);
	assert.equal(parseStravaSyncResult({}).complete, false);
});

test('a complete field that is not the boolean true does not earn completeness', () => {
	for (const value of ['true', 1, {}, [], null, 'yes']) {
		assert.equal(
			parseStravaSyncResult({ complete: value }).complete,
			false,
			`complete: ${JSON.stringify(value)} must not read as finished`,
		);
	}
});

test('rate_limited must be the boolean true to claim a throttle', () => {
	for (const value of ['true', 1, {}, null]) {
		assert.equal(parseStravaSyncResult({ rate_limited: value }).rateLimited, false);
	}
});

test('an unrecognised payload zeroes the counts and reports partial', () => {
	for (const payload of [null, undefined, 'ok', 42, [], [{ imported: 9 }]]) {
		const r = parseStravaSyncResult(payload);
		assert.deepEqual(
			[r.imported, r.skipped, r.failed, r.rateLimited, r.complete, r.athleteId, r.error],
			[0, 0, 0, false, false, null, null],
			`payload ${JSON.stringify(payload)} must not read as a sync`,
		);
	}
});

test('only a non-negative integer is a count', () => {
	const r = parseStravaSyncResult({
		imported: -3,
		skipped: 4.5,
		failed: '7',
		complete: true,
	});
	// A malformed count reads as 0 rather than as a number the toast would
	// then state as fact. Completeness is a separate claim and survives.
	assert.deepEqual([r.imported, r.skipped, r.failed], [0, 0, 0]);
	assert.equal(r.complete, true);
	assert.equal(parseStravaSyncResult({ imported: Number.NaN }).imported, 0);
	assert.equal(parseStravaSyncResult({ imported: Number.POSITIVE_INFINITY }).imported, 0);
	assert.equal(parseStravaSyncResult({ imported: 0 }).imported, 0);
});

test('a whole double is a count, as it is on the Dart twin', () => {
	// JSON has one number type: `Number.isInteger(12.0)` is true, so the Dart
	// side must not reject a `double` that happens to be whole.
	assert.equal(parseStravaSyncResult({ imported: 12.0 }).imported, 12);
});

test('an embedded error forces partial even when the body claims complete', () => {
	const r = parseStravaSyncResult({
		error: 'strava_not_connected',
		imported: 0,
		skipped: 0,
		failed: 0,
		complete: true,
	});
	assert.equal(r.error, 'strava_not_connected');
	assert.equal(r.complete, false);
});

test('a blank error is no error', () => {
	assert.equal(parseStravaSyncResult({ error: '   ', complete: true }).error, null);
	assert.equal(parseStravaSyncResult({ error: '   ', complete: true }).complete, true);
	assert.equal(parseStravaSyncResult({ error: 404 }).error, null);
});

test('athlete_id is carried through only as a non-empty string', () => {
	assert.equal(parseStravaSyncResult({ athlete_id: '12345' }).athleteId, '12345');
	assert.equal(parseStravaSyncResult({ athlete_id: '' }).athleteId, null);
	assert.equal(parseStravaSyncResult({ athlete_id: 12345 }).athleteId, null);
	assert.equal(parseStravaSyncResult({}).athleteId, null);
});
