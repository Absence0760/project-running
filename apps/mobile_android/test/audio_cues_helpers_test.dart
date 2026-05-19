import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;
import '../lib/audio_cues.dart';
import '../lib/preferences.dart';

WorkoutStep _step({
  WorkoutStepKind kind = WorkoutStepKind.rep,
  int? repIndex = 3,
  int? repTotal = 5,
  double targetDistanceMetres = 800,
  int targetPaceSecPerKm = 240,
  String label = 'Rep',
}) =>
    WorkoutStep(
      kind: kind,
      repIndex: repIndex,
      repTotal: repTotal,
      targetDistanceMetres: targetDistanceMetres,
      targetPaceSecPerKm: targetPaceSecPerKm,
      label: label,
    );

void main() {
  group('formatSpeedUtterance', () {
    test('km branch — "Speed, 12.0 kilometres per hour" for 5:00 /km', () {
      expect(formatSpeedUtterance(300, DistanceUnit.km),
          'Speed, 12.0 kilometres per hour');
    });

    test('mi branch — divides km/h by 1.609344 and uses miles per hour', () {
      // 6:00 /km → 10 km/h → ~6.2 mph
      expect(formatSpeedUtterance(360, DistanceUnit.mi),
          'Speed, 6.2 miles per hour');
    });

    test('returns empty string for null or non-positive pace', () {
      expect(formatSpeedUtterance(null, DistanceUnit.km), '');
      expect(formatSpeedUtterance(0, DistanceUnit.km), '');
      expect(formatSpeedUtterance(-5, DistanceUnit.mi), '');
    });
  });

  group('formatPaceUtterance', () {
    test('km branch — "Pace, 5 minutes 30 seconds per kilometre"', () {
      expect(formatPaceUtterance(330, DistanceUnit.km),
          'Pace, 5 minutes 30 seconds per kilometre');
    });

    test('mi branch — scales seconds-per-km by 1609.344/1000 and says per mile',
        () {
      // 6:00 /km → 6 * 1.609344 = 9 minutes 39.6 seconds — truncates to
      // "9 minutes 39 seconds per mile" (the formatter takes the
      // integer seconds floor).
      expect(formatPaceUtterance(360, DistanceUnit.mi),
          'Pace, 9 minutes 39 seconds per mile');
    });

    test('returns empty string for null or non-positive pace', () {
      expect(formatPaceUtterance(null, DistanceUnit.km), '');
      expect(formatPaceUtterance(0, DistanceUnit.km), '');
    });
  });

  group('formatSpokenDistance (km mode)', () {
    test('integer km drops the decimal — "5 kilometres" not "5.0"', () {
      expect(formatSpokenDistance(5000, DistanceUnit.km), '5 kilometres');
      expect(formatSpokenDistance(10000, DistanceUnit.km), '10 kilometres');
    });

    test('non-integer km uses one decimal — "5.2 kilometres"', () {
      expect(formatSpokenDistance(5200, DistanceUnit.km), '5.2 kilometres');
    });

    test('< 1 km is spoken in metres', () {
      expect(formatSpokenDistance(800, DistanceUnit.km), '800 metres');
      expect(formatSpokenDistance(0, DistanceUnit.km), '0 metres');
    });
  });

  group('formatSpokenDistance (mi mode)', () {
    // Regression net: mi-mode users previously heard "5 kilometres"
    // even though the on-screen distance read "3.11 mi". Pin the
    // unit-aware path so the spoken value matches the visual.
    test('integer miles drops the decimal — singular vs plural', () {
      // 1 mile = 1609.344 m; round to .roundToDouble() matches exact
      // metre values here.
      expect(formatSpokenDistance(1609.344, DistanceUnit.mi), '1 mile');
      expect(formatSpokenDistance(5 * 1609.344, DistanceUnit.mi), '5 miles');
    });

    test('non-integer miles uses one decimal — "3.1 miles"', () {
      expect(formatSpokenDistance(5000, DistanceUnit.mi), '3.1 miles');
    });

    test('< 1 mile is spoken in yards', () {
      // 800 m × 1.09361 ≈ 875 yards
      expect(formatSpokenDistance(800, DistanceUnit.mi), '875 yards');
      expect(formatSpokenDistance(0, DistanceUnit.mi), '0 yards');
    });

    test('boundary at exactly 1 mile reads "1 mile" not "1 miles"', () {
      // Singular contract — a regression that emitted "1 miles" would
      // catch every screen-reader user with imperial pref. Pin it.
      expect(
        formatSpokenDistance(1609.344, DistanceUnit.mi),
        '1 mile',
      );
    });
  });

  group('formatWorkoutStepUtterance (km mode)', () {
    test('rep step with repIndex/repTotal reads "Rep 3 of 5. ..."', () {
      final out = formatWorkoutStepUtterance(_step(), DistanceUnit.km);
      expect(out.startsWith('Rep 3 of 5. '), isTrue);
      expect(out, contains('800 metres'));
      expect(out, contains('4 minutes per kilometre'));
    });

    test('rep step without indices falls back to bare "Rep"', () {
      final out = formatWorkoutStepUtterance(
        _step(repIndex: null, repTotal: null),
        DistanceUnit.km,
      );
      expect(out.startsWith('Rep. '), isTrue);
    });

    test('warmup step opens with "Warmup. ..."', () {
      final out = formatWorkoutStepUtterance(
        _step(kind: WorkoutStepKind.warmup, label: 'Warmup'),
        DistanceUnit.km,
      );
      expect(out.startsWith('Warmup. '), isTrue);
    });

    test('recovery / steady / cooldown intros all match their kind', () {
      expect(
        formatWorkoutStepUtterance(
            _step(kind: WorkoutStepKind.recovery), DistanceUnit.km),
        startsWith('Recovery. '),
      );
      expect(
        formatWorkoutStepUtterance(
            _step(kind: WorkoutStepKind.steady), DistanceUnit.km),
        startsWith('Steady. '),
      );
      expect(
        formatWorkoutStepUtterance(
            _step(kind: WorkoutStepKind.cooldown), DistanceUnit.km),
        startsWith('Cooldown. '),
      );
    });

    test('whole-minute pace omits the seconds tail', () {
      final out = formatWorkoutStepUtterance(
        _step(targetPaceSecPerKm: 240),
        DistanceUnit.km,
      );
      expect(out, contains('4 minutes per kilometre'));
      expect(out, isNot(contains('seconds per kilometre')));
    });

    test('non-zero seconds includes the seconds tail', () {
      final out = formatWorkoutStepUtterance(
        _step(targetPaceSecPerKm: 245),
        DistanceUnit.km,
      );
      expect(out, contains('4 minutes 5 seconds per kilometre'));
    });
  });

  group('formatWorkoutStepUtterance (mi mode)', () {
    // Mi-mode regression nets — a workout step's spoken distance +
    // pace must both honour the unit pref. A regression that left
    // only the distance unit-aware would announce "1 mile at 4
    // minutes per kilometre" — confusing for an imperial runner.
    test('distance and pace both render in imperial', () {
      final out = formatWorkoutStepUtterance(
        _step(targetDistanceMetres: 1609.344, targetPaceSecPerKm: 240),
        DistanceUnit.mi,
      );
      expect(out, contains('1 mile'));
      // 240 sec/km × 1.609344 km/mi = ~386 sec/mi → "6 minutes 26 seconds"
      // Allow the seconds round (toRound on the integer division).
      expect(out, contains('per mile'));
      expect(out, isNot(contains('per kilometre')));
    });

    test('whole-minute /mi pace omits seconds tail in mi mode', () {
      // 7-minute-per-mile pace = 7 × 60 / 1.609344 ≈ 261 sec/km
      // (close enough that the formatted output reads "7 minutes per
      // mile"). We feed back-computed sec/km so the math is exact.
      const targetSecPerMile = 7 * 60;
      final secPerKm = (targetSecPerMile / 1.609344).round();
      final out = formatWorkoutStepUtterance(
        _step(targetPaceSecPerKm: secPerKm),
        DistanceUnit.mi,
      );
      expect(out, contains('7 minutes per mile'));
      expect(out, isNot(contains('seconds per mile')));
    });
  });
}
