import 'package:flutter_test/flutter_test.dart';

import '../lib/health_connect_importer.dart';

int? _steps(
  String activityType,
  int? totalSteps, {
  Duration duration = const Duration(minutes: 30),
}) =>
    HealthConnectImporter.stepsForWorkout(
      activityType: activityType,
      totalSteps: totalSteps,
      duration: duration,
    );

void main() {
  group('HealthConnectImporter.stepsForWorkout (#664)', () {
    test('a foot-powered session with steps keeps its count', () {
      expect(_steps('run', 5400), 5400);
      expect(_steps('walk', 3000), 3000);
      expect(_steps('hike', 4200), 4200);
    });

    // Health Connect has no per-session step field, so a session whose
    // window holds no StepsRecord — and a session whose StepsRecord the
    // READ_STEPS grant is missing for — both arrive as null. Neither can be
    // told from the other here, and both mean the same thing to the run:
    // import it exactly as before, with no steps key and so no cadence.
    test('a session with no readable steps writes nothing', () {
      expect(_steps('run', null), isNull);
    });

    test('a zero or negative count is an absence, not a count', () {
      expect(_steps('run', 0), isNull);
      expect(_steps('run', -1), isNull);
    });

    // The plugin sums every StepsRecord overlapping the session window
    // whoever wrote it, so a whole-day total from another app lands on a
    // short session as a count no leg produces.
    test('a count implying an impossible cadence is dropped whole', () {
      const halfHour = Duration(minutes: 30);
      expect(_steps('run', 5400, duration: halfHour), 5400);
      expect(_steps('run', 12000, duration: halfHour), isNull);
    });

    test('a zero-length session yields no cadence to sanity-check against', () {
      expect(_steps('run', 5000, duration: Duration.zero), isNull);
    });

    // preferences.dart's stride table: "pedometer not meaningful for
    // cycling". The phone counts pocket jostle, the tile would call it spm.
    test('a ride is excluded even when Health Connect reports steps', () {
      expect(_steps('cycle', 2400), isNull);
    });

    // decisions § 598, the same call gearBackfillCandidates makes: name the
    // bike, never enumerate the foot-powered set, or the next activity_type
    // added to the CHECK silently loses its steps.
    test('an activity type this helper has never heard of keeps its steps',
        () {
      expect(_steps('stroller', 4800), 4800);
      expect(_steps('snowshoe', 4800), 4800);
    });
  });
}
