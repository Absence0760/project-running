import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Writes completed runs back to Android Health Connect so they flow on
/// to Google Fit / Samsung Health / Fitbit / Garmin Connect (everything
/// that reads Health Connect). The inverse of [HealthConnectImporter].
/// Persona-hunt android #36.
///
/// Health Connect is Android-only; callers gate this behind
/// `Platform.isAndroid` AND the per-device "write to Health Connect"
/// preference (off by default — writing user data to a third-party store
/// is opt-in). On iOS the `health` package targets HealthKit, which
/// needs separate entitlements we don't ship, so the write path is not
/// invoked there.
class HealthConnectExporter {
  static final _health = Health();

  /// Request WRITE access for the workout session + its distance record.
  /// `writeWorkoutData` inserts an `ExerciseSessionRecord` plus a
  /// `DistanceRecord` (when a distance is supplied), so both write
  /// permissions are needed. Returns true when granted.
  static Future<bool> requestWritePermission() async {
    await _health.configure();
    const types = [HealthDataType.WORKOUT, HealthDataType.DISTANCE_DELTA];
    return _health.requestAuthorization(
      types,
      permissions: types.map((_) => HealthDataAccess.WRITE).toList(),
    );
  }

  /// Best-effort: write [run] to Health Connect as a workout. Returns
  /// true on success. Swallows + logs any failure (missing permission,
  /// HC unavailable, unsupported type) so a write-back can never break
  /// the run-save flow — same L4 contract as the rest of the recording
  /// stack.
  static Future<bool> writeRun(Run run) async {
    final type = healthWorkoutTypeForActivity(
      run.metadata?['activity_type'] as String?,
    );
    if (type == null) return false;
    try {
      await _health.configure();
      final start = run.startedAt;
      final end = run.startedAt.add(run.duration);
      final distance = run.distanceMetres.round();
      return await _health.writeWorkoutData(
        activityType: type,
        start: start,
        end: end,
        totalDistance: distance > 0 ? distance : null,
        totalDistanceUnit: HealthDataUnit.METER,
        title: run.metadata?['title'] as String?,
        recordingMethod: RecordingMethod.automatic,
      );
    } catch (e) {
      debugPrint('Health Connect write failed for run ${run.id}: $e');
      return false;
    }
  }
}

/// Map an `activity_type` string to a Health Connect workout type.
/// Inverse of `HealthConnectImporter._mapWorkoutType`. A null / unknown
/// type defaults to RUNNING (this is a running app and the recorder
/// always stamps a type, so an absent one is almost certainly a run).
/// Stroller runs (persona #51) map to RUNNING — Health Connect has no
/// stroller type and the effort profile is run-like. Pure + top-level so
/// it's unit-testable without the platform channel.
HealthWorkoutActivityType? healthWorkoutTypeForActivity(String? activityType) {
  switch (activityType) {
    case 'walk':
      return HealthWorkoutActivityType.WALKING;
    case 'cycle':
      return HealthWorkoutActivityType.BIKING;
    case 'hike':
      return HealthWorkoutActivityType.HIKING;
    case 'run':
    case 'stroller':
    case null:
      return HealthWorkoutActivityType.RUNNING;
    default:
      return HealthWorkoutActivityType.RUNNING;
  }
}
