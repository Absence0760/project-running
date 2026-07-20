import 'package:flutter_test/flutter_test.dart';

import '../lib/nearby.dart';

void main() {
  test('bucket bounds and count are the shared contract', () {
    expect(kNearbyBucketBoundsM, [2000, 5000, 10000, 25000]);
    expect(kNearbyBucketCount, 5);
  });

  test('distances map to the same buckets as the SQL CASE', () {
    expect(nearbyDistanceBucket(0), 0);
    expect(nearbyDistanceBucket(1999), 0);
    expect(nearbyDistanceBucket(2000), 1);
    expect(nearbyDistanceBucket(4999), 1);
    expect(nearbyDistanceBucket(5000), 2);
    expect(nearbyDistanceBucket(9999), 2);
    expect(nearbyDistanceBucket(10000), 3);
    expect(nearbyDistanceBucket(24999), 3);
    expect(nearbyDistanceBucket(25000), 4);
    expect(nearbyDistanceBucket(500000), 4);
  });

  test('bad distance values clamp to the nearest bucket, never crash', () {
    expect(nearbyDistanceBucket(-1), 0);
    expect(nearbyDistanceBucket(double.nan), 0);
    expect(nearbyDistanceBucket(double.infinity), kNearbyBucketCount - 1);
  });

  test('bucket upper bounds map to the shared metre thresholds', () {
    expect(nearbyBucketUpperBoundM(0), 2000);
    expect(nearbyBucketUpperBoundM(1), 5000);
    expect(nearbyBucketUpperBoundM(2), 10000);
    expect(nearbyBucketUpperBoundM(3), 25000);
    expect(nearbyBucketUpperBoundM(4), isNull);
  });

  test('bucket upper bounds clamp out-of-range indices', () {
    expect(nearbyBucketUpperBoundM(-3), 2000);
    expect(nearbyBucketUpperBoundM(99), isNull);
  });
}
