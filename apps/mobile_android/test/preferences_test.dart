// Unit tests for the pure-logic surface of `lib/preferences.dart` —
// specifically the `ActivityType` enum's per-activity getters that
// drive recording-stack behaviour (pace vs speed, split cadence,
// GPS filter, jitter floor, stride fallback, max plausible speed).
//
// The `Preferences` class itself wraps SharedPreferences and is
// covered by the screen-level + integration tests; these unit tests
// scope to the enum's pure methods so they run in <100ms with no
// platform bindings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/preferences.dart';

void main() {
  group('ActivityType.label', () {
    // Reason: the activity-type chip row on RunScreen, all dashboard
    // cards, the run-detail header, and every share-card binding read
    // `t.label` for display. A regression that re-cased / re-spelled
    // any of these (e.g. "Running") would surface everywhere at once.
    test('returns the canonical capitalised English noun', () {
      expect(ActivityType.run.label, 'Run');
      expect(ActivityType.walk.label, 'Walk');
      expect(ActivityType.cycle.label, 'Cycle');
      // Surfaced as "Trail run" — see kdoc on label getter. The
      // enum name stays `hike` for back-compat with the SQL CHECK
      // constraint + Strava / Health Connect importer mappings.
      expect(ActivityType.hike.label, 'Trail run');
    });
  });

  group('ActivityType.icon', () {
    // Reason: the run-screen chip + every list-view per-row icon
    // dispatch on this getter. A mis-mapped icon (e.g. cycle → terrain)
    // would ship a confusing UX but no functional failure, so without
    // a test the regression would land silently.
    test('maps to the matching Material symbol', () {
      expect(ActivityType.run.icon, Icons.directions_run);
      expect(ActivityType.walk.icon, Icons.directions_walk);
      expect(ActivityType.cycle.icon, Icons.directions_bike);
      expect(ActivityType.hike.icon, Icons.terrain);
    });
  });

  group('ActivityType.usesSpeed', () {
    // Reason: cycling shows km/h (or mph) instead of min/km pace.
    // Every pace formatter + the recording-stack pace-alert decision
    // branches on this single boolean. A regression flipping the
    // truth condition (e.g. `this != ActivityType.cycle`) would
    // invert every screen — runs would display in km/h and rides
    // would announce min/km splits.
    test('cycle uses speed, others use pace', () {
      expect(ActivityType.cycle.usesSpeed, isTrue);
      expect(ActivityType.run.usesSpeed, isFalse);
      expect(ActivityType.walk.usesSpeed, isFalse);
      expect(ActivityType.hike.usesSpeed, isFalse);
    });
  });

  group('ActivityType.kcalPerKgPerKm', () {
    test('values land in a plausible metabolic range', () {
      // 0.4–1.2 kcal/kg/km covers cycling through stroller-running per the
      // approximate METs translation (stroller pushes a load so it sits just
      // above open running at 1.1). A regression introducing e.g. 10.0 (10×
      // too big) would inflate the dashboard's calories number by an order of
      // magnitude.
      for (final t in ActivityType.values) {
        expect(t.kcalPerKgPerKm, greaterThanOrEqualTo(0.4));
        expect(t.kcalPerKgPerKm, lessThanOrEqualTo(1.2));
      }
    });

    test('stroller burns at least as much as open running (#51)', () {
      expect(
        ActivityType.stroller.kcalPerKgPerKm,
        greaterThanOrEqualTo(ActivityType.run.kcalPerKgPerKm),
      );
    });

    test('run > hike > walk > cycle (relative metabolic cost)', () {
      // The relative ordering is the load-bearing invariant — even
      // if the absolute values drift in a future calibration pass,
      // running should always burn more per km than walking (faster
      // cadence), hiking sits between walking and running (incline
      // load), and cycling is the cheapest per km (gravity-assist on
      // flats). A regression that swapped run + walk would
      // mis-rank weekly calorie cards.
      expect(
        ActivityType.run.kcalPerKgPerKm,
        greaterThan(ActivityType.hike.kcalPerKgPerKm),
      );
      expect(
        ActivityType.hike.kcalPerKgPerKm,
        greaterThan(ActivityType.walk.kcalPerKgPerKm),
      );
      expect(
        ActivityType.walk.kcalPerKgPerKm,
        greaterThan(ActivityType.cycle.kcalPerKgPerKm),
      );
    });
  });

  group('ActivityType.splitIntervalMetres', () {
    test('cycle splits every 5km, others every 1km', () {
      // A 30 km ride at 1 km splits would fire 30 audio cues — too
      // noisy. The default-vs-cycle branch is one line of switch;
      // pin both sides so a regression that dropped the case (and
      // fell through to 1000 for cycle) would surface as a flood
      // of mid-ride announcements.
      expect(ActivityType.cycle.splitIntervalMetres, 5000);
      expect(ActivityType.run.splitIntervalMetres, 1000);
      expect(ActivityType.walk.splitIntervalMetres, 1000);
      expect(ActivityType.hike.splitIntervalMetres, 1000);
    });
  });

  group('ActivityType.gpsDistanceFilter', () {
    test('cycle filter 5m, others 3m', () {
      // The GPS distance filter is fed to the geolocator config —
      // it's the "min movement before the next fix fires" threshold.
      // Tighter for runs/walks (3 m) where micro-movements matter;
      // looser for cycling (5 m) where the runner moves faster and
      // a 3 m threshold would oversample at urban-speed.
      expect(ActivityType.cycle.gpsDistanceFilter, 5);
      expect(ActivityType.run.gpsDistanceFilter, 3);
      expect(ActivityType.walk.gpsDistanceFilter, 3);
      expect(ActivityType.hike.gpsDistanceFilter, 3);
    });
  });

  group('ActivityType.minMovementMetres', () {
    test('cycle floor 4m, others 2m (GPS-jitter rejection)', () {
      // This is the JITTER floor — samples closer than this are
      // dropped as noise rather than recorded as distance. A
      // regression that loosened it (e.g. to 0.5 m) would inflate
      // distance on stationary GPS drift; tightening it (e.g. to
      // 10 m) would drop legitimate slow-jog samples.
      expect(ActivityType.cycle.minMovementMetres, 4);
      expect(ActivityType.run.minMovementMetres, 2);
      expect(ActivityType.walk.minMovementMetres, 2);
      expect(ActivityType.hike.minMovementMetres, 2);
    });
  });

  group('ActivityType.strideMetres', () {
    test('per-activity stride lengths land at sensible values', () {
      // Treadmill / indoor-recording fallback: when GPS never
      // produces a fix, distance = steps × strideMetres. Wrong
      // values would mis-report indoor runs to the user.
      expect(ActivityType.run.strideMetres, 1.1);
      expect(ActivityType.walk.strideMetres, 0.73);
      expect(ActivityType.hike.strideMetres, 0.85);
    });

    test('cycle stride is 0 (pedometer not meaningful)', () {
      // Cyclists pedal, not step — the pedometer reading is
      // unrelated to distance. The code uses 0 as the explicit
      // "do not use pedometer-derived distance for this activity"
      // signal. A regression to a non-zero value would suddenly
      // start adding spurious distance to indoor cycling
      // recordings.
      expect(ActivityType.cycle.strideMetres, 0.0);
    });

    test('running stride > hiking > walking', () {
      // Stride length tracks cadence + speed: runners stretch out,
      // hikers shorten on uneven ground, walkers shortest of the
      // three. Pin the relative ordering so a calibration drift
      // doesn't silently re-rank the three.
      expect(
        ActivityType.run.strideMetres,
        greaterThan(ActivityType.hike.strideMetres),
      );
      expect(
        ActivityType.hike.strideMetres,
        greaterThan(ActivityType.walk.strideMetres),
      );
    });
  });

  group('ActivityType.maxSpeedMps', () {
    test('caps are above realistic peak speed for each activity', () {
      // The cap is the GPS-corruption rejection threshold —
      // position deltas implying faster than this are discarded as
      // bad fixes. Sanity-check that each cap sits above the
      // fastest-realistic value (so we don't drop legitimate
      // segments).
      // Run: world-record 100m is ~10.4 m/s instantaneous → 10
      // accommodates a fast sprinter on a Strava segment.
      expect(ActivityType.run.maxSpeedMps, greaterThanOrEqualTo(10));
      // Walk: brisk walk ~1.7 m/s → 5 gives 3× headroom.
      expect(ActivityType.walk.maxSpeedMps, greaterThanOrEqualTo(5));
      // Cycle: tour-sprint speeds ~20 m/s → 25 gives headroom.
      expect(ActivityType.cycle.maxSpeedMps, greaterThanOrEqualTo(20));
      // Hike: occasional scrambling-descent jog overlaps with run.
      expect(ActivityType.hike.maxSpeedMps, greaterThanOrEqualTo(5));
    });

    test('cycle cap is highest, walk lowest (per-activity ranking)', () {
      // A regression that swapped run + cycle caps (10 ↔ 25) would
      // silently corrupt rides — sane fixes at 15 m/s would land
      // above the wrong-activity cap and get dropped. Pin the
      // ordering so this can't drift.
      expect(
        ActivityType.cycle.maxSpeedMps,
        greaterThan(ActivityType.run.maxSpeedMps),
      );
      expect(
        ActivityType.run.maxSpeedMps,
        greaterThan(ActivityType.hike.maxSpeedMps),
      );
      expect(
        ActivityType.hike.maxSpeedMps,
        greaterThanOrEqualTo(ActivityType.walk.maxSpeedMps),
      );
    });
  });

  group('ActivityType.fromName', () {
    test('round-trips every enum value through its .name', () {
      // .name is the wire format used in runs.metadata.activity_type
      // (lowercase enum identifier). The pairing must round-trip
      // — a regression that broke either half would surface as
      // "Walk" runs landing in the wrong filter bucket on the
      // runs-list screen.
      for (final t in ActivityType.values) {
        expect(ActivityType.fromName(t.name), t);
      }
    });

    test('unknown name falls back to run (defensive default)', () {
      // Old / malformed metadata on the wire (e.g. legacy
      // "running", or a typo) must not throw. Falling back to run
      // is the documented contract per the orElse clause.
      expect(ActivityType.fromName('running'), ActivityType.run);
      expect(ActivityType.fromName('not-an-activity'), ActivityType.run);
      expect(ActivityType.fromName(''), ActivityType.run);
    });

    test('null name falls back to run', () {
      // Many call-sites read `metadata['activity_type']` which can
      // return null. The parser must accept null without throwing —
      // a NoSuchMethodError on the chip-render path would crash the
      // runs-list build.
      expect(ActivityType.fromName(null), ActivityType.run);
    });
  });

  group('DistanceUnit enum', () {
    test('declares exactly km and mi', () {
      // The unit-preference plumbing reads `prefs.use_miles` (bool)
      // but the enum is the canonical type for the rest of the app.
      // Pin the value set so a future addition (e.g. nautical miles)
      // forces a deliberate review of every formatter.
      expect(DistanceUnit.values.length, 2);
      expect(DistanceUnit.values, containsAll([DistanceUnit.km, DistanceUnit.mi]));
    });
  });

  group('Preferences.bodyWeightKg', () {
    // The calorie estimate on the run-detail page previously hardcoded
    // 70 kg. Wiring `bodyWeightKg` through Preferences lets users with
    // a body_weight_kg setting see a personalised estimate; the 70 kg
    // fallback is documented at the call site.

    test('defaults to null when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.bodyWeightKg, isNull);
    });

    test('reads a persisted positive value', () async {
      SharedPreferences.setMockInitialValues({'body_weight_kg': 75.5});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.bodyWeightKg, 75.5);
    });

    test('treats persisted zero / negative as unset (defensive)', () async {
      // Should never happen via the setter (it filters), but a manual
      // SharedPreferences edit or a corrupted value must not propagate
      // a zero weight into the calorie math — kcal = 0 × ... = 0
      // would render as "0 kcal" on every run, more misleading than
      // the 70 kg fallback.
      SharedPreferences.setMockInitialValues({'body_weight_kg': 0.0});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.bodyWeightKg, isNull);
    });

    test('setter persists positive values + notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      var notifyCount = 0;
      prefs.addListener(() => notifyCount++);

      await prefs.setBodyWeightKg(80.0);
      expect(prefs.bodyWeightKg, 80.0);
      expect(notifyCount, 1);

      // Idempotent — same value again does NOT notify.
      await prefs.setBodyWeightKg(80.0);
      expect(notifyCount, 1);
    });

    test('setter clears on null / non-positive + removes the prefs key', () async {
      SharedPreferences.setMockInitialValues({'body_weight_kg': 80.0});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.bodyWeightKg, 80.0);

      await prefs.setBodyWeightKg(null);
      expect(prefs.bodyWeightKg, isNull);

      // Persisted absence: a fresh Preferences instance also reads null.
      final prefs2 = Preferences();
      await prefs2.init();
      expect(prefs2.bodyWeightKg, isNull);
    });

    test('setter rejects non-positive values', () async {
      SharedPreferences.setMockInitialValues({'body_weight_kg': 80.0});
      final prefs = Preferences();
      await prefs.init();

      await prefs.setBodyWeightKg(0.0);
      expect(prefs.bodyWeightKg, isNull);

      await prefs.setBodyWeightKg(-10.0);
      expect(prefs.bodyWeightKg, isNull);
    });
  });

  group('Preferences.privacyDefault + newRunsArePublic', () {
    // privacy_default drives the initial is_public flag at run-save
    // time. The setting was previously stranded — set in the UI but
    // never read at save time. Pinning the contract here keeps the
    // setter conservative (corrupt values fall back to private so
    // a bad bag can't accidentally publish every new run).

    test('defaults to "private" when no value persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.privacyDefault, 'private');
      expect(prefs.newRunsArePublic, isFalse);
    });

    test('reads a persisted "public" value + flips newRunsArePublic', () async {
      SharedPreferences.setMockInitialValues({'privacy_default': 'public'});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.privacyDefault, 'public');
      expect(prefs.newRunsArePublic, isTrue);
    });

    test('"followers" is treated as private (no DB shape today)',
        () async {
      // No followers-only column on `runs` — `is_public` is a bool.
      // The setter accepts 'followers' as a valid value (mirrors the
      // web settings UI) but `newRunsArePublic` returns false so the
      // run lands private. When the schema gains a third visibility
      // state, this is the test that flips.
      SharedPreferences.setMockInitialValues({'privacy_default': 'followers'});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.privacyDefault, 'followers');
      expect(prefs.newRunsArePublic, isFalse);
    });

    test('setter accepts public / followers / private + persists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      for (final value in ['public', 'followers', 'private']) {
        await prefs.setPrivacyDefault(value);
        expect(prefs.privacyDefault, value);

        // Persistence: a fresh Preferences also reads the value.
        final p2 = Preferences();
        await p2.init();
        expect(p2.privacyDefault, value);
      }
    });

    test('setter rejects unknown strings → falls back to private',
        () async {
      // Defensive: a corrupt bag write (e.g. an old web build that
      // emitted "everyone" or "world") must not promote runs to
      // public. Conservative default — fall back to private.
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await prefs.setPrivacyDefault('public');
      expect(prefs.privacyDefault, 'public');

      await prefs.setPrivacyDefault('everyone');
      expect(prefs.privacyDefault, 'private');
      expect(prefs.newRunsArePublic, isFalse);
    });

    test('setter is idempotent — same value does NOT notify', () async {
      SharedPreferences.setMockInitialValues({'privacy_default': 'public'});
      final prefs = Preferences();
      await prefs.init();
      var notifyCount = 0;
      prefs.addListener(() => notifyCount++);

      await prefs.setPrivacyDefault('public');
      expect(notifyCount, 0);

      await prefs.setPrivacyDefault('private');
      expect(notifyCount, 1);
    });
  });

  group('formatDistanceForPref + activeDistanceUnit (global accessor)', () {
    // Several read-only surfaces (feed cards, profile notification
    // verbs, live spectator stats, club-detail route subtitles, the
    // home-screen recovered-run banner) used to hardcode
    // `'${(metres / 1000).toStringAsFixed(2)} km'` because they
    // didn't take a Preferences constructor dep. `formatDistanceForPref`
    // is the drop-in replacement that reads the active unit from the
    // top-level `_activePreferences` registered by main.dart. These
    // tests pin the accessor's contract; the screen-level widget
    // tests pin that the right surfaces use it.
    tearDown(resetActivePreferencesForTest);

    test('defaults to km when no Preferences has been registered', () {
      // Host-test runner / very-early-cold-start path. Without this
      // default, the helper would throw on a null deref and crash a
      // screen build before main.dart's register call completes.
      resetActivePreferencesForTest();
      expect(activeDistanceUnit, DistanceUnit.km);
      expect(formatDistanceForPref(5000), '5.00 km');
    });

    test('formats in mi when registered Preferences is mi-mode', () async {
      // The headline regression net: a user with mi-mode pref must
      // see "3.11 mi" not "5.00 km" on every surface routed through
      // this helper. The bug shape is "screen hardcoded km even
      // though Preferences was loaded in mi-mode".
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      expect(activeDistanceUnit, DistanceUnit.mi);
      expect(formatDistanceForPref(5000), '3.11 mi');
    });

    test('formats in km when registered Preferences is km-mode', () async {
      SharedPreferences.setMockInitialValues({'use_miles': false});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      expect(activeDistanceUnit, DistanceUnit.km);
      expect(formatDistanceForPref(5000), '5.00 km');
    });

    test('re-registering with a new Preferences flips the active unit', () async {
      // Test isolation contract: a test that registers one Preferences
      // instance must not bleed into the next. `resetActivePreferencesForTest`
      // is the documented way to clear; pin that re-registering also
      // works (so a screen-level test can flip the unit mid-test).
      SharedPreferences.setMockInitialValues({'use_miles': false});
      final kmPrefs = Preferences();
      await kmPrefs.init();
      registerActivePreferences(kmPrefs);
      expect(formatDistanceForPref(5000), '5.00 km');

      SharedPreferences.setMockInitialValues({'use_miles': true});
      final miPrefs = Preferences();
      await miPrefs.init();
      registerActivePreferences(miPrefs);
      expect(formatDistanceForPref(5000), '3.11 mi');
    });

    test('resetActivePreferencesForTest clears the registered instance', () async {
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      expect(activeDistanceUnit, DistanceUnit.mi);

      resetActivePreferencesForTest();
      expect(activeDistanceUnit, DistanceUnit.km); // back to default
    });

    test('round-trips through UnitFormat.distance contract', () async {
      // formatDistanceForPref is documented as a drop-in for
      // `UnitFormat.distance(metres, activeUnit)`. Pin that the
      // results match byte-for-byte across both unit modes — a
      // regression that diverged the two would break the screens
      // that mix calling styles (e.g. a screen that uses
      // UnitFormat.distance for one row and formatDistanceForPref
      // for another).
      for (final useMiles in [false, true]) {
        SharedPreferences.setMockInitialValues({'use_miles': useMiles});
        final prefs = Preferences();
        await prefs.init();
        registerActivePreferences(prefs);
        for (final m in [0.0, 50.0, 500.0, 1500.0, 5000.0, 42_195.0]) {
          expect(
            formatDistanceForPref(m),
            UnitFormat.distance(m, activeDistanceUnit),
            reason: 'metres=$m useMiles=$useMiles drift',
          );
        }
      }
    });
  });
}
