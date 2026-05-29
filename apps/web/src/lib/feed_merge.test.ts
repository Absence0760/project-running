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

test('mergeFeedPages trims to the global top-N across multiple saturated chunks', () => {
	// Three chunks each returning a full `limit`-sized page (the worst case:
	// every chunk is saturated). The merge must surface the global newest
	// `limit` rows across all chunks, not just one chunk's worth.
	const limit = 3;
	const mk = (id: string, day: number) => ({
		id,
		started_at: `2026-05-${String(day).padStart(2, '0')}T10:00:00Z`
	});
	// Interleave dates across chunks so the correct top-3 (days 12,11,10) is
	// spread over all three pages — a naive "take the first chunk" would miss it.
	const pageA = [mk('a3', 3), mk('a2', 2), mk('a1', 1)];
	const pageB = [mk('b12', 12), mk('b6', 6), mk('b5', 5)];
	const pageC = [mk('c11', 11), mk('c10', 10), mk('c4', 4)];
	const merged = mergeFeedPages([pageA, pageB, pageC], limit);
	assert.equal(merged.length, limit);
	assert.deepEqual(
		merged.map((r) => r.id),
		['b12', 'c11', 'c10']
	);
});

test('mergeFeedPages returns [] when limit is 0', () => {
	assert.deepEqual(
		mergeFeedPages([[{ id: 'x', started_at: '2026-05-02T10:00:00Z' }]], 0),
		[]
	);
});
