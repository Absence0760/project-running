// Pure tests for the Strava ZIP dedupe-set builder. Persona-hunt
// Intermediate #1: pre-fix the dedup queried only metadata.strava_id
// AND filtered by source='strava', so older rows from before the
// strava_id tag was added — or rows that lost the metadata key in a
// partial restore — slipped past and re-imported as duplicates.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildStravaDedupeSet } from './strava-zip-dedupe';

test('buildStravaDedupeSet — adds metadata.strava_id', () => {
	const seen = buildStravaDedupeSet([
		{ metadata: { strava_id: '12345' }, external_id: null },
	]);
	assert.equal(seen.size, 1);
	assert.equal(seen.has('12345'), true);
});

test('buildStravaDedupeSet — adds external_id starting with strava:', () => {
	const seen = buildStravaDedupeSet([
		{ metadata: null, external_id: 'strava:67890' },
	]);
	assert.equal(seen.size, 1);
	assert.equal(seen.has('67890'), true);
});

test('buildStravaDedupeSet — coalesces same id from metadata + external_id', () => {
	// A normal modern row has BOTH the tag and the external_id. Must
	// not double-count.
	const seen = buildStravaDedupeSet([
		{ metadata: { strava_id: '99' }, external_id: 'strava:99' },
	]);
	assert.equal(seen.size, 1);
	assert.equal(seen.has('99'), true);
});

test('buildStravaDedupeSet — catches pre-tag rows via external_id', () => {
	// The original bug: a row with source='strava' + external_id set
	// to 'strava:42' but NO metadata.strava_id. Pre-fix this slipped
	// past the dedup; post-fix it lands in the set.
	const seen = buildStravaDedupeSet([
		{ metadata: { activity_type: 'run' }, external_id: 'strava:42' },
	]);
	assert.equal(seen.size, 1);
	assert.equal(seen.has('42'), true);
});

test('buildStravaDedupeSet — skips non-strava external_ids', () => {
	const seen = buildStravaDedupeSet([
		{ metadata: null, external_id: 'parkrun:1234-2026-04-15' },
		{ metadata: null, external_id: 'csv:2026-04-15-5000-1800' },
		{ metadata: null, external_id: 'healthconnect:abc-123' },
	]);
	assert.equal(seen.size, 0);
});

test('buildStravaDedupeSet — ignores null/empty inputs', () => {
	const seen = buildStravaDedupeSet([
		{ metadata: null, external_id: null },
		{ metadata: {}, external_id: '' },
		{ metadata: { other_key: 'x' }, external_id: undefined as unknown as null },
	]);
	assert.equal(seen.size, 0);
});

test('buildStravaDedupeSet — stringifies numeric metadata.strava_id', () => {
	// The csv stores activity IDs as strings, but a deserialiser
	// could feed numbers through. The set keys are strings; both
	// shapes must hash to the same bucket.
	const seen = buildStravaDedupeSet([
		{ metadata: { strava_id: 100 as unknown as string }, external_id: null },
	]);
	assert.equal(seen.has('100'), true);
});

test('buildStravaDedupeSet — handles mixed batch of new + legacy rows', () => {
	// Realistic case: an established account with rows from several
	// import generations. All Strava-derived rows must end up in the
	// set regardless of which path imported them.
	const seen = buildStravaDedupeSet([
		// Modern import: both keys.
		{ metadata: { strava_id: '1' }, external_id: 'strava:1' },
		// Legacy import: external_id only.
		{ metadata: null, external_id: 'strava:2' },
		// Partial restore: metadata only.
		{ metadata: { strava_id: '3' }, external_id: null },
		// Native app run: neither.
		{ metadata: { activity_type: 'run' }, external_id: null },
		// parkrun: different external_id namespace.
		{ metadata: null, external_id: 'parkrun:42-2026-04-01' },
	]);
	assert.equal(seen.size, 3);
	assert.equal(seen.has('1'), true);
	assert.equal(seen.has('2'), true);
	assert.equal(seen.has('3'), true);
});
