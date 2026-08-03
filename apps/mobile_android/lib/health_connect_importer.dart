import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'embedded_bests.dart';
import 'imported_run_id.dart';

/// One `ExerciseRoute` location, flattened off the plugin's
/// `WorkoutRouteLocation` so the shaping below stays testable without a
/// platform channel.
typedef HcRoutePoint = ({
  double lat,
  double lng,
  DateTime at,
  double? altitudeMetres,
});

/// Pulls workouts from Android Health Connect (Google Fit, Samsung Health,
/// Garmin Connect, Fitbit, etc. all sync into Health Connect on Android 14+).
///
/// A workout summary (start, duration, distance, type) always imports. The
/// GPS route is separate and conditional: an `ExerciseSessionRecord` may
/// carry an `ExerciseRoute`, but reading one written by another app needs
/// `READ_EXERCISE_ROUTES` on top of the session read, and Health Connect
/// withholds it from a background read even when that is granted. So a route
/// is treated as a bonus — when it arrives the run gets a real track, and
/// when it doesn't the run imports exactly as it did before, with an empty
/// track and nothing claiming otherwise.
class HealthConnectImporter {
  static final _health = Health();

  /// Request permission to read workouts from Health Connect.
  /// Returns true if permission was granted.
  static Future<bool> requestPermission() async {
    await _health.configure();

    final types = [
      HealthDataType.WORKOUT,
      // Android-only. On HealthKit the same type maps to
      // HKSeriesType.workoutRoute(), so asking for it here would widen what
      // the iOS build collects — and what its usage string and App Store
      // privacy labels have to declare. That is a decision of its own, not
      // a side effect of fixing the Health Connect import.
      if (Platform.isAndroid) HealthDataType.WORKOUT_ROUTE,
      HealthDataType.DISTANCE_DELTA,
      HealthDataType.HEART_RATE,
      // Read body weight so the import can seed the user's body_weight_kg
      // (used by the calorie estimate) when they haven't set one — a
      // Samsung-watch user keeps their weight in Samsung Health, which
      // syncs into Health Connect (persona round-5 samsung-watch).
      HealthDataType.WEIGHT,
    ];

    final granted = await _health.requestAuthorization(
      types,
      permissions: types.map((_) => HealthDataAccess.READ).toList(),
    );
    return granted;
  }

  /// Pull workouts from Health Connect within the given date range
  /// (defaults to last 365 days). Returns runs converted from each workout
  /// summary, each carrying its GPS route when Health Connect released one.
  /// Activities without GPS data still count — they're recorded with an
  /// empty track.
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

    final routeTracks = await _fetchRouteTracks(start, end);

    final runs = <Run>[];
    for (final point in data) {
      try {
        final value = point.value;
        if (value is! WorkoutHealthValue) continue;

        final activityType = _mapWorkoutType(value.workoutActivityType);
        if (activityType == null) continue; // not a movement workout we care about

        final distance = (value.totalDistance ?? 0).toDouble();
        if (distance < 100) continue; // skip workouts shorter than 100m

        // Average heart rate across the workout window. Null when the
        // source app didn't write HR samples — common for walking
        // sessions and third-party trackers that only report a summary.
        final avgBpm = await _averageHrInWindow(point.dateFrom, point.dateTo);

        final metadata = <String, dynamic>{
          MetadataKeys.importedFrom: 'health_connect',
          MetadataKeys.importedAt: DateTime.now().toIso8601String(),
          MetadataKeys.healthConnectType: value.workoutActivityType.name,
          MetadataKeys.activityType: activityType,
        };
        if (avgBpm != null) metadata[MetadataKeys.avgBpm] = avgBpm;

        // Both the workout point and its route point carry the same
        // ExerciseSessionRecord id, so that is the join key.
        final track = routeTracks[point.uuid] ?? const <Waypoint>[];

        final externalId = 'healthconnect:${point.uuid}';
        runs.add(Run(
          // Stable id derived from external_id so a re-import maps to the same
          // local run (no duplicate) and the server upsert never rewrites the
          // primary key — see imported_run_id.dart (#361).
          id: stableRunIdFromExternalId(externalId),
          startedAt: point.dateFrom,
          duration: point.dateTo.difference(point.dateFrom),
          distanceMetres: distance,
          track: track,
          source: RunSource.healthconnect,
          externalId: externalId,
          // A fast 5k inside an imported long run only reaches
          // personal_records through these, and they can only be computed
          // once there is a timestamped track. Returns metadata untouched
          // when there isn't one, so a trackless import writes no fake bests.
          metadata: enrichMetadataWithEmbeddedBests(
            track: track,
            metadata: metadata,
          ),
        ));
      } catch (e) {
        debugPrint('Failed to map Health Connect workout: $e');
      }
    }
    return runs;
  }

  /// Per-workout GPS tracks Health Connect will release for the window,
  /// keyed by `ExerciseSessionRecord` id.
  ///
  /// Wrapped whole: a route read that throws (permission revoked mid-import,
  /// Health Connect updating underneath us) degrades every workout in the
  /// batch to a summary-only import rather than failing the import outright.
  static Future<Map<String, List<Waypoint>>> _fetchRouteTracks(
    DateTime start,
    DateTime end,
  ) async {
    if (!Platform.isAndroid) return const {};
    try {
      final data = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT_ROUTE],
        startTime: start,
        endTime: end,
      );
      final routes = <({String uuid, List<HcRoutePoint> points})>[];
      for (final point in data) {
        final value = point.value;
        if (value is! WorkoutRouteHealthValue) continue;
        routes.add((
          uuid: point.uuid,
          points: [
            for (final l in value.locations)
              (
                lat: l.latitude,
                lng: l.longitude,
                at: l.timestamp,
                altitudeMetres: l.altitude,
              ),
          ],
        ));
      }
      return tracksFromRoutePoints(routes);
    } catch (e) {
      debugPrint('Health Connect route fetch failed: $e');
      return const {};
    }
  }

  /// Shape Health Connect route locations into per-workout tracks. Pure so
  /// the join + ordering + screening is unit-testable without the plugin.
  ///
  /// A session whose route Health Connect withheld arrives with zero
  /// locations (the `ConsentRequired` result — the route permission isn't
  /// granted, or the read ran in the background) and is left out of the map
  /// entirely, so its run imports with no track instead of a track that
  /// claims to be the route and isn't. Points are ordered by time and
  /// screened for finite, in-range coordinates; a session left with fewer
  /// than two is dropped, since one point is a position, not a route.
  @visibleForTesting
  static Map<String, List<Waypoint>> tracksFromRoutePoints(
    List<({String uuid, List<HcRoutePoint> points})> routes,
  ) {
    final out = <String, List<Waypoint>>{};
    for (final route in routes) {
      final valid = route.points.where(_isPlausibleFix).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (valid.length < 2) continue;
      out[route.uuid] = [
        for (final p in valid)
          Waypoint(
            lat: p.lat,
            lng: p.lng,
            elevationMetres: p.altitudeMetres,
            timestamp: p.at,
          ),
      ];
    }
    return out;
  }

  static bool _isPlausibleFix(HcRoutePoint p) =>
      p.lat.isFinite &&
      p.lng.isFinite &&
      p.lat.abs() <= 90 &&
      p.lng.abs() <= 180;

  /// The most-recent body-weight sample (kg) Health Connect holds, or null
  /// when there is none or the read errors. Used to one-time seed the
  /// user's `body_weight_kg` on import. Clamps to a sane 30–300 kg so a
  /// stray sample can't poison the calorie estimate.
  static Future<double?> fetchLatestWeightKg() async {
    try {
      final now = DateTime.now();
      final samples = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WEIGHT],
        startTime: now.subtract(const Duration(days: 3650)),
        endTime: now,
      );
      return selectLatestWeightKg([
        for (final s in samples)
          if (s.value is NumericHealthValue)
            (
              kg: (s.value as NumericHealthValue).numericValue.toDouble(),
              at: s.dateTo,
            ),
      ]);
    } catch (e) {
      debugPrint('Weight fetch failed: $e');
      return null;
    }
  }

  /// Pick the most-recent in-range (30–300 kg) weight from a list of
  /// samples. Pure so the recency + clamp logic is unit-testable without
  /// the Health Connect plugin. Returns null when none qualify.
  @visibleForTesting
  static double? selectLatestWeightKg(List<({double kg, DateTime at})> samples) {
    double? latestKg;
    DateTime? latestAt;
    for (final s in samples) {
      if (s.kg < 30 || s.kg > 300) continue;
      if (latestAt == null || s.at.isAfter(latestAt)) {
        latestAt = s.at;
        latestKg = s.kg;
      }
    }
    return latestKg;
  }

  /// Mean of every HR sample Health Connect has between [start] and [end].
  /// Returns null when no samples exist in the window or the query errors
  /// (the caller just omits `avg_bpm` from metadata in that case).
  static Future<double?> _averageHrInWindow(DateTime start, DateTime end) async {
    try {
      final samples = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: end,
      );
      final values = <double>[];
      for (final s in samples) {
        final v = s.value;
        if (v is NumericHealthValue) {
          final bpm = v.numericValue.toDouble();
          // Same sanity clamp the watch uses: anything outside 30–230
          // is sensor noise and shouldn't bias the average.
          if (bpm >= 30 && bpm <= 230) values.add(bpm);
        }
      }
      if (values.isEmpty) return null;
      return values.reduce((a, b) => a + b) / values.length;
    } catch (e) {
      debugPrint('HR fetch failed for workout window: $e');
      return null;
    }
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
