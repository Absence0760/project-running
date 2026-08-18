import 'generated/db_rows.dart';
import 'metadata_keys.dart';
import 'run.dart';

/// Metadata keys the `runs` table also stores in a column and which are
/// therefore DROPPED from the persisted bag. The column is the only stored
/// copy, so a bag copy left behind shadows a later column edit on the next
/// read-modify-write.
///
/// `activity_type` / `is_dnf` were promoted by migration `20261207_001`, the
/// four embedded bests by `20270325_001`. `track_url` / `hr_series_url` are
/// the read-side stashes `ApiClient._runFromRow` synthesises back out of their
/// columns for lazy-loading callers; they are never authored into the bag.
const Map<String, String> kRunPromotedMetadataColumns = <String, String>{
  MetadataKeys.activityType: RunRow.colActivityType,
  MetadataKeys.isDnf: RunRow.colIsDnf,
  MetadataKeys.fastest5kS: RunRow.colFastest5kS,
  MetadataKeys.fastest10kS: RunRow.colFastest10kS,
  MetadataKeys.fastestHalfMarathonS: RunRow.colFastestHalfMarathonS,
  MetadataKeys.fastestMarathonS: RunRow.colFastestMarathonS,
  MetadataKeys.trackUrl: RunRow.colTrackUrl,
  MetadataKeys.hrSeriesUrl: RunRow.colHrSeriesUrl,
};

/// Metadata keys mirrored into a column but KEPT in the bag — migration
/// `20270302_001` promoted elevation for the vert aggregate and had writers
/// populate both, so the bag copy here is not a shadow.
const Map<String, String> kRunMirroredMetadataColumns = <String, String>{
  MetadataKeys.elevationM: RunRow.colElevationGainM,
};

/// The bag as it is persisted: every [kRunPromotedMetadataColumns] key
/// removed. Collapses to null when nothing else was in it.
Map<String, dynamic>? runMetadataForRow(Map<String, dynamic>? metadata) {
  if (metadata == null) return null;
  final out = Map<String, dynamic>.from(metadata)
    ..removeWhere((k, _) => kRunPromotedMetadataColumns.containsKey(k));
  return out.isEmpty ? null : out;
}

/// Bag → column lift for a promoted embedded-best key. Non-negative integers
/// only — the domain the old SQL-side `~ '^[0-9]+$'` validation admitted;
/// anything else is dropped rather than written.
int? runEmbeddedBestSeconds(Map<String, dynamic>? metadata, String key) {
  final v = metadata?[key];
  final secs = v is int ? v : (v is num ? v.toInt() : null);
  if (secs == null || secs < 0) return null;
  return secs;
}

/// Bag → column lift for a promoted numeric key that stays in the bag too.
double? runPromotedDouble(Map<String, dynamic>? metadata, String key) {
  final v = metadata?[key];
  if (v is num && v.isFinite) return v.toDouble();
  return null;
}

/// The one place a [Run] becomes a raw `runs` row.
///
/// Both writers go through here — `ApiClient.saveRun` / `saveRunsBatch` on
/// the wire, and `BackupService.rawRunRowForBackup` for the device-only rows
/// an archive carries — so a newly promoted column cannot land on one and not
/// the other, which is how the archive came to omit `elevation_gain_m`.
///
/// [startedAt] is forced to UTC: `toIso8601String()` on a local `DateTime`
/// emits a naive string with no offset, which a `timestamptz` reads as UTC —
/// off by the runner's offset and potentially a whole calendar day.
RunRow runRowFromRun(
  Run run, {
  required String userId,
  String? trackUrl,
  bool? isPublic,
  DateTime? createdAt,
}) {
  final meta = run.metadata;
  return RunRow(
    id: run.id,
    userId: userId,
    startedAt: run.startedAt.toUtc(),
    durationS: run.duration.inSeconds,
    distanceM: run.distanceMetres,
    routeId: run.routeId,
    source: run.source.name,
    externalId: run.externalId,
    metadata: runMetadataForRow(meta),
    createdAt: createdAt,
    trackUrl: trackUrl,
    isPublic: isPublic,
    activityType: (meta?[MetadataKeys.activityType] as String?) ?? 'run',
    isDnf: meta?[MetadataKeys.isDnf] == true,
    elevationGainM: runPromotedDouble(meta, MetadataKeys.elevationM),
    fastest5kS: runEmbeddedBestSeconds(meta, MetadataKeys.fastest5kS),
    fastest10kS: runEmbeddedBestSeconds(meta, MetadataKeys.fastest10kS),
    fastestHalfMarathonS:
        runEmbeddedBestSeconds(meta, MetadataKeys.fastestHalfMarathonS),
    fastestMarathonS:
        runEmbeddedBestSeconds(meta, MetadataKeys.fastestMarathonS),
  );
}
