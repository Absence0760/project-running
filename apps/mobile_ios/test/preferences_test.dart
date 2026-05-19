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
      expect(ActivityType.hike.label, 'Hike');
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
      // 0.4–1.0 kcal/kg/km covers walking through running per the
      // approximate METs translation. A regression introducing e.g.
      // 10.0 (10× too big) would inflate the dashboard's
      // calories-burned number by an order of magnitude.
      for (final t in ActivityType.values) {
        expect(t.kcalPerKgPerKm, greaterThanOrEqualTo(0.4));
        expect(t.kcalPerKgPerKm, lessThanOrEqualTo(1.0));
      }
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
}
