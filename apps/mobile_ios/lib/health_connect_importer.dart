import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import 'embedded_bests.dart';
import 'import_failures.dart';
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

/// What one Health Connect route read produced: the tracks it released, the
/// sessions whose route it refused to release, and — when the read itself
/// threw — the error behind an empty result. Without that last field an
/// outright failed read is indistinguishable from a source that genuinely
/// holds no routes, and the import tells the runner the wrong one.
typedef HealthConnectRoutes = ({
  Map<String, List<Waypoint>> tracks,
  Set<String> withheldSessionIds,
  Object? readFailure,
});

/// A Health Connect import: the runs, the sessions whose GPS route Health
/// Connect withheld, and the workouts that could not be mapped at all. The
/// withheld set is the only honest trigger for offering the route grant —
/// there is no point asking a runner for a permission that would buy them
/// nothing. `failures` names the workouts that were dropped: they used to
/// vanish into a `debugPrint` with nothing on screen at all, so a session
/// Health Connect could not hand over simply never appeared.
typedef HealthConnectImport = ({
  List<Run> runs,
  Set<String> withheldSessionIds,
  ImportFailureLog failures,
});

/// The Health Connect permission that releases a workout's GPS route. Must
/// agree with `AndroidManifest.xml`, `res/xml/health_permissions.xml` and
/// `HealthRoutePermissionBridge.PERMISSION`; a mismatch is refused by the
/// platform with no dialog and no error the runner can act on.
const String kHealthRoutePermission =
    'android.permission.health.READ_EXERCISE_ROUTES';

/// Method channel to `HealthRoutePermissionBridge.kt`. Android only.
@visibleForTesting
const MethodChannel healthRoutePermissionChannel =
    MethodChannel('run_app/health_route_permission');

/// Ask Health Connect for the exercise-route grant.
///
/// Only ever called from an explicit runner action, never chained onto the
/// import's own permission sheet — tapping "import" must not spring a second
/// system dialog on someone who asked for workouts, not for location data.
///
/// Returns false off Android, when Health Connect isn't installed, when the
/// runner refuses, and on any channel error. Every one of those leaves the
/// import working exactly as it does today, summary-only.
Future<bool> requestHealthRoutePermission({required bool isAndroid}) async {
  if (!isAndroid) return false;
  try {
    final granted = await healthRoutePermissionChannel
        .invokeMethod<bool>('requestRoutePermission');
    return granted == true;
  } catch (e) {
    debugPrint('Health Connect route permission request failed: $e');
    return false;
  }
}

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
      // Android-only for the same reason as WORKOUT_ROUTE above, though the
      // asymmetry is the other way round: the plugin's Health Connect
      // workout handler sums a StepsRecord read into totalSteps, while its
      // HealthKit one never populates that field at all. So on iOS this
      // would widen what the build collects and buy nothing back.
      if (Platform.isAndroid) HealthDataType.STEPS,
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
  static Future<HealthConnectImport> fetchWorkouts({
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

    final routes = await fetchRoutes(from: start, to: end);
    final routeTracks = routes.tracks;

    final runs = <Run>[];
    final failures = newImportFailureLog();
    // A refused route read leaves exactly the shape a source with no routes
    // leaves, so without this the import would tell the runner their maps
    // don't exist when they were simply unreadable.
    if (routes.readFailure != null) {
      recordImportFailure(
        failures,
        name: 'GPS routes',
        error: routes.readFailure,
      );
    }
    for (final point in data) {
      // Filled as soon as the workout identifies itself so the catch below
      // can name what was dropped; a throw before that still reports, under
      // the unnamed-activity fallback.
      var label = '';
      String? startedAt;
      try {
        final value = point.value;
        if (value is! WorkoutHealthValue) continue;
        label = value.workoutActivityType.name;
        startedAt = point.dateFrom.toUtc().toIso8601String();

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
          MetadataKeys.importedAt: DateTime.now().toUtc().toIso8601String(),
          MetadataKeys.healthConnectType: value.workoutActivityType.name,
          MetadataKeys.activityType: activityType,
        };
        if (avgBpm != null) metadata[MetadataKeys.avgBpm] = avgBpm;

        final steps = stepsForWorkout(
          activityType: activityType,
          totalSteps: value.totalSteps,
          duration: point.dateTo.difference(point.dateFrom),
        );
        if (steps != null) metadata[MetadataKeys.steps] = steps;

        // Both the workout point and its route point carry the same
        // ExerciseSessionRecord id, so that is the join key.
        final track = routeTracks[point.uuid] ?? const <Waypoint>[];

        final externalId = '$_externalIdPrefix${point.uuid}';
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
        recordImportFailure(
          failures,
          name: label,
          startedAt: startedAt,
          error: e,
        );
      }
    }
    return (
      runs: runs,
      withheldSessionIds: routes.withheldSessionIds,
      failures: failures,
    );
  }

  /// Per-workout GPS tracks Health Connect will release for the window, keyed
  /// by `ExerciseSessionRecord` id, plus the sessions it refused to release.
  ///
  /// Wrapped whole: a route read that throws (permission revoked mid-import,
  /// Health Connect updating underneath us) degrades every workout in the
  /// batch to a summary-only import rather than failing the import outright.
  static Future<HealthConnectRoutes> fetchRoutes({
    DateTime? from,
    DateTime? to,
  }) async {
    if (!Platform.isAndroid) {
      return (
        tracks: const <String, List<Waypoint>>{},
        withheldSessionIds: const <String>{},
        readFailure: null,
      );
    }
    try {
      final data = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT_ROUTE],
        startTime: from ?? DateTime.now().subtract(const Duration(days: 365)),
        endTime: to ?? DateTime.now(),
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
      return (
        tracks: tracksFromRoutePoints(routes),
        withheldSessionIds: withheldRouteSessionIds(routes),
        readFailure: null,
      );
    } catch (e) {
      debugPrint('Health Connect route fetch failed: $e');
      return (
        tracks: const <String, List<Waypoint>>{},
        withheldSessionIds: const <String>{},
        readFailure: e,
      );
    }
  }

  /// Sessions whose GPS route Health Connect has but refused to release.
  ///
  /// The plugin renders `ExerciseRouteResult.ConsentRequired` as a
  /// `WORKOUT_ROUTE` point carrying zero locations, and emits nothing at all
  /// for a session that simply has no route (`NoData`). So an empty point
  /// means "this workout has a route you are not allowed to read" — the one
  /// case where asking for `READ_EXERCISE_ROUTES` would actually produce a
  /// map, and therefore the only case worth asking in.
  @visibleForTesting
  static Set<String> withheldRouteSessionIds(
    List<({String uuid, List<HcRoutePoint> points})> routes,
  ) =>
      {
        for (final route in routes)
          if (route.points.isEmpty) route.uuid,
      };

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

  static const _externalIdPrefix = 'healthconnect:';

  /// The `ExerciseSessionRecord` id behind a run imported from Health
  /// Connect, or null for a run from anywhere else. Both the route join and
  /// the after-the-fact backfill key on it, so the encoding lives here.
  static String? sessionIdOf(Run run) {
    if (run.source != RunSource.healthconnect) return null;
    final external = run.externalId;
    if (external == null || !external.startsWith(_externalIdPrefix)) return null;
    final id = external.substring(_externalIdPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Copies of the runs a just-granted route permission fills in — the only
  /// runs worth rewriting after the grant, since a Health Connect re-import
  /// is suppressed by `isCrossSourceDuplicate` and would never reach them.
  ///
  /// A run that already has a track is left alone: Health Connect is not
  /// authoritative over geometry the runner already has. So is a run from any
  /// other source, and one whose route Health Connect still withholds. The
  /// embedded bests are recomputed exactly as a routed import computes them,
  /// so a backfilled run and a first-time routed import are indistinguishable.
  static List<Run> runsWithBackfilledTracks(
    List<Run> runs,
    Map<String, List<Waypoint>> tracks,
  ) {
    final out = <Run>[];
    for (final run in runs) {
      if (run.track.isNotEmpty) continue;
      final sessionId = sessionIdOf(run);
      if (sessionId == null) continue;
      final track = tracks[sessionId];
      if (track == null || track.isEmpty) continue;
      out.add(Run(
        id: run.id,
        startedAt: run.startedAt,
        duration: run.duration,
        distanceMetres: run.distanceMetres,
        track: track,
        routeId: run.routeId,
        source: run.source,
        externalId: run.externalId,
        metadata: enrichMetadataWithEmbeddedBests(
          track: track,
          metadata: run.metadata,
        ),
        createdAt: run.createdAt,
      ));
    }
    return out;
  }

  /// The step count worth recording for an imported workout, or null when
  /// there isn't a believable one.
  ///
  /// Health Connect has no per-session step field: the plugin derives
  /// `totalSteps` by summing every `StepsRecord` overlapping the session
  /// window, whoever wrote it. Two things follow. A ride with the phone in
  /// a jersey pocket comes back with a real step count that is not the
  /// rider's cadence, and the run-detail tile divides whatever is stored by
  /// moving time and calls the result spm — so `cycle` is excluded, matching
  /// the "pedometer not meaningful for cycling" stride table. The exclusion
  /// names the bike rather than listing the foot-powered types, for the
  /// reason decisions § 598 records against `gearBackfillCandidates`: an
  /// allowlist of `{run, walk, hike}` silently drops a real activity_type
  /// nobody remembered, and a step count is wrong only where there are no
  /// steps.
  ///
  /// A count implying a cadence no human sustains is window contamination
  /// (a whole-day total overlapping a short session), not a step count, and
  /// is dropped whole — the same call the HR average makes on a sample
  /// outside 30-230 bpm. Dropping it leaves the run exactly as it imports
  /// today rather than publishing a fabricated cadence.
  @visibleForTesting
  static int? stepsForWorkout({
    required String activityType,
    required int? totalSteps,
    required Duration duration,
  }) {
    if (totalSteps == null || totalSteps <= 0) return null;
    if (activityType == 'cycle') return null;
    final minutes = duration.inSeconds / 60;
    if (minutes <= 0) return null;
    if (totalSteps / minutes > _maxPlausibleCadenceSpm) return null;
    return totalSteps;
  }

  /// Steps per minute past which a count is contamination rather than a
  /// cadence. Elite track sprinters peak near 300; nothing sustains it over
  /// a whole session, so this only ever rejects a summed foreign record.
  static const int _maxPlausibleCadenceSpm = 300;

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
        // elapsed-time: lower bound of a Health Connect query, not a calendar day.
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
