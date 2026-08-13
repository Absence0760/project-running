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

  test('liveElapsedS advances the race clock by the ping age', () {
    // A cut-off deadline runs on wall time. 40 min after the last ping the
    // runner has burned 40 min of their budget whether or not it reached us.
    expect(liveElapsedS(3600, 0), 3600);
    expect(liveElapsedS(3600, 40 * 60000), 3600 + 2400);
    // Sub-second remainders floor, matching the seconds-granularity readout.
    expect(liveElapsedS(3600, 1999), 3601);
  });

  test('liveElapsedS composes with a freshness age', () {
    final f = freshnessFor(now - 5 * 60000, now);
    expect(f.stale, true);
    expect(liveElapsedS(7200, f.ageMs), 7200 + 300);
  });

  test('liveElapsedS never rewinds the clock or invents time it cannot date',
      () {
    // An age we cannot establish advances nothing — better the last known
    // figure than a guess. Same for a future-dated (clock-skewed) ping.
    expect(liveElapsedS(3600, null), 3600);
    expect(liveElapsedS(3600, -60000), 3600);
    expect(liveElapsedS(-10, 60000), 60);
  });
}

(FreshnessBucket, int) _pick(Freshness f) => (f.bucket, f.value);
