import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	chunk,
	mergeFeedPages,
	mergeProfilePages,
	mergeRecencyPages,
	FEED_FOLLOWEE_CHUNK
} from './feed_merge';

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

test('mergeRecencyPages orders by an arbitrary timestamp field (earned_at)', () => {
	// The badge feed orders by `earned_at`, not `started_at` — mergeFeedPages is
	// just this specialised to `started_at`.
	const mk = (id: string, day: number) => ({
		id,
		earned_at: `2026-05-${String(day).padStart(2, '0')}T10:00:00Z`
	});
	const pageA = [mk('a12', 12), mk('a2', 2)];
	const pageB = [mk('b11', 11), mk('b2', 2)]; // 'b2' vs 'a2' tie → id desc keeps 'b2'
	const merged = mergeRecencyPages([pageA, pageB], 3, (r) => r.earned_at);
	assert.deepEqual(
		merged.map((r) => r.id),
		['a12', 'b11', 'b2']
	);
});

test('badge-feed chunk+merge surfaces every followee across >FEED_FOLLOWEE_CHUNK ids', () => {
	// Simulate the fetchFollowingBadgeAwards path: >100 followees, each with one
	// public award, queried per chunk. The merge must surface the global newest
	// `limit` — proving the chunking can't drop a followee's award.
	const limit = 20;
	const authorCount = 250;
	const authors = Array.from({ length: authorCount }, (_, i) => `author-${i}`);
	// Each author earned a badge; earned_at increases with the index so the
	// newest `limit` are the highest indices.
	const rowFor = (i: number) => ({
		id: `badge-${i}`,
		user_id: `author-${i}`,
		earned_at: `2026-01-01T00:${String(i % 60).padStart(2, '0')}:${String(i).padStart(4, '0').slice(-2)}Z`,
		// Monotonic sort key independent of the minute rollover above.
		sort: i
	});
	const chunks = chunk(authors, FEED_FOLLOWEE_CHUNK);
	assert.equal(chunks.length, 3);
	// Each chunk query returns its authors' rows, newest-first, capped at limit.
	const pages = chunks.map((ids) => {
		const idxs = ids.map((a) => Number(a.split('-')[1]));
		return idxs
			.map(rowFor)
			.sort((x, y) => y.sort - x.sort)
			.slice(0, limit);
	});
	const merged = mergeRecencyPages(pages, limit, (r) => String(r.sort).padStart(4, '0'));
	assert.equal(merged.length, limit);
	// The global newest `limit` are indices 249..230.
	assert.deepEqual(
		merged.map((r) => r.sort),
		Array.from({ length: limit }, (_, i) => authorCount - 1 - i)
	);
});

test('mergeProfilePages merges every chunk into one id→row map', () => {
	// The profile-join leg chunks `.in('id', ids)`; the merge must not drop a
	// single profile even when the id set spans multiple chunks.
	const ids = Array.from({ length: 250 }, (_, i) => `u-${i}`);
	const chunks = chunk(ids, FEED_FOLLOWEE_CHUNK);
	assert.equal(chunks.length, 3);
	const pages = chunks.map((c) =>
		c.map((id) => ({ id, display_name: `name-${id}`, avatar_url: null }))
	);
	const byId = mergeProfilePages(pages);
	assert.equal(byId.size, 250);
	for (const id of ids) {
		assert.equal(byId.get(id)?.display_name, `name-${id}`);
	}
});

test('mergeProfilePages tolerates null/undefined pages and returns an empty map for no input', () => {
	assert.equal(mergeProfilePages<{ id: string }>([]).size, 0);
	const byId = mergeProfilePages([[{ id: 'a' }], null, undefined, [{ id: 'b' }]]);
	assert.deepEqual([...byId.keys()].sort(), ['a', 'b']);
});
