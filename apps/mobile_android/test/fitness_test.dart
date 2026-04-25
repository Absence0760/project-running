import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/fitness.dart';

Run _r({
  required double distance,
  required int durationS,
  DateTime? startedAt,
  RunSource source = RunSource.app,
}) =>
    Run(
      id: 'r${distance.toInt()}-${durationS}',
      startedAt: startedAt ?? DateTime.utc(2026, 1, 1),
      duration: Duration(seconds: durationS),
      distanceMetres: distance,
      track: const [],
      source: source,
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

    test('ignores manually-entered runs (no source signal)', () {
      // Even though a 15-min 5k looks great, manual entries don't qualify.
      // (`RunSource.race` and `parkrun` aren't in the qualifying set either.)
      final r = _r(
        distance: 5000,
        durationS: 900,
        source: RunSource.parkrun,
      );
      expect(currentVdot([r]), isNull);
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
