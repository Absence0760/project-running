import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:uuid/uuid.dart';

/// Pulls workouts from Android Health Connect (Google Fit, Samsung Health,
/// Garmin Connect, Fitbit, etc. all sync into Health Connect on Android 14+).
///
/// Health Connect doesn't expose GPS routes for workouts written by other
/// apps — those stay in the originating app's database. We can read the
/// workout summary (start, duration, distance, type) and use that to create
/// runs without GPS tracks. The user can still see them in Runs; the
/// detail screen just shows stats and no map.
class HealthConnectImporter {
  static const _uuid = Uuid();
  static final _health = Health();

  /// Request permission to read workouts from Health Connect.
  /// Returns true if permission was granted.
  static Future<bool> requestPermission() async {
    await _health.configure();

    final types = [
      HealthDataType.WORKOUT,
      HealthDataType.DISTANCE_DELTA,
    ];

    final granted = await _health.requestAuthorization(
      types,
      permissions: types.map((_) => HealthDataAccess.READ).toList(),
    );
    return granted;
  }

  /// Pull workouts from Health Connect within the given date range
  /// (defaults to last 365 days). Returns runs converted from each workout
  /// summary. Activities without GPS data still count — they're recorded
  /// with an empty track.
  static Future<List<Run>> fetchWorkouts({
    DateTime? from,
    DateTime? to,
  }) async {
    final start = from ?? DateTime.now().subtract(const Duration(days: 365));
    final end = to ?? DateTime.now();

    final data = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.WORKOUT],
      startTime: start,
      endTime: end,
    );

    final runs = <Run>[];
    for (final point in data) {
      try {
        final value = point.value;
        if (value is! WorkoutHealthValue) continue;

        final activityType = _mapWorkoutType(value.workoutActivityType);
        if (activityType == null) continue; // not a movement workout we care about

        final distance = (value.totalDistance ?? 0).toDouble();
        if (distance < 100) continue; // skip workouts shorter than 100m

        runs.add(Run(
          id: _uuid.v4(),
          startedAt: point.dateFrom,
          duration: point.dateTo.difference(point.dateFrom),
          distanceMetres: distance,
          track: const [], // Health Connect doesn't expose route geometry
          source: RunSource.healthconnect,
          externalId: point.uuid,
          metadata: {
            'imported_from': 'health_connect',
            'imported_at': DateTime.now().toIso8601String(),
            'health_connect_type': value.workoutActivityType.name,
            'activity_type': activityType,
          },
        ));
      } catch (e) {
        debugPrint('Failed to map Health Connect workout: $e');
      }
    }
    return runs;
  }

  /// Map Health Connect workout types to our activity_type strings.
  /// Returns null for workout types we don't display (e.g. weights, yoga).
  static String? _mapWorkoutType(HealthWorkoutActivityType type) {
    switch (type) {
      case HealthWorkoutActivityType.RUNNING:
      case HealthWorkoutActivityType.RUNNING_TREADMILL:
        return 'run';
      case HealthWorkoutActivityType.WALKING:
        return 'walk';
      case HealthWorkoutActivityType.BIKING:
        return 'cycle';
      case HealthWorkoutActivityType.HIKING:
        return 'hike';
      default:
        return null;
    }
  }
}
