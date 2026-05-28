import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chunk, mergeFeedPages, FEED_FOLLOWEE_CHUNK } from './feed_merge';

test('chunk splits into the requested size with a short final chunk', () => {
	const ids = Array.from({ length: 250 }, (_, i) => `id-${i}`);
	const chunks = chunk(ids, FEED_FOLLOWEE_CHUNK);
	assert.equal(chunks.length, 3);
	assert.equal(chunks[0].length, 100);
	assert.equal(chunks[1].length, 100);
	assert.equal(chunks[2].length, 50);
	// No id lost or duplicated.
	assert.deepEqual(chunks.flat(), ids);
});

test('chunk returns empty array for empty input, single chunk when under size', () => {
	assert.deepEqual(chunk([], 100), []);
	assert.deepEqual(chunk(['a', 'b'], 100), [['a', 'b']]);
});

test('chunk throws on non-positive size', () => {
	assert.throws(() => chunk([1, 2], 0));
});

test('mergeFeedPages sorts by started_at desc then id desc and trims to limit', () => {
	const pageA = [
		{ id: 'b', started_at: '2026-05-02T10:00:00Z' },
		{ id: 'a', started_at: '2026-05-01T10:00:00Z' }
	];
	const pageB = [
		{ id: 'd', started_at: '2026-05-03T10:00:00Z' },
		{ id: 'c', started_at: '2026-05-02T10:00:00Z' } // same ts as 'b' → id desc tiebreak
	];
	const merged = mergeFeedPages([pageA, pageB], 3);
	assert.deepEqual(
		merged.map((r) => r.id),
		['d', 'c', 'b'] // 2026-05-03, then 05-02 (c > b by id desc), then drop 'a'
	);
});

test('mergeFeedPages dedupes by id and tolerates null/undefined pages', () => {
	const merged = mergeFeedPages(
		[
			[{ id: 'x', started_at: '2026-05-02T10:00:00Z' }],
			null,
			[{ id: 'x', started_at: '2026-05-02T10:00:00Z' }],
			undefined
		],
		10
	);
	assert.equal(merged.length, 1);
	assert.equal(merged[0].id, 'x');
});

test('mergeFeedPages returns empty for all-empty input', () => {
	assert.deepEqual(mergeFeedPages([null, [], undefined], 20), []);
});
