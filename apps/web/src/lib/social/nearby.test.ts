import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	NEARBY_BUCKET_BOUNDS_M,
	NEARBY_BUCKET_COUNT,
	nearbyDistanceBucket,
	nearbyBucketUpperBoundM,
} from './nearby';

test('bucket bounds and count are the shared contract', () => {
	assert.deepEqual([...NEARBY_BUCKET_BOUNDS_M], [2000, 5000, 10000, 25000]);
	assert.equal(NEARBY_BUCKET_COUNT, 5);
});

test('distances map to the same buckets as the SQL CASE', () => {
	assert.equal(nearbyDistanceBucket(0), 0);
	assert.equal(nearbyDistanceBucket(1999), 0);
	assert.equal(nearbyDistanceBucket(2000), 1);
	assert.equal(nearbyDistanceBucket(4999), 1);
	assert.equal(nearbyDistanceBucket(5000), 2);
	assert.equal(nearbyDistanceBucket(9999), 2);
	assert.equal(nearbyDistanceBucket(10000), 3);
	assert.equal(nearbyDistanceBucket(24999), 3);
	assert.equal(nearbyDistanceBucket(25000), 4);
	assert.equal(nearbyDistanceBucket(500000), 4);
});

test('bad distance values clamp to the nearest bucket, never crash', () => {
	assert.equal(nearbyDistanceBucket(-1), 0);
	assert.equal(nearbyDistanceBucket(Number.NaN), 0);
	assert.equal(nearbyDistanceBucket(Number.POSITIVE_INFINITY), NEARBY_BUCKET_COUNT - 1);
});

test('bucket upper bounds map to the shared metre thresholds', () => {
	assert.equal(nearbyBucketUpperBoundM(0), 2000);
	assert.equal(nearbyBucketUpperBoundM(1), 5000);
	assert.equal(nearbyBucketUpperBoundM(2), 10000);
	assert.equal(nearbyBucketUpperBoundM(3), 25000);
	assert.equal(nearbyBucketUpperBoundM(4), null);
});

test('bucket upper bounds clamp out-of-range indices', () => {
	assert.equal(nearbyBucketUpperBoundM(-3), 2000);
	assert.equal(nearbyBucketUpperBoundM(99), null);
});
