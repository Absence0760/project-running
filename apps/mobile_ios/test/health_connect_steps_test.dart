import 'dart:io';

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

    // The cutoff is `>`, so exactly the ceiling is a count and one past it is
    // not. An off-by-one here silently drops (or admits) a whole class of
    // sessions, and neither direction is visible on any screen.
    test('the cadence ceiling admits its own boundary and nothing past it',
        () {
      const halfHour = Duration(minutes: 30);
      expect(_steps('run', 9000, duration: halfHour), 9000,
          reason: '9000 steps in 30 min is exactly 300 spm');
      expect(_steps('run', 9001, duration: halfHour), isNull);
    });

    test('a long session is not penalised for a large total', () {
      // A 100-mile finisher walks a quarter of a million steps. The screen
      // is a cadence check, not a size check.
      expect(_steps('run', 250000, duration: const Duration(hours: 30)),
          250000);
    });

    test('a very short session is still measured as a rate, not a count', () {
      expect(_steps('run', 200, duration: const Duration(minutes: 1)), 200);
      expect(_steps('run', 400, duration: const Duration(minutes: 1)), isNull);
    });

    test('a negative-length session claims nothing', () {
      expect(_steps('run', 5000, duration: const Duration(minutes: -5)),
          isNull);
    });
  });

  // The Dart change alone would have shipped a correct-looking helper that
  // still stored null forever: Health Connect has no per-session step field,
  // so the plugin derives `totalSteps` by summing StepsRecords, and that
  // sub-read needs READ_STEPS. It was declared nowhere.
  group('the step read is actually granted and actually stored', () {
    // Each app in the twin owns its own native sub-tree, so the manifest
    // only exists on the Android side; the iOS twin skips rather than fails.
    File? _android(String path) {
      final f = File(path);
      return f.existsSync() ? f : null;
    }

    test('READ_STEPS is declared in the manifest and the rationale list', () {
      final manifest = _android('android/app/src/main/AndroidManifest.xml');
      final rationale =
          _android('android/app/src/main/res/xml/health_permissions.xml');
      if (manifest == null || rationale == null) return;

      const perm = 'android.permission.health.READ_STEPS';
      expect(manifest.readAsStringSync(), contains(perm),
          reason: 'without the manifest entry the plugin\'s StepsRecord '
              'sub-read is never granted and totalSteps is null forever');
      expect(rationale.readAsStringSync(), contains(perm),
          reason: 'Health Connect shows the rationale list; a permission '
              'missing from it cannot be granted from inside the HC app');

      // Negative control: the guard is reading a real declaration list.
      expect(manifest.readAsStringSync(),
          contains('android.permission.health.READ_EXERCISE_ROUTES'));
    });

    test('STEPS is requested on Android only', () {
      // Same call WORKOUT_ROUTE makes for the mirror-image reason: the
      // plugin's HealthKit handler never populates totalSteps, so asking on
      // iOS widens what the build collects — and what its App Store privacy
      // labels must declare — and buys nothing back.
      final src = File('lib/health_connect_importer.dart').readAsStringSync();
      expect(src, contains('if (Platform.isAndroid) HealthDataType.STEPS'),
          reason: 'an unconditional STEPS request is a declared-but-unused '
              'health permission on iOS');
    });

    test('the import stores the step count it was handed', () {
      // The original defect was not a missing API — the number was already
      // on the object the loop held, and the loop dropped it. The unit
      // cases above all pass with that line deleted, so this reads the wiring.
      final src = File('lib/health_connect_importer.dart').readAsStringSync();
      final at = src.indexOf('final steps = stepsForWorkout(');
      expect(at, isNonNegative,
          reason: 'the importer no longer calls stepsForWorkout — every case '
              'above is then testing a helper nothing uses');
      final wiring = src.substring(at, at + 400);
      expect(wiring, contains('totalSteps: value.totalSteps'),
          reason: 'the count has to come off the WorkoutHealthValue the loop '
              'already holds');
      expect(wiring, contains('duration: point.dateTo.difference(point.dateFrom)'),
          reason: 'the cadence screen needs the session window');
      expect(wiring, contains('metadata[MetadataKeys.steps] = steps'),
          reason: 'a screened count that is never stored is the defect § 783 '
              'found, with extra steps');
    });

    test('no cadence_spm is derived and stored beside the steps', () {
      // Health Connect reports steps, so steps is the fact; the existing
      // steps / moving-time derivation is the single place that turns it
      // into a cadence. A second stored value would put two numbers behind
      // one tile.
      final src = File('lib/health_connect_importer.dart').readAsStringSync();
      expect(src.contains('MetadataKeys.cadenceSpm'), isFalse,
          reason: 'the FIT importer stores cadence because a FIT session '
              'reports it directly and carries no step count; Health Connect '
              'is the other way round');
    });
  });
}
