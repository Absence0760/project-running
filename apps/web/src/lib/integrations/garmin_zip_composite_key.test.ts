import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compositeKey } from './garmin_dedupe';

test('compositeKey normalises a DB timestamptz and a parsed ISO string to the same key', () => {
	// PostgREST serialises a timestamptz with a +00:00 offset; parsed
	// imports carry a Z-suffixed ISO string. The same instant must yield
	// the same dedupe key, or a GPX/TCX re-import never matches its DB row.
	const fromDb = compositeKey('2026-01-01T09:00:00+00:00', 5012.7);
	const fromImport = compositeKey('2026-01-01T09:00:00.000Z', 5012.7);
	assert.equal(fromDb, fromImport);
});

test('compositeKey rounds distance so float-vs-int sources agree', () => {
	assert.equal(compositeKey('2026-01-01T09:00:00Z', 5012.7), compositeKey('2026-01-01T09:00:00Z', 5013));
	assert.equal(compositeKey('2026-01-01T09:00:00Z', 5000), '2026-01-01T09:00:00.000Z|5000');
});

test('compositeKey tolerates a non-offset timestamp and a null distance', () => {
	// A +02:00 offset normalises to the equivalent UTC instant.
	assert.equal(
		compositeKey('2026-01-01T11:00:00+02:00', 5000),
		compositeKey('2026-01-01T09:00:00Z', 5000),
	);
	assert.equal(compositeKey('2026-01-01T09:00:00Z', null), '2026-01-01T09:00:00.000Z|0');
});

test('compositeKey falls back to the raw string when the timestamp is unparseable', () => {
	assert.equal(compositeKey('not-a-date', 100), 'not-a-date|100');
});
