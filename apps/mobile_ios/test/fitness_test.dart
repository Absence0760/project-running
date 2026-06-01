import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/fitness.dart';

Run _r({
  required double distance,
  required int durationS,
  DateTime? startedAt,
  RunSource source = RunSource.app,
  Map<String, dynamic>? metadata,
}) =>
    Run(
      id: 'r${distance.toInt()}-${durationS}',
      startedAt: startedAt ?? DateTime.utc(2026, 1, 1),
      duration: Duration(seconds: durationS),
      distanceMetres: distance,
      track: const [],
      source: source,
      metadata: metadata,
    );

void main() {
  group('vdotFromRun', () {
    test('returns null for runs that are too short', () {
      expect(vdotFromRun(500, 600), isNull);
      expect(vdotFromRun(5000, 60), isNull);
    });

    test('produces a sensible VDOT for a 20:00 5k', () {
      final v = vdotFromRun(5000, 1200);
      expect(v, isNotNull);
      // Daniels' tables put a 20:00 5k at VDOT 49.8 ± a touch.
      expect(v!, inInclusiveRange(48, 52));
    });

    test('produces a sensible VDOT for a 3:30:00 marathon', () {
      final v = vdotFromRun(42195, 12600);
      expect(v, isNotNull);
      // VDOT for 3:30 marathon sits in the mid-40s.
      expect(v!, inInclusiveRange(42, 48));
    });
  });

  group('qualifyingRuns', () {
    // Persona round-5 runner-comeback. Mirrors the distance-floor tests in
    // fitness.test.ts — the floor dropped from 3 km to 1.5 km.
    test('drops sub-1.5km runs (too noisy for VDOT)', () {
      final longEnough = _r(distance: 5000, durationS: 1500);
      final tooShort = _r(distance: 1000, durationS: 360);
      final qualifying = qualifyingRuns([longEnough, tooShort]);
      expect(qualifying, hasLength(1));
      expect(qualifying.first.id, longEnough.id);
    });

    test('admits a sustained 1.5-2km comeback run', () {
      final comeback = _r(distance: 1800, durationS: 600);
      expect(qualifyingRuns([comeback]), hasLength(1));
    });

    test('drops indoor/treadmill runs (belt distance is not VDOT-worthy)', () {
      // Mirrors the indoor-exclusion test in fitness.test.ts.
      final outdoor = _r(distance: 5000, durationS: 1500);
      final treadmill = _r(
        distance: 5000,
        durationS: 1500,
        source: RunSource.garmin,
        metadata: {'indoor': true},
      );
      final qualifying = qualifyingRuns([outdoor, treadmill]);
      expect(qualifying, hasLength(1));
      expect(qualifying.first.id, outdoor.id);
    });
  });

  group('currentVdot', () {
    test('picks the best qualifying run in the last 90 days', () {
      final now = DateTime.utc(2026, 5, 1);
      final runs = [
        _r(distance: 5000, durationS: 1500, startedAt: now.subtract(const Duration(days: 30))),
        _r(distance: 5000, durationS: 1200, startedAt: now.subtract(const Duration(days: 10))),
        _r(distance: 5000, durationS: 1100, startedAt: now.subtract(const Duration(days: 200))), // too old
      ];
      final v = currentVdot(runs, now: now);
      expect(v, isNotNull);
      // Best in-window is the 20-min 5k.
      final best = vdotFromRun(5000, 1200);
      expect(v!, closeTo(best!, 0.001));
    });

    test('returns null when no qualifying run', () {
      expect(currentVdot(const []), isNull);
      expect(
          currentVdot([_r(distance: 100, durationS: 60)]), isNull); // too short
    });

    test('excludes parkrun and race sources from VDOT qualifying set', () {
      final r = _r(
        distance: 5000,
        durationS: 900,
        source: RunSource.parkrun,
      );
      expect(currentVdot([r]), isNull);
    });
  });

  group('thresholdPaceSecPerKmFromVdot', () {
    test('null / non-positive VDOT returns null', () {
      expect(thresholdPaceSecPerKmFromVdot(null), isNull);
      expect(thresholdPaceSecPerKmFromVdot(0), isNull);
      expect(thresholdPaceSecPerKmFromVdot(-5), isNull);
    });

    test('matches Daniels T-pace tables across the meaningful VDOT band', () {
      // Daniels publishes: VDOT 50 → 4:15/km (255 s/km),
      // VDOT 60 → 3:40/km (220 s/km), VDOT 70 → 3:14/km (194 s/km).
      // Allow ±10 s of slack.
      expect(thresholdPaceSecPerKmFromVdot(50)!, closeTo(255, 10));
      expect(thresholdPaceSecPerKmFromVdot(60)!, closeTo(220, 10));
      expect(thresholdPaceSecPerKmFromVdot(70)!, closeTo(194, 10));
    });

    test('higher VDOT yields a faster (smaller) threshold pace', () {
      final beginner = thresholdPaceSecPerKmFromVdot(30)!;
      final intermediate = thresholdPaceSecPerKmFromVdot(50)!;
      final elite = thresholdPaceSecPerKmFromVdot(70)!;
      expect(intermediate, lessThan(beginner));
      expect(elite, lessThan(intermediate));
    });
  });

  group('runTss', () {
    test('returns 0 for tiny inputs', () {
      expect(runTss(50, 60, 300), 0);
      expect(runTss(1000, 10, 300), 0);
      expect(runTss(1000, 600, 0), 0);
    });

    test('matches Coggan-style ranges for a steady 1h at threshold', () {
      // 1 h at threshold pace is by definition TSS=100.
      final tss = runTss(10000, 3600, 360);
      expect(tss, closeTo(100, 1.0));
    });

    test('faster-than-threshold pushes TSS above 100', () {
      // Same hour, but at 5:00/km — well under a 6:00/km threshold.
      final tss = runTss(12000, 3600, 360);
      expect(tss, greaterThan(100));
    });
  });

  group('trainingLoad', () {
    test('returns nulls when threshold or runs missing', () {
      final l1 = trainingLoad(const [], 360);
      expect(l1.acuteLoad, isNull);

      final l2 = trainingLoad([
        _r(distance: 5000, durationS: 1200),
      ], null);
      expect(l2.acuteLoad, isNull);
    });

    test('produces non-null ATL/CTL/TSB for a stream of runs', () {
      final now = DateTime.utc(2026, 5, 1);
      final runs = [
        for (var i = 0; i < 30; i++)
          _r(
            distance: 8000,
            durationS: 2400,
            startedAt: now.subtract(Duration(days: i)),
          ),
      ];
      final l = trainingLoad(runs, 360, now: now);
      expect(l.acuteLoad, isNotNull);
      expect(l.chronicLoad, isNotNull);
      expect(l.trainingStressBal, isNotNull);
      expect(l.acuteLoad! > 0, isTrue);
      expect(l.chronicLoad! > 0, isTrue);
    });
  });

  group('recoveryAdvice', () {
    test('flags low CTL as still building', () {
      final s = recoveryAdvice(0, 5);
      expect(s.toLowerCase(), contains('building'));
    });

    test('flags very negative TSB as heavily loaded', () {
      final s = recoveryAdvice(-40, 50);
      expect(s.toLowerCase(), contains('heavily loaded'));
    });

    test('flags very positive TSB as fresh', () {
      final s = recoveryAdvice(30, 50);
      expect(s.toLowerCase(), contains('fresh'));
    });

    test('returns the empty-data string when inputs are null', () {
      expect(recoveryAdvice(null, 50), contains('Not enough'));
      expect(recoveryAdvice(0, null), contains('Not enough'));
    });

    test('returning-from-layoff overrides freshness rungs (comeback #29)', () {
      final normal = recoveryAdvice(40, 50);
      final returning = recoveryAdvice(40, 50, returningFromLayoff: true);
      expect(returning, isNot(equals(normal)));
      expect(returning.toLowerCase(), anyOf(contains('rebuild'), contains('back')));
    });
  });

  group('isReturningFromLayoff (comeback #29)', () {
    final now = DateTime.utc(2026, 4, 30, 7);
    test('true when a recent run follows a >28d gap', () {
      final runs = [
        _r(distance: 10000, durationS: 3000, startedAt: DateTime.utc(2025, 12, 1, 7)),
        _r(distance: 5000, durationS: 1800, startedAt: DateTime.utc(2026, 4, 29, 7)),
      ];
      expect(isReturningFromLayoff(runs, now: now), isTrue);
    });

    test('false for a steady runner with no gap', () {
      final runs = [
        _r(distance: 8000, durationS: 2400, startedAt: DateTime.utc(2026, 4, 20, 7)),
        _r(distance: 8000, durationS: 2400, startedAt: DateTime.utc(2026, 4, 27, 7)),
        _r(distance: 8000, durationS: 2400, startedAt: DateTime.utc(2026, 4, 29, 7)),
      ];
      expect(isReturningFromLayoff(runs, now: now), isFalse);
    });

    test('false for a single run (new runner, not returning)', () {
      final runs = [
        _r(distance: 5000, durationS: 1800, startedAt: DateTime.utc(2026, 4, 29, 7)),
      ];
      expect(isReturningFromLayoff(runs, now: now), isFalse);
    });

    test('false when the gap is ongoing (not currently active)', () {
      final runs = [
        _r(distance: 10000, durationS: 3000, startedAt: DateTime.utc(2026, 2, 1, 7)),
        _r(distance: 10000, durationS: 3000, startedAt: DateTime.utc(2026, 3, 21, 7)),
      ];
      expect(isReturningFromLayoff(runs, now: now), isFalse);
    });
  });

  group('computeSnapshot', () {
    test('hits the happy path on a varied run list', () {
      final now = DateTime.utc(2026, 5, 1);
      final runs = [
        for (var i = 0; i < 10; i++)
          _r(
            distance: 8000 + i * 200,
            durationS: 2400 - i * 30,
            startedAt: now.subtract(Duration(days: i * 3)),
          ),
      ];
      final snap = computeSnapshot(runs, now: now);
      expect(snap.vdot, isNotNull);
      expect(snap.vo2Max, snap.vdot); // identity per design
      expect(snap.qualifyingRunCount, 10);
    });

    test('returns nulls for an empty run list', () {
      final snap = computeSnapshot(const []);
      expect(snap.vdot, isNull);
      expect(snap.vo2Max, isNull);
      expect(snap.acuteLoad, isNull);
      expect(snap.qualifyingRunCount, 0);
    });
  });
}
