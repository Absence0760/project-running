import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import '../lib/health_connect_exporter.dart';

/// Pure-mapping coverage for the Health Connect write-back (persona #36).
/// The `writeRun` / permission paths need the platform channel, so only
/// the activity-type mapping is unit-tested here.
void main() {
  group('healthWorkoutTypeForActivity', () {
    test('maps the four core activity types', () {
      expect(healthWorkoutTypeForActivity('run'),
          HealthWorkoutActivityType.RUNNING);
      expect(healthWorkoutTypeForActivity('walk'),
          HealthWorkoutActivityType.WALKING);
      expect(healthWorkoutTypeForActivity('cycle'),
          HealthWorkoutActivityType.BIKING);
      expect(healthWorkoutTypeForActivity('hike'),
          HealthWorkoutActivityType.HIKING);
    });

    test('stroller maps to running (no HC stroller type; run-like effort)', () {
      expect(healthWorkoutTypeForActivity('stroller'),
          HealthWorkoutActivityType.RUNNING);
    });

    test('null / unknown default to running (running app)', () {
      expect(healthWorkoutTypeForActivity(null),
          HealthWorkoutActivityType.RUNNING);
      expect(healthWorkoutTypeForActivity('kayak'),
          HealthWorkoutActivityType.RUNNING);
    });

    test('round-trips with the importer mapping for the shared four', () {
      // Importer maps RUNNING→run, WALKING→walk, BIKING→cycle, HIKING→hike;
      // the exporter is its inverse for those four.
      const pairs = {
        'run': HealthWorkoutActivityType.RUNNING,
        'walk': HealthWorkoutActivityType.WALKING,
        'cycle': HealthWorkoutActivityType.BIKING,
        'hike': HealthWorkoutActivityType.HIKING,
      };
      pairs.forEach((activity, hcType) {
        expect(healthWorkoutTypeForActivity(activity), hcType);
      });
    });
  });
}
