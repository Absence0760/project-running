import 'package:flutter_test/flutter_test.dart';

import '../lib/race_match.dart';

void main() {
  group('raceDistanceBand', () {
    test('buckets recognised distances', () {
      expect(raceDistanceBand(5000), RaceDistanceBand.fiveK);
      expect(raceDistanceBand(10000), RaceDistanceBand.tenK);
      expect(raceDistanceBand(21097), RaceDistanceBand.half);
      expect(raceDistanceBand(42195), RaceDistanceBand.marathon);
      expect(raceDistanceBand(50000), RaceDistanceBand.ultra);
      expect(raceDistanceBand(160934), RaceDistanceBand.ultra);
    });

    test('tolerance edges', () {
      expect(raceDistanceBand(4500), RaceDistanceBand.fiveK);
      expect(raceDistanceBand(5500), RaceDistanceBand.fiveK);
      expect(raceDistanceBand(9000), RaceDistanceBand.tenK);
      expect(raceDistanceBand(11000), RaceDistanceBand.tenK);
    });

    test('returns null for unrecognised / tiny distances', () {
      expect(raceDistanceBand(4499), isNull);
      expect(raceDistanceBand(7000), isNull);
      expect(raceDistanceBand(15000), isNull);
      expect(raceDistanceBand(null), isNull);
      expect(raceDistanceBand(double.nan), isNull);
    });
  });

  group('raceMatchScore', () {
    test('different calendar day scores 0', () {
      final s = raceMatchScore(
        const RunMatchInput(
            runDate: '2025-09-20T09:00:00Z', runStartLatLng: null, runDistanceM: 21097),
        const ListingMatchInput(raceDate: '2025-09-21', distanceM: 21097, distanceMAway: 100),
      );
      expect(s, 0);
    });

    test('same day with near start + matching band scores high', () {
      final s = raceMatchScore(
        const RunMatchInput(
            runDate: '2025-09-21T09:00:00Z',
            runStartLatLng: LatLng(0, 0),
            runDistanceM: 21097),
        const ListingMatchInput(raceDate: '2025-09-21', distanceM: 21097, distanceMAway: 200),
      );
      expect(s, greaterThan(0.95));
    });

    test('same day only (no proximity, no band) normalises to 1', () {
      final s = raceMatchScore(
        const RunMatchInput(runDate: '2025-09-21', runStartLatLng: null, runDistanceM: null),
        const ListingMatchInput(raceDate: '2025-09-21', distanceM: null, distanceMAway: null),
      );
      expect(s, 1);
    });

    test('same day + matching band but no proximity still strong', () {
      final s = raceMatchScore(
        const RunMatchInput(runDate: '2025-09-21', runStartLatLng: null, runDistanceM: 5000),
        const ListingMatchInput(raceDate: '2025-09-21', distanceM: 5000, distanceMAway: null),
      );
      expect(s, 1);
    });

    test('same day + mismatched band lowers the score', () {
      final s = raceMatchScore(
        const RunMatchInput(runDate: '2025-09-21', runStartLatLng: null, runDistanceM: 5000),
        const ListingMatchInput(raceDate: '2025-09-21', distanceM: 42195, distanceMAway: null),
      );
      expect((s - 0.5 / 0.7).abs() < 1e-9, isTrue);
    });

    test('proximity falloff is linear to the radius edge', () {
      final s = raceMatchScore(
        const RunMatchInput(
            runDate: '2025-09-21', runStartLatLng: LatLng(0, 0), runDistanceM: null),
        const ListingMatchInput(
            raceDate: '2025-09-21', distanceM: null, distanceMAway: raceMatchRadiusM / 2),
      );
      expect((s - 0.65 / 0.8).abs() < 1e-9, isTrue);
    });

    test('start beyond the radius contributes no proximity points', () {
      final s = raceMatchScore(
        const RunMatchInput(
            runDate: '2025-09-21', runStartLatLng: LatLng(0, 0), runDistanceM: null),
        const ListingMatchInput(
            raceDate: '2025-09-21', distanceM: null, distanceMAway: raceMatchRadiusM * 3),
      );
      expect((s - 0.5 / 0.8).abs() < 1e-9, isTrue);
    });

    test('full ISO timestamp compares on the calendar day', () {
      final s = raceMatchScore(
        const RunMatchInput(
            runDate: '2025-09-21T23:59:00Z', runStartLatLng: null, runDistanceM: 10000),
        const ListingMatchInput(raceDate: '2025-09-21', distanceM: 10000, distanceMAway: null),
      );
      expect(s, 1);
    });
  });

  group('isRaceMatchCandidate', () {
    test('gates on the threshold', () {
      const near = RunMatchInput(
          runDate: '2025-09-21', runStartLatLng: LatLng(0, 0), runDistanceM: 21097);
      expect(
        isRaceMatchCandidate(near,
            const ListingMatchInput(raceDate: '2025-09-21', distanceM: 21097, distanceMAway: 100)),
        isTrue,
      );
      expect(
        isRaceMatchCandidate(near,
            const ListingMatchInput(raceDate: '2025-09-22', distanceM: 21097, distanceMAway: 100)),
        isFalse,
      );
    });
  });

  group('haversineMetres', () {
    test('~0 for identical points', () {
      expect(haversineMetres(const LatLng(51.5, -0.1), const LatLng(51.5, -0.1)) < 1e-6, isTrue);
    });

    test('~111km per degree of latitude', () {
      final d = haversineMetres(const LatLng(0, 0), const LatLng(1, 0));
      expect((d - 111195).abs() < 500, isTrue);
    });
  });

  test('raceMatchThreshold is the documented 0.5', () {
    expect(raceMatchThreshold, 0.5);
  });
}
