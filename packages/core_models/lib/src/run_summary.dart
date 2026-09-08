import 'iso_parse.dart';
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
/// `routeId` (run-detail route-comparison / attempt history), `lastModifiedAt`
/// (newer-wins clock), `createdByUserId` (owner tag, decisions §67), `synced`
/// (unsynced badge + sync drain). Excluded — recovered on demand via the
/// store's `runById`: `track`, `createdAt`, every other metadata key (`title`,
/// `notes`, `laps`, `workout_step_results`, …).
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
  final String? routeId;
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
    this.routeId,
    this.lastModifiedAt,
    this.createdByUserId,
    this.synced = false,
  });

  /// A [Run.metadata] value of the expected type, or null.
  ///
  /// `metadata` is a jsonb bag with no schema and no type-level protection, so
  /// a value of the wrong type is a thing it can hold — written by another
  /// client, an import, or a hand-edited row. A hard cast made that throw out
  /// of the projection, which the store's save path does not catch, so ONE
  /// malformed bag value discarded the whole run rather than the one field it
  /// applied to. `last_modified_at` is the worst of the five to lose that way:
  /// it is the clock deciding which copy of a run survives a merge
  /// (decisions § 1377).
  static String? _string(dynamic v) => v is String ? v : null;

  static num? _number(dynamic v) => v is num ? v : null;

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
      activityType: _string(meta?[MetadataKeys.activityType]),
      externalId: run.externalId,
      avgBpm: _number(meta?[MetadataKeys.avgBpm])?.toDouble(),
      elevationM: _number(meta?[MetadataKeys.elevationM])?.toDouble(),
      indoor: meta?[MetadataKeys.indoor] == true,
      routeId: run.routeId,
      lastModifiedAt: _string(meta?[MetadataKeys.lastModifiedAt]),
      createdByUserId: _string(meta?[MetadataKeys.createdByUserId]),
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
        routeId: routeId,
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
      routeId: routeId,
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
        'route_id': routeId,
        'last_modified_at': lastModifiedAt,
        'created_by_user_id': createdByUserId,
        'synced': synced,
      };

  /// A field the index cannot be read without, as its own named refusal.
  ///
  /// The alternative is the bare cast this replaces, whose `TypeError` names
  /// the Dart types and neither the column nor the row — so the store's
  /// recovery logged `type 'Null' is not a subtype of type 'String'` about a
  /// file with thousands of rows in it.
  static T _required<T>(Map<String, dynamic> j, String field) {
    final v = j[field];
    if (v is! T) throw FormatException('index row: $field is not usable', v);
    return v;
  }

  /// Rebuild a summary from one row of the on-disk index.
  ///
  /// Unlike [fromRun], which reads a jsonb bag another client may have
  /// written and therefore tolerates a wrong type per field, this reads a file
  /// [toIndexJson] wrote in this same build: a field it cannot read means the
  /// index is CORRUPT, not that a writer disagreed. So every unreadable field
  /// throws, and the throw is the point — `LocalRunStore._readIndex` catches
  /// it, discards the index, and rebuilds from the per-run files, which is
  /// lossless. Skipping the row instead would drop a run that is still on
  /// disk and then persist that omission on the next index write, and
  /// defaulting the field would persist the wrong value; both defeat the
  /// recovery this reaches (decisions § 1431).
  ///
  /// `started_at` is why this matters and not merely why it is tidy: it read
  /// through `DateTime.parse`, which ROLLS an impossible instant through the
  /// calendar rather than refusing it, so a corrupt date never threw, never
  /// reached the rebuild, sorted the run list by a day the runner never ran
  /// and was written back on the next flush.
  factory RunSummary.fromIndexJson(Map<String, dynamic> j) => RunSummary(
        id: _required<String>(j, 'id'),
        startedAt: parseIsoStrictRequired(j['started_at'], 'started_at'),
        duration: Duration(
            microseconds: _required<num>(j, 'duration_us').toInt()),
        distanceMetres: _required<num>(j, 'distance_m').toDouble(),
        source: _sourceFromName(j['source'] as String?),
        activityType: j['activity_type'] as String?,
        externalId: j['external_id'] as String?,
        avgBpm: (j['avg_bpm'] as num?)?.toDouble(),
        elevationM: (j['elevation_m'] as num?)?.toDouble(),
        indoor: j['indoor'] == true,
        routeId: j['route_id'] as String?,
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
