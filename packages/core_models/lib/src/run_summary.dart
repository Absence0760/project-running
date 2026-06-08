import 'metadata_keys.dart';
import 'run.dart';
import 'run_source.dart';

/// A lightweight projection of a [Run] carrying only the scalar fields the
/// local-store consumers read off the full history — never the GPS [Run.track]
/// or the bulky metadata keys (`laps`, `workout_step_results`,
/// `running_dynamics`, …). The local stores keep one of these per row in a
/// single on-disk index file, so cold-load reads ONE file instead of N per-row
/// JSON files, and the full [Run] objects can be windowed (only a recent
/// working set held resident) while every all-time consumer still sees the
/// whole history through [toRun].
///
/// The carried set is fixed by the real readers: distance/duration (list +
/// pace), `source` + `activityType` (filter chips), `externalId` (import
/// dedup), `avgBpm` (HR cards / training load), `elevationM` (year-in-running
/// recap), `indoor` (fitness excludes indoor runs from the VDOT pool),
/// `lastModifiedAt` (newer-wins clock), `createdByUserId` (owner tag,
/// decisions §67), `synced` (unsynced badge + sync drain). Excluded — recovered
/// on demand via the store's `runById`: `track`, `routeId`, `createdAt`, every
/// other metadata key (`title`, `notes`, `laps`, `workout_step_results`, …).
class RunSummary {
  final String id;
  final DateTime startedAt;
  final Duration duration;
  final double distanceMetres;
  final RunSource source;
  final String? activityType;
  final String? externalId;
  final double? avgBpm;
  final double? elevationM;
  final bool indoor;
  final String? lastModifiedAt;
  final String? createdByUserId;
  final bool synced;

  const RunSummary({
    required this.id,
    required this.startedAt,
    required this.duration,
    required this.distanceMetres,
    required this.source,
    this.activityType,
    this.externalId,
    this.avgBpm,
    this.elevationM,
    this.indoor = false,
    this.lastModifiedAt,
    this.createdByUserId,
    this.synced = false,
  });

  /// Project a full [Run] into a summary. [synced] comes from the store's
  /// sync-state sidecar, not the run itself.
  factory RunSummary.fromRun(Run run, {required bool synced}) {
    final meta = run.metadata;
    return RunSummary(
      id: run.id,
      startedAt: run.startedAt,
      duration: run.duration,
      distanceMetres: run.distanceMetres,
      source: run.source,
      activityType: meta?[MetadataKeys.activityType] as String?,
      externalId: run.externalId,
      avgBpm: (meta?[MetadataKeys.avgBpm] as num?)?.toDouble(),
      elevationM: (meta?[MetadataKeys.elevationM] as num?)?.toDouble(),
      indoor: meta?[MetadataKeys.indoor] == true,
      lastModifiedAt: meta?[MetadataKeys.lastModifiedAt] as String?,
      createdByUserId: meta?[MetadataKeys.createdByUserId] as String?,
      synced: synced,
    );
  }

  /// A copy with a flipped [synced] flag — the store updates this in memory on
  /// `markSynced` without re-reading the row file.
  RunSummary withSynced(bool value) => RunSummary(
        id: id,
        startedAt: startedAt,
        duration: duration,
        distanceMetres: distanceMetres,
        source: source,
        activityType: activityType,
        externalId: externalId,
        avgBpm: avgBpm,
        elevationM: elevationM,
        indoor: indoor,
        lastModifiedAt: lastModifiedAt,
        createdByUserId: createdByUserId,
        synced: value,
      );

  /// A track-less [Run] rebuilt from the carried scalars, with the
  /// metadata-derived fields stuffed back into [Run.metadata]. Lets the
  /// all-time consumers (fitness, mileage, goals, gear backfill, period
  /// summary, recap, import dedup, intensity) keep their `List<Run>` inputs
  /// unchanged — including the TS↔Dart parity helpers — while reading the full
  /// history off the index. Anything needing the track or full metadata must
  /// hydrate the real run via the store's `runById`.
  Run toRun() {
    final metadata = <String, dynamic>{
      if (activityType != null) MetadataKeys.activityType: activityType,
      if (avgBpm != null) MetadataKeys.avgBpm: avgBpm,
      if (elevationM != null) MetadataKeys.elevationM: elevationM,
      // Only carry `indoor` when true — real runs omit the key when outdoor, and
      // consumers test `metadata['indoor'] != true`.
      if (indoor) MetadataKeys.indoor: true,
      if (lastModifiedAt != null) MetadataKeys.lastModifiedAt: lastModifiedAt,
      if (createdByUserId != null) MetadataKeys.createdByUserId: createdByUserId,
    };
    return Run(
      id: id,
      startedAt: startedAt,
      duration: duration,
      distanceMetres: distanceMetres,
      track: const [],
      source: source,
      externalId: externalId,
      metadata: metadata.isEmpty ? null : metadata,
    );
  }

  /// Compact wire shape for the on-disk index (snake_case, microsecond
  /// duration). Deliberately NOT [Run.toJson] — the index is its own format.
  Map<String, dynamic> toIndexJson() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'duration_us': duration.inMicroseconds,
        'distance_m': distanceMetres,
        'source': source.name,
        'activity_type': activityType,
        'external_id': externalId,
        'avg_bpm': avgBpm,
        'elevation_m': elevationM,
        'indoor': indoor,
        'last_modified_at': lastModifiedAt,
        'created_by_user_id': createdByUserId,
        'synced': synced,
      };

  factory RunSummary.fromIndexJson(Map<String, dynamic> j) => RunSummary(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['started_at'] as String),
        duration: Duration(microseconds: (j['duration_us'] as num).toInt()),
        distanceMetres: (j['distance_m'] as num).toDouble(),
        source: _sourceFromName(j['source'] as String?),
        activityType: j['activity_type'] as String?,
        externalId: j['external_id'] as String?,
        avgBpm: (j['avg_bpm'] as num?)?.toDouble(),
        elevationM: (j['elevation_m'] as num?)?.toDouble(),
        indoor: j['indoor'] == true,
        lastModifiedAt: j['last_modified_at'] as String?,
        createdByUserId: j['created_by_user_id'] as String?,
        synced: j['synced'] == true,
      );

  static RunSource _sourceFromName(String? name) {
    if (name == null) return RunSource.app;
    for (final s in RunSource.values) {
      if (s.name == name) return s;
    }
    return RunSource.app;
  }
}
