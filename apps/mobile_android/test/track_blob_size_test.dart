import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/import_failures.dart';

/// The `runs` bucket refuses a track blob past its own `file_size_limit`, and
/// the sync drain retries a failed upload forever — so an over-size track is a
/// permanent failure wearing a transient failure's clothes. decisions § 1009.
void main() {
  /// A 1 Hz recorder trace: full-precision drifting coordinates, wobbling
  /// elevation, per-second timestamps, per-point HR. The realistic shape, not
  /// a compressible one — repeated identical points would gzip to nothing and
  /// make the density claim below meaningless.
  List<Waypoint> trace(int n) {
    final rnd = Random(42);
    final start = DateTime.utc(2026, 6, 1, 6);
    var lat = 38.5733, lng = -109.5498, ele = 1230.0;
    return List.generate(n, (i) {
      lat += (rnd.nextDouble() - 0.5) * 0.00004;
      lng += (rnd.nextDouble() - 0.5) * 0.00004;
      ele += (rnd.nextDouble() - 0.5) * 0.6;
      return Waypoint(
        lat: lat,
        lng: lng,
        elevationMetres: ele,
        timestamp: start.add(Duration(seconds: i)),
        bpm: 120 + rnd.nextInt(50),
      );
    });
  }

  int gzippedBlobBytes(List<Waypoint> track) =>
      gzip.encode(utf8.encode(ApiClient.debugTrackBlobJson(track))).length;

  test('a track blob costs about 27 gzipped bytes per waypoint', () {
    // The whole reachability argument rests on this density: at ~27.3 B/pt the
    // 25 MiB limit is ~960k waypoints, which is 266 hours of 1 Hz recording
    // (unreachable) but a 94 MiB GPX (very reachable through import). If the
    // blob shape changes enough to move this materially, the arithmetic in
    // § 1009 and the constant's own doc need re-deriving — so pin it wide
    // enough not to be brittle and tight enough to notice.
    final perPoint = gzippedBlobBytes(trace(20000)) / 20000;
    expect(perPoint, greaterThan(20));
    expect(perPoint, lessThan(40));
  });

  test('the limit is not reachable by recording, and is by import', () {
    final perPoint = gzippedBlobBytes(trace(20000)) / 20000;
    final pointsAtLimit = StorageBuckets.runsBucketMaxBytes / perPoint;

    // At 1 Hz. The longest event the product models is a 112 h cutoff.
    final recordingHours = pointsAtLimit / 3600;
    expect(recordingHours, greaterThan(200),
        reason: 'a live recording must stay far short of the bucket limit; if '
            'this drops the recorder itself can strand a run');

    // The same points as GPX trkpts, which is what an import carries. Well
    // inside the 500 MiB Strava-archive cap, so the archive cap does not
    // bound this and the failure has a real member.
    expect(pointsAtLimit, lessThan(2000000),
        reason: 'an imported GPX reaches this point count long before it '
            'reaches the archive size cap');
  });

  test('an over-size blob is refused with a classifiable terminal failure', () {
    const e = TrackTooLargeException(
      runId: 'r1',
      bytes: 30000000,
      limitBytes: StorageBuckets.runsBucketMaxBytes,
      waypoints: 1100000,
    );
    // The import-failure report is the surface that already names this class,
    // so the thrown value has to land in `tooLarge` there rather than in
    // `unknown` — which is what it would do if the message stopped saying so.
    expect(classifyImportFailure(e).reason, ImportFailureReason.tooLarge);
    expect(e.toString(), contains('maximum allowed size'));
  });

  test('the refusal happens before the network, not after a 413', () {
    // The drain re-gzips and re-sends the same bytes every cycle, forever. The
    // pre-check is what stops a run that can never sync from spending a data
    // plan on proving it again.
    final src =
        File('../../packages/api_client/lib/src/api_client.dart').readAsStringSync();
    final upload = src.substring(
      src.indexOf('    final json = _trackBlobJson(usable);'),
      src.indexOf('return path;', src.indexOf('final json = _trackBlobJson(usable);')),
    );
    final guardAt = upload.indexOf('TrackTooLargeException');
    final sendAt = upload.indexOf('uploadBinary');
    expect(guardAt, greaterThan(-1),
        reason: 'the size pre-check left _uploadTrack');
    expect(sendAt, greaterThan(-1), reason: 're-anchor: uploadBinary moved');
    expect(guardAt, lessThan(sendAt),
        reason: 'the size check must run BEFORE the upload, or it saves '
            'nothing over the 413 it exists to pre-empt');
  });
}
