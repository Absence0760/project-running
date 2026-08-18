import 'package:core_models/core_models.dart' as cm;
import 'package:flutter_test/flutter_test.dart';

import '../lib/backup.dart';

/// Pins the archive's `runs.json` row against the shaper the wire writer uses.
///
/// `rawRunRowForBackup` used to carry its own copy of the promoted-column lift
/// so a device-only row would match what `saveRun` writes. It had already
/// drifted: `elevation_gain_m` was promoted by `20270302_001` and the wire
/// writer fills it, the archive copy never learned to, so every restored
/// local-only run read as 0 m of vert on the challenge board.
///
/// The loop below is driven by the registry in `run_row_shape.dart` rather
/// than by a hand-written list, so promoting a column and forgetting the
/// archive fails here instead of shipping.
void main() {
  cm.Run run() => cm.Run(
        id: 'local-1',
        startedAt: DateTime.utc(2026, 4, 10, 8),
        duration: const Duration(seconds: 1500),
        distanceMetres: 5000,
        source: cm.RunSource.app,
        createdAt: DateTime.utc(2026, 4, 10, 9),
        metadata: const {
          cm.MetadataKeys.activityType: 'trail_run',
          cm.MetadataKeys.isDnf: true,
          cm.MetadataKeys.elevationM: 480.0,
          cm.MetadataKeys.fastest5kS: 1200,
          cm.MetadataKeys.fastest10kS: 2500,
          cm.MetadataKeys.fastestHalfMarathonS: 5600,
          cm.MetadataKeys.fastestMarathonS: 11000,
          cm.MetadataKeys.trackUrl: 'old-owner/local-1.json.gz',
          cm.MetadataKeys.title: 'Ridge loop',
        },
      );

  test('the archive fills every column the registry declares', () {
    final row = BackupService.rawRunRowForBackup(run());
    for (final col in [
      ...cm.kRunPromotedMetadataColumns.values,
      ...cm.kRunMirroredMetadataColumns.values,
    ]) {
      // The archive deliberately carries neither storage pointer: the track
      // blob rides in `tracks/<id>.json.gz` and either URL names the OLD
      // owner's path, which the restore rewrites.
      if (col == cm.RunRow.colTrackUrl || col == cm.RunRow.colHrSeriesUrl) {
        expect(row[col], isNull);
        continue;
      }
      expect(row[col], isNotNull, reason: '$col is missing from the archive row');
    }
    expect(row[cm.RunRow.colElevationGainM], 480.0);
  });

  test('no promoted key survives in the archived bag', () {
    final bag = BackupService.rawRunRowForBackup(run())[cm.RunRow.colMetadata]
        as Map<String, dynamic>?;
    for (final key in cm.kRunPromotedMetadataColumns.keys) {
      expect(bag?.containsKey(key) ?? false, isFalse, reason: '$key shadows its column');
    }
    // The mirrored key is a deliberate double-write and stays.
    expect(bag, {
      cm.MetadataKeys.elevationM: 480.0,
      cm.MetadataKeys.title: 'Ridge loop',
    });
  });

  test('the archive row is the wire row less the owner and the track url', () {
    final archived = BackupService.rawRunRowForBackup(run());
    final wire = cm
        .runRowFromRun(run(), userId: 'owner-1', createdAt: run().createdAt)
        .toJson()
      ..remove(cm.RunRow.colUserId)
      ..remove(cm.RunRow.colTrackUrl);
    expect(archived, wire);
  });
}
