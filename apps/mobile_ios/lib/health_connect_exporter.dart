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

  /// Request WRITE access for the workout session, its distance record, and
  /// heart rate. `writeWorkoutData` inserts an `ExerciseSessionRecord` plus a
  /// `DistanceRecord`; the per-point chest-strap HR is written as separate
  /// `HeartRateRecord` samples, so all three write permissions are needed.
  /// Returns true when granted.
  static Future<bool> requestWritePermission() async {
    await _health.configure();
    const types = [
      HealthDataType.WORKOUT,
      HealthDataType.DISTANCE_DELTA,
      HealthDataType.HEART_RATE,
    ];
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
      final ok = await _health.writeWorkoutData(
        activityType: type,
        start: start,
        end: end,
        totalDistance: distance > 0 ? distance : null,
        totalDistanceUnit: HealthDataUnit.METER,
        title: run.metadata?['title'] as String?,
        recordingMethod: RecordingMethod.automatic,
      );
      // Best-effort HR write-back: chest-strap BPM captured during the run
      // (per-point on the track, or a single avg_bpm) flows back so Health
      // Connect readers see the heart-rate trace, not just the session +
      // distance. Wrapped separately so a missing WRITE_HEART_RATE grant or
      // an unsupported sample can't roll back the workout write above.
      try {
        await _writeHeartRate(run, start);
      } catch (e) {
        debugPrint('Health Connect HR write failed for run ${run.id}: $e');
      }
      return ok;
    } catch (e) {
      debugPrint('Health Connect write failed for run ${run.id}: $e');
      return false;
    }
  }

  /// Write the run's heart-rate samples. Sample selection is the pure
  /// [heartRateSamplesForRun]; this method just fans each one onto the
  /// platform channel.
  static Future<void> _writeHeartRate(Run run, DateTime start) async {
    for (final s in heartRateSamplesForRun(run, start)) {
      await _health.writeHealthData(
        value: s.bpm.toDouble(),
        type: HealthDataType.HEART_RATE,
        startTime: s.time,
        endTime: s.time,
        recordingMethod: RecordingMethod.automatic,
      );
    }
  }
}

/// One heart-rate sample destined for Health Connect.
class HeartRateSample {
  final DateTime time;
  final int bpm;
  const HeartRateSample(this.time, this.bpm);
}

/// Pick the heart-rate samples to write back for [run]. Prefers per-point
/// BPM stamped on the track (each waypoint with a timestamp + a positive bpm
/// becomes one sample); falls back to a single average sample at [start] when
/// only `metadata.avg_bpm` is present. Empty when the run carries no usable
/// HR. Pure + top-level so the per-point-vs-average decision is unit-testable
/// without the platform channel.
List<HeartRateSample> heartRateSamplesForRun(Run run, DateTime start) {
  final perPoint = <HeartRateSample>[];
  for (final w in run.track) {
    final bpm = w.bpm;
    final ts = w.timestamp;
    if (bpm == null || bpm <= 0 || ts == null) continue;
    perPoint.add(HeartRateSample(ts, bpm));
  }
  if (perPoint.isNotEmpty) return perPoint;

  final avg = run.metadata?['avg_bpm'];
  final avgBpm = avg is num ? avg.round() : null;
  if (avgBpm == null || avgBpm <= 0) return const [];
  return [HeartRateSample(start, avgBpm)];
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
