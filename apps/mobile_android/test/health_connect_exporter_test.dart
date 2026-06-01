import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import '../lib/health_connect_exporter.dart';

/// Pure-mapping coverage for the Health Connect write-back (persona #36).
/// The `writeRun` / permission paths need the platform channel, so only
/// the activity-type mapping + HR-sample selection are unit-tested here.
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

  group('heartRateSamplesForRun (persona round-5 HR write-back)', () {
    final start = DateTime(2026, 5, 31, 8);

    Run runWith({List<Waypoint> track = const [], num? avgBpm}) => Run(
          id: 'r1',
          startedAt: start,
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          track: track,
          source: RunSource.app,
          metadata: avgBpm == null ? null : {'avg_bpm': avgBpm},
        );

    test('prefers per-point BPM from the track', () {
      final t0 = start.add(const Duration(seconds: 1));
      final t1 = start.add(const Duration(seconds: 2));
      final samples = heartRateSamplesForRun(
        runWith(track: [
          Waypoint(lat: 0, lng: 0, timestamp: t0, bpm: 140),
          Waypoint(lat: 0, lng: 0, timestamp: t1, bpm: 145),
        ], avgBpm: 99),
        start,
      );
      expect(samples.map((s) => s.bpm), [140, 145]);
      expect(samples.map((s) => s.time), [t0, t1]);
    });

    test('skips waypoints with null / non-positive bpm or null timestamp', () {
      final t1 = start.add(const Duration(seconds: 2));
      final samples = heartRateSamplesForRun(
        runWith(track: [
          Waypoint(lat: 0, lng: 0, timestamp: start, bpm: null),
          Waypoint(lat: 0, lng: 0, timestamp: null, bpm: 150),
          Waypoint(lat: 0, lng: 0, timestamp: start, bpm: 0),
          Waypoint(lat: 0, lng: 0, timestamp: t1, bpm: 138),
        ]),
        start,
      );
      expect(samples.length, 1);
      expect(samples.single.bpm, 138);
      expect(samples.single.time, t1);
    });

    test('falls back to a single avg_bpm sample at start when no per-point HR',
        () {
      final samples = heartRateSamplesForRun(runWith(avgBpm: 152), start);
      expect(samples.length, 1);
      expect(samples.single.bpm, 152);
      expect(samples.single.time, start);
    });

    test('rounds a fractional avg_bpm', () {
      final samples = heartRateSamplesForRun(runWith(avgBpm: 151.6), start);
      expect(samples.single.bpm, 152);
    });

    test('empty when the run carries no usable HR', () {
      expect(heartRateSamplesForRun(runWith(), start), isEmpty);
      expect(heartRateSamplesForRun(runWith(avgBpm: 0), start), isEmpty);
    });
  });
}
