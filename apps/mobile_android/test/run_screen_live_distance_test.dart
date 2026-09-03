import 'package:core_models/core_models.dart' show ActivityType;
import 'package:flutter_test/flutter_test.dart';

import '../lib/preferences.dart';
import '../lib/race_phases.dart';
import '../lib/run_stats.dart';

/// Pins the distance source every distance-DERIVED behaviour on the run screen
/// has to resolve through. An indoor / treadmill session never gets a GPS fix,
/// so the recorder's own distance stays 0 for the whole run while the pedometer
/// estimate climbs — reading the raw figure silently disables split cues and
/// race-phase transitions for the entire session.
void main() {
  group('liveDistanceMetres', () {
    test('a GPS-backed run reports the recorder distance untouched', () {
      expect(
        liveDistanceMetres(
          everHadGpsFix: true,
          gpsDistanceMetres: 5432.1,
          steps: 9000,
          strideMetres: 1.1,
        ),
        5432.1,
      );
    });

    test('a fix that has arrived pins the source even at zero distance', () {
      // Standing on the start line with a fix: the pedometer must not
      // manufacture distance the GPS says the runner has not covered.
      expect(
        liveDistanceMetres(
          everHadGpsFix: true,
          gpsDistanceMetres: 0,
          steps: 400,
          strideMetres: 1.1,
        ),
        0,
      );
    });

    test('an indoor run with no fix falls back to steps x stride', () {
      expect(
        liveDistanceMetres(
          everHadGpsFix: false,
          gpsDistanceMetres: 0,
          steps: 10000,
          strideMetres: 1.1,
        ),
        11000,
      );
    });

    test('a treadmill belt feeding distance without a fix wins over steps', () {
      expect(
        liveDistanceMetres(
          everHadGpsFix: false,
          gpsDistanceMetres: 3000,
          steps: 10000,
          strideMetres: 1.1,
        ),
        3000,
      );
    });

    test('cycling has no pedometer, so the estimate is zero not a guess', () {
      expect(
        liveDistanceMetres(
          everHadGpsFix: false,
          gpsDistanceMetres: 0,
          steps: 10000,
          strideMetres: ActivityType.cycle.strideMetres,
        ),
        0,
      );
    });
  });

  group('indoor run behaviours read the resolved distance', () {
    // 9273 steps x 1.1 m = 10200.3 m — the ~10.2 km the screen displays.
    const steps = 9273;
    double indoorDistance() => liveDistanceMetres(
          everHadGpsFix: false,
          gpsDistanceMetres: 0,
          steps: steps,
          strideMetres: ActivityType.run.strideMetres,
        );

    test('split ticks fire on the pedometer estimate, not the raw zero', () {
      final interval = ActivityType.run.splitIntervalMetresFor(DistanceUnit.km);
      expect(UnitFormat.activityTicks(0, interval), 0);
      expect(UnitFormat.activityTicks(indoorDistance(), interval), 10);
    });

    test('the split average pace is a real number, not null', () {
      expect(averagePaceSecPerKm(0, 3600), isNull);
      expect(
        averagePaceSecPerKm(indoorDistance(), 3600),
        closeTo(352.9, 0.1),
      );
    });

    test('race phases advance instead of latching on phase 1', () {
      final plan = buildPhasePlan(21097.5, RacePhasePreset.tenTenTen);
      expect(plan, isNotEmpty);
      expect(phaseAt(plan, 0), 0);
      expect(phaseAt(plan, indoorDistance()), greaterThan(0));
    });

    test('the 50 m gate that defers the first phase cue is clearable', () {
      // The phase block waits for 50 m of movement so the first announcement
      // does not cut off the start cue. On the raw field that gate is never
      // passed on an indoor run.
      expect(indoorDistance(), greaterThan(50));
    });
  });
}
