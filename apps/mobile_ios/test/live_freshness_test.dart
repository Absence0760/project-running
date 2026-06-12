import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/live_freshness.dart';

const int now = 1700000000000;

void main() {
  test('a future-dated ping (clock skew) clamps to age 0, never negative', () {
    final f = freshnessFor(now + 5000, now);
    expect(f.ageMs, 0);
    expect(f.stale, false);
    expect(f.bucket, FreshnessBucket.now);
  });

  test('stale threshold is inclusive at the boundary', () {
    final justFresh = freshnessFor(now - (liveStaleAfterMs - 1), now);
    expect(justFresh.stale, false, reason: 'one ms under the threshold is still fresh');
    final justStale = freshnessFor(now - liveStaleAfterMs, now);
    expect(justStale.stale, true, reason: 'exactly at the threshold is stale');
  });

  test('a long no-signal stretch is honestly stale, not a fresh Live dot', () {
    final eighteenHours = freshnessFor(now - 18 * 3600000, now);
    expect(eighteenHours.stale, true);
    expect(eighteenHours.bucket, FreshnessBucket.hours);
    expect(eighteenHours.value, 18);
  });

  test('bucket boundaries', () {
    expect(_pick(freshnessFor(now - 9000, now)), (FreshnessBucket.now, 0));
    expect(_pick(freshnessFor(now - 10000, now)), (FreshnessBucket.seconds, 10));
    expect(_pick(freshnessFor(now - 59000, now)), (FreshnessBucket.seconds, 59));
    expect(_pick(freshnessFor(now - 60000, now)), (FreshnessBucket.minutes, 1));
    expect(_pick(freshnessFor(now - 59 * 60000, now)), (FreshnessBucket.minutes, 59));
    expect(_pick(freshnessFor(now - 3600000, now)), (FreshnessBucket.hours, 1));
    expect(_pick(freshnessFor(now - 23 * 3600000, now)), (FreshnessBucket.hours, 23));
    expect(_pick(freshnessFor(now - 24 * 3600000, now)), (FreshnessBucket.days, 1));
    expect(_pick(freshnessFor(now - 50 * 3600000, now)), (FreshnessBucket.days, 2));
  });

  test('an exactly-now ping reads as fresh "now"', () {
    final f = freshnessFor(now, now);
    expect(f.ageMs, 0);
    expect(f.bucket, FreshnessBucket.now);
    expect(f.stale, false);
  });
}

(FreshnessBucket, int) _pick(Freshness f) => (f.bucket, f.value);
