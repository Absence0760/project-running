import assert from 'node:assert/strict';
import { test } from 'node:test';

import { SegmentCache, segmentCacheKey, type CachedSegment } from './segment_cache';

const seg = (distanceM: number): CachedSegment => ({
	polyline: [
		[0, 0],
		[1, 1],
	],
	distanceM,
});

test('segmentCacheKey is stable for identical endpoints + profile', () => {
	const a = segmentCacheKey({ lng: 1, lat: 2 }, { lng: 3, lat: 4 }, 'foot');
	const b = segmentCacheKey({ lng: 1, lat: 2 }, { lng: 3, lat: 4 }, 'foot');
	assert.equal(a, b);
});

test('segmentCacheKey is order-sensitive (A→B differs from B→A)', () => {
	const ab = segmentCacheKey({ lng: 1, lat: 2 }, { lng: 3, lat: 4 });
	const ba = segmentCacheKey({ lng: 3, lat: 4 }, { lng: 1, lat: 2 });
	assert.notEqual(ab, ba);
});

test('segmentCacheKey is profile-scoped', () => {
	const onFoot = segmentCacheKey({ lng: 1, lat: 2 }, { lng: 3, lat: 4 }, 'foot');
	const inCar = segmentCacheKey({ lng: 1, lat: 2 }, { lng: 3, lat: 4 }, 'car');
	assert.notEqual(onFoot, inCar);
});

test('segmentCacheKey distinguishes a moved endpoint', () => {
	const before = segmentCacheKey({ lng: 1, lat: 2 }, { lng: 3, lat: 4 });
	const afterDrag = segmentCacheKey({ lng: 1, lat: 2 }, { lng: 3.0001, lat: 4 });
	assert.notEqual(before, afterDrag);
});

test('SegmentCache stores and returns by key', () => {
	const cache = new SegmentCache();
	const k = segmentCacheKey({ lng: 0, lat: 0 }, { lng: 1, lat: 1 });
	assert.equal(cache.get(k), undefined);
	cache.set(k, seg(100));
	assert.equal(cache.get(k)?.distanceM, 100);
	assert.equal(cache.size, 1);
});

test('SegmentCache: incremental route only misses on the new segment', () => {
	// Simulates the builder's real access pattern: route [A,B], then
	// append C and route [A,B,B,C]. The shared A→B segment must be a
	// cache hit on the second pass so only B→C hits OSRM.
	const cache = new SegmentCache();
	const A = { lng: 0, lat: 0 };
	const B = { lng: 1, lat: 0 };
	const C = { lng: 2, lat: 0 };

	const fetches: string[] = [];
	const routeThrough = (pts: { lng: number; lat: number }[]) => {
		for (let i = 0; i < pts.length - 1; i++) {
			const key = segmentCacheKey(pts[i], pts[i + 1]);
			if (cache.get(key)) continue;
			fetches.push(key);
			cache.set(key, seg(1000));
		}
	};

	routeThrough([A, B]);
	assert.equal(fetches.length, 1); // A→B fetched

	routeThrough([A, B, C]);
	assert.equal(fetches.length, 2); // only B→C newly fetched; A→B reused
});

test('SegmentCache evicts the oldest entry past its cap', () => {
	const cache = new SegmentCache(2);
	const k1 = segmentCacheKey({ lng: 0, lat: 0 }, { lng: 1, lat: 0 });
	const k2 = segmentCacheKey({ lng: 1, lat: 0 }, { lng: 2, lat: 0 });
	const k3 = segmentCacheKey({ lng: 2, lat: 0 }, { lng: 3, lat: 0 });
	cache.set(k1, seg(1));
	cache.set(k2, seg(2));
	cache.set(k3, seg(3)); // overflows → evicts k1 (oldest)
	assert.equal(cache.size, 2);
	assert.equal(cache.get(k1), undefined);
	assert.equal(cache.get(k2)?.distanceM, 2);
	assert.equal(cache.get(k3)?.distanceM, 3);
});

test('SegmentCache: get() refreshes recency so a reused segment is not evicted', () => {
	const cache = new SegmentCache(2);
	const k1 = segmentCacheKey({ lng: 0, lat: 0 }, { lng: 1, lat: 0 });
	const k2 = segmentCacheKey({ lng: 1, lat: 0 }, { lng: 2, lat: 0 });
	const k3 = segmentCacheKey({ lng: 2, lat: 0 }, { lng: 3, lat: 0 });
	cache.set(k1, seg(1));
	cache.set(k2, seg(2));
	cache.get(k1); // touch k1 → now k2 is oldest
	cache.set(k3, seg(3)); // evicts k2, not k1
	assert.equal(cache.get(k1)?.distanceM, 1);
	assert.equal(cache.get(k2), undefined);
});
