import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/hr_zones.dart';

Waypoint _wp({required int? bpm, DateTime? ts}) =>
    Waypoint(lat: 0, lng: 0, timestamp: ts, bpm: bpm);

void main() {
  group('hrZoneBreakdown', () {
    test('returns empty when no bpm samples', () {
      final track = [
        _wp(bpm: null, ts: DateTime(2026, 1, 1, 10)),
        _wp(bpm: null, ts: DateTime(2026, 1, 1, 10, 0, 1)),
      ];
      expect(hrZoneBreakdown(track), isEmpty);
    });

    test('drops out-of-range bpm samples', () {
      final track = [
        _wp(bpm: 20, ts: DateTime(2026, 1, 1, 10)), // too low
        _wp(bpm: 250, ts: DateTime(2026, 1, 1, 10, 0, 1)), // too high
      ];
      expect(hrZoneBreakdown(track), isEmpty);
      expect(bpmStatsOf(track), isNull);
    });

    test('sample-count fallback when timestamps absent', () {
      final track = [
        _wp(bpm: 100), // Z1 (≤114)
        _wp(bpm: 100), // Z1
        _wp(bpm: 100), // Z1
        _wp(bpm: 200), // Z5 (>171)
      ];
      final buckets = hrZoneBreakdown(track);
      expect(buckets, hasLength(5));
      expect(buckets[0].pct, 75); // 3/4
      expect(buckets[4].pct, 25); // 1/4
      // No timestamps => seconds null on every bucket.
      expect(buckets.every((b) => b.seconds == null), isTrue);
    });

    test('time-weights samples when timestamps are present', () {
      final t = DateTime(2026, 1, 1, 10);
      // 1s of Z1, then 9s of Z5 — Z5 should be much larger than Z1.
      final track = [
        _wp(bpm: 100, ts: t),
        _wp(bpm: 200, ts: t.add(const Duration(seconds: 1))),
        _wp(bpm: 200, ts: t.add(const Duration(seconds: 10))),
      ];
      final buckets = hrZoneBreakdown(track);
      expect(buckets[0].pct, lessThan(buckets[4].pct));
      expect(buckets[4].pct, greaterThan(50));
    });

    test('caps a 30s+ pause so it cannot dominate the breakdown', () {
      final t = DateTime(2026, 1, 1, 10);
      // Fake a long pause: 1 sample of Z1 then a 600s gap to a single Z5
      // sample. Without the 30s cap on each half-gap, the Z5 sample's
      // weight would balloon. With the cap, both halves max out at 30s.
      final track = [
        _wp(bpm: 100, ts: t),
        _wp(bpm: 200, ts: t.add(const Duration(seconds: 600))),
      ];
      final buckets = hrZoneBreakdown(track);
      // Z1 weighted by half the only neighbouring gap (capped at 30s).
      // Z5 weighted by the same. So roughly 50/50.
      expect((buckets[0].pct - buckets[4].pct).abs(), lessThanOrEqualTo(2));
    });

    test('respects custom cutoffs', () {
      final t = DateTime(2026, 1, 1, 10);
      final track = [
        _wp(bpm: 130, ts: t),
        _wp(bpm: 130, ts: t.add(const Duration(seconds: 1))),
      ];
      // Tight cutoffs put 130 firmly in Z5.
      final buckets =
          hrZoneBreakdown(track, cutoffs: const [80, 90, 100, 120, 200]);
      expect(buckets[4].pct, 100);
      expect(buckets[0].pct, 0);
    });

    test('rejects malformed cutoff arrays', () {
      expect(
        () => hrZoneBreakdown(const [], cutoffs: const [80, 90]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('bpmStatsOf', () {
    test('computes min / max / avg over valid samples', () {
      final track = [
        _wp(bpm: 80),
        _wp(bpm: 100),
        _wp(bpm: 150),
        _wp(bpm: null), // ignored
        _wp(bpm: 5), // out of range, ignored
      ];
      final stats = bpmStatsOf(track);
      expect(stats, isNotNull);
      expect(stats!.min, 80);
      expect(stats.max, 150);
      expect(stats.avg, 110); // (80+100+150)/3 = 110
    });
  });

  group('default cutoff derivation', () {
    test('tanakaMaxHr applies 208 − 0.7×age, rounded', () {
      expect(tanakaMaxHr(20), 194);
      expect(tanakaMaxHr(36), 183); // 182.8 → 183
      expect(tanakaMaxHr(60), 166);
    });

    test('zoneCutoffsFromMaxHr is 60/70/80/90/100 % rounded', () {
      expect(zoneCutoffsFromMaxHr(190), [114, 133, 152, 171, 190]);
      expect(zoneCutoffsFromMaxHr(200), [120, 140, 160, 180, 200]);
    });

    test('defaultZoneCutoffs prefers an explicit max-HR override', () {
      expect(defaultZoneCutoffs(maxHrBpm: 200, ageYears: 60),
          [120, 140, 160, 180, 200]);
    });

    test('defaultZoneCutoffs derives from age (Tanaka) when no override', () {
      expect(defaultZoneCutoffs(ageYears: 60), zoneCutoffsFromMaxHr(166));
      // A masters runner's top zone is below the legacy 190 default.
      expect(defaultZoneCutoffs(ageYears: 60)[4] < 190, isTrue);
    });

    test('defaultZoneCutoffs falls back to the legacy 190 ladder', () {
      expect(defaultZoneCutoffs(), [114, 133, 152, 171, 190]);
      expect(defaultZoneCutoffs(maxHrBpm: null, ageYears: null),
          [114, 133, 152, 171, 190]);
    });

    test('defaultZoneCutoffs ignores out-of-range inputs', () {
      // implausible max HR falls through to age
      expect(defaultZoneCutoffs(maxHrBpm: 40, ageYears: 30),
          zoneCutoffsFromMaxHr(tanakaMaxHr(30)));
      // implausible age falls through to the legacy default
      expect(defaultZoneCutoffs(ageYears: 200), [114, 133, 152, 171, 190]);
    });

    // The bounds are the part the THIRD rail shares — the Wear OS
    // `resolveZoneCutoffs` applied `max_hr_bpm` flat until decisions § 1245,
    // so a mistyped 300 gave the same run different zones on the watch and the
    // phone. `max_hr_bpm` is a jsonb prefs key with no CHECK, so nothing but
    // these reads stands between a typo and a zone ladder.
    test('the usable ranges are the bounds defaultZoneCutoffs applies', () {
      expect(defaultZoneCutoffs(maxHrBpm: kMaxHrBpmMin)[4], kMaxHrBpmMin);
      expect(defaultZoneCutoffs(maxHrBpm: kMaxHrBpmMax)[4], kMaxHrBpmMax);
      expect(defaultZoneCutoffs(maxHrBpm: kMaxHrBpmMin - 1),
          [114, 133, 152, 171, 190]);
      expect(defaultZoneCutoffs(maxHrBpm: kMaxHrBpmMax + 1),
          [114, 133, 152, 171, 190]);

      expect(defaultZoneCutoffs(ageYears: kTanakaAgeMin),
          zoneCutoffsFromMaxHr(tanakaMaxHr(kTanakaAgeMin)));
      expect(defaultZoneCutoffs(ageYears: kTanakaAgeMax),
          zoneCutoffsFromMaxHr(tanakaMaxHr(kTanakaAgeMax)));
      expect(defaultZoneCutoffs(ageYears: kTanakaAgeMin - 1),
          [114, 133, 152, 171, 190]);
      expect(defaultZoneCutoffs(ageYears: kTanakaAgeMax + 1),
          [114, 133, 152, 171, 190]);
    });

    // 0 survives every null check and is exactly what an emptied number input
    // posts. Applied flat it yields an all-zero ladder that puts every real
    // sample above Z5 — the shape the watch rail had.
    test('a zero max HR is ignored, not applied as a ceiling', () {
      expect(defaultZoneCutoffs(maxHrBpm: 0), [114, 133, 152, 171, 190]);
      expect(defaultZoneCutoffs(maxHrBpm: -1), [114, 133, 152, 171, 190]);
    });
  });
}
