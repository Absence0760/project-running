import 'package:flutter_test/flutter_test.dart';
import '../lib/preferences.dart';

void main() {
  group('UnitFormat.distance', () {
    test('km branch divides metres by 1000 with two decimals', () {
      expect(UnitFormat.distance(5000, DistanceUnit.km), '5.00 km');
      expect(UnitFormat.distance(5234, DistanceUnit.km), '5.23 km');
    });

    test('mi branch uses 1609.344 m per mile', () {
      expect(UnitFormat.distance(1609.344, DistanceUnit.mi), '1.00 mi');
      expect(UnitFormat.distance(5000, DistanceUnit.mi), '3.11 mi');
    });

    test('zero metres formats as 0.00', () {
      expect(UnitFormat.distance(0, DistanceUnit.km), '0.00 km');
      expect(UnitFormat.distance(0, DistanceUnit.mi), '0.00 mi');
    });
  });

  group('UnitFormat.distanceValue', () {
    test('returns the same value as distance() without the unit suffix', () {
      expect(UnitFormat.distanceValue(5234, DistanceUnit.km), '5.23');
      expect(UnitFormat.distanceValue(5000, DistanceUnit.mi), '3.11');
    });
  });

  group('UnitFormat.distanceLabel', () {
    test('returns "km" or "mi"', () {
      expect(UnitFormat.distanceLabel(DistanceUnit.km), 'km');
      expect(UnitFormat.distanceLabel(DistanceUnit.mi), 'mi');
    });
  });

  group('UnitFormat.pace', () {
    test('formats minutes:seconds zero-padded to two digits', () {
      expect(UnitFormat.pace(330, DistanceUnit.km), '5:30');
      expect(UnitFormat.pace(305, DistanceUnit.km), '5:05');
    });

    test('returns the em-dash sentinel when pace is null or non-positive', () {
      expect(UnitFormat.pace(null, DistanceUnit.km), '--:--');
      expect(UnitFormat.pace(0, DistanceUnit.km), '--:--');
      expect(UnitFormat.pace(-1, DistanceUnit.km), '--:--');
    });

    test('mi branch scales seconds-per-km by 1609.344/1000 to get sec/mile', () {
      // 6:00 /km → 6 * 1.609344 = ~9:39 /mi
      expect(UnitFormat.pace(360, DistanceUnit.mi), '9:39');
    });
  });

  group('UnitFormat.paceLabel', () {
    test('returns "/km" or "/mi"', () {
      expect(UnitFormat.paceLabel(DistanceUnit.km), '/km');
      expect(UnitFormat.paceLabel(DistanceUnit.mi), '/mi');
    });
  });

  group('UnitFormat.distanceTicks', () {
    test('km counts each completed kilometre', () {
      expect(UnitFormat.distanceTicks(0, DistanceUnit.km), 0);
      expect(UnitFormat.distanceTicks(999, DistanceUnit.km), 0);
      expect(UnitFormat.distanceTicks(1000, DistanceUnit.km), 1);
      expect(UnitFormat.distanceTicks(1999, DistanceUnit.km), 1);
      expect(UnitFormat.distanceTicks(7100, DistanceUnit.km), 7);
    });

    test('mi counts each completed mile (1609.344 m)', () {
      expect(UnitFormat.distanceTicks(1609, DistanceUnit.mi), 0);
      expect(UnitFormat.distanceTicks(1610, DistanceUnit.mi), 1);
      expect(UnitFormat.distanceTicks(5000, DistanceUnit.mi), 3);
    });
  });

  group('UnitFormat.activityTicks', () {
    test('floors the metres / interval ratio', () {
      expect(UnitFormat.activityTicks(0, 5000), 0);
      expect(UnitFormat.activityTicks(4999, 5000), 0);
      expect(UnitFormat.activityTicks(5000, 5000), 1);
      expect(UnitFormat.activityTicks(15000.5, 5000), 3);
    });
  });

  group('UnitFormat.speed', () {
    test('km branch divides 3600 by seconds-per-km', () {
      // 6:00 /km → 10.0 km/h
      expect(UnitFormat.speed(360, DistanceUnit.km), '10.0');
      // 5:00 /km → 12.0 km/h
      expect(UnitFormat.speed(300, DistanceUnit.km), '12.0');
    });

    test('mi branch divides km/h by 1.609344', () {
      // 10 km/h → ~6.2 mph
      expect(UnitFormat.speed(360, DistanceUnit.mi), '6.2');
    });

    test('returns "--" sentinel for null or non-positive pace', () {
      expect(UnitFormat.speed(null, DistanceUnit.km), '--');
      expect(UnitFormat.speed(0, DistanceUnit.km), '--');
      expect(UnitFormat.speed(-1, DistanceUnit.mi), '--');
    });
  });

  group('UnitFormat.speedLabel', () {
    test('returns "km/h" or "mph"', () {
      expect(UnitFormat.speedLabel(DistanceUnit.km), 'km/h');
      expect(UnitFormat.speedLabel(DistanceUnit.mi), 'mph');
    });
  });

  group('ActivityType', () {
    test('label maps each enum value to its display string', () {
      expect(ActivityType.run.label, 'Run');
      expect(ActivityType.walk.label, 'Walk');
      expect(ActivityType.cycle.label, 'Cycle');
      // Surfaced as "Trail run" on the picker so runners pick a
      // more natural label for off-road runs. Internal enum name
      // stays `hike` for back-compat with the runs.metadata
      // CHECK constraint + Strava / Health Connect importers.
      expect(ActivityType.hike.label, 'Trail run');
    });

    test('usesSpeed is true only for cycle', () {
      expect(ActivityType.run.usesSpeed, isFalse);
      expect(ActivityType.walk.usesSpeed, isFalse);
      expect(ActivityType.hike.usesSpeed, isFalse);
      expect(ActivityType.cycle.usesSpeed, isTrue);
    });

    test('kcalPerKgPerKm orders run > hike > walk > cycle', () {
      expect(ActivityType.run.kcalPerKgPerKm, 1.0);
      expect(ActivityType.hike.kcalPerKgPerKm, 0.7);
      expect(ActivityType.walk.kcalPerKgPerKm, 0.5);
      expect(ActivityType.cycle.kcalPerKgPerKm, 0.4);
    });

    test('splitIntervalMetres is 5km for cycle, 1km otherwise', () {
      expect(ActivityType.cycle.splitIntervalMetres, 5000);
      expect(ActivityType.run.splitIntervalMetres, 1000);
      expect(ActivityType.walk.splitIntervalMetres, 1000);
      expect(ActivityType.hike.splitIntervalMetres, 1000);
    });

    test('gpsDistanceFilter is 5 m for cycle, 3 m otherwise', () {
      expect(ActivityType.cycle.gpsDistanceFilter, 5);
      expect(ActivityType.run.gpsDistanceFilter, 3);
      expect(ActivityType.walk.gpsDistanceFilter, 3);
      expect(ActivityType.hike.gpsDistanceFilter, 3);
    });
  });
}
