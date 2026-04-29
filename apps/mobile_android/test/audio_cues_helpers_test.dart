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

  group('formatSpokenDistance', () {
    test('integer km drops the decimal — "5 kilometres" not "5.0"', () {
      expect(formatSpokenDistance(5000), '5 kilometres');
      expect(formatSpokenDistance(10000), '10 kilometres');
    });

    test('non-integer km uses one decimal — "5.2 kilometres"', () {
      expect(formatSpokenDistance(5200), '5.2 kilometres');
    });

    test('< 1 km is spoken in metres', () {
      expect(formatSpokenDistance(800), '800 metres');
      expect(formatSpokenDistance(0), '0 metres');
    });
  });

  group('formatWorkoutStepUtterance', () {
    test('rep step with repIndex/repTotal reads "Rep 3 of 5. ..."', () {
      final out = formatWorkoutStepUtterance(_step());
      expect(out.startsWith('Rep 3 of 5. '), isTrue);
      expect(out, contains('800 metres'));
      expect(out, contains('4 minutes per kilometre'));
    });

    test('rep step without indices falls back to bare "Rep"', () {
      final out = formatWorkoutStepUtterance(
        _step(repIndex: null, repTotal: null),
      );
      expect(out.startsWith('Rep. '), isTrue);
    });

    test('warmup step opens with "Warmup. ..."', () {
      final out = formatWorkoutStepUtterance(
        _step(kind: WorkoutStepKind.warmup, label: 'Warmup'),
      );
      expect(out.startsWith('Warmup. '), isTrue);
    });

    test('recovery / steady / cooldown intros all match their kind', () {
      expect(
        formatWorkoutStepUtterance(_step(kind: WorkoutStepKind.recovery)),
        startsWith('Recovery. '),
      );
      expect(
        formatWorkoutStepUtterance(_step(kind: WorkoutStepKind.steady)),
        startsWith('Steady. '),
      );
      expect(
        formatWorkoutStepUtterance(_step(kind: WorkoutStepKind.cooldown)),
        startsWith('Cooldown. '),
      );
    });

    test('whole-minute pace omits the seconds tail', () {
      final out = formatWorkoutStepUtterance(
        _step(targetPaceSecPerKm: 240),
      );
      expect(out, contains('4 minutes per kilometre'));
      expect(out, isNot(contains('seconds per kilometre')));
    });

    test('non-zero seconds includes the seconds tail', () {
      final out = formatWorkoutStepUtterance(
        _step(targetPaceSecPerKm: 245),
      );
      expect(out, contains('4 minutes 5 seconds per kilometre'));
    });
  });
}
