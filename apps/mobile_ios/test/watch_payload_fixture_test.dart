import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/watch_ingest_queue.dart';

/// Cross-platform contract test for the canonical watch-run payload.
///
/// The fixture at `fixtures/watch_run_payload.json` (repo root) is shared
/// with the Wear OS test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`)
/// and the web test (`apps/web/src/lib/watch_payload_fixture.test.ts`).
/// All three platforms decode the same file and must agree on the shape.
/// If you change a field here, update both other tests in the same commit.
///
/// This is the guardrail for the class of bugs the April 2026 audit found:
/// laps shape divergence, missing per-point bpm, missing activity_type.
void main() {
  group('canonical watch-run payload fixture', () {
    late Map<String, dynamic> fixture;
    late Map<String, dynamic> payload;
    late Map<String, dynamic> expectedRow;
    late Map<String, dynamic> expectedMetadata;

    setUpAll(() {
      // The test runner cwd is the package dir
      // (apps/mobile_android/), so repo root is two parents up.
      final file = File('../../fixtures/watch_run_payload.json');
      fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      payload = fixture['payload'] as Map<String, dynamic>;
      expectedRow = fixture['expectedRow'] as Map<String, dynamic>;
      expectedMetadata = fixture['expectedMetadata'] as Map<String, dynamic>;
    });

    test('row fields match expectedRow', () {
      final run = runFromWatchPayload(payload);
      expect(run.source.name, expectedRow['source']);
      expect(run.duration.inSeconds, expectedRow['duration_s']);
      expect(run.distanceMetres, expectedRow['distance_m']);
    });

    test('metadata.activity_type round-trips', () {
      final run = runFromWatchPayload(payload);
      expect(run.metadata?['activity_type'], expectedMetadata['activity_type']);
    });

    test('metadata.avg_bpm round-trips as a number', () {
      final run = runFromWatchPayload(payload);
      // avg_bpm is stored as double (the existing decoder casts to double).
      expect(run.metadata?['avg_bpm'], expectedMetadata['avg_bpm']);
    });

    test('metadata.laps preserves canonical per-lap shape', () {
      final run = runFromWatchPayload(payload);
      final laps = (run.metadata?['laps'] as List).cast<Map>();
      final expectedLaps = (expectedMetadata['laps'] as List).cast<Map>();
      expect(laps.length, expectedLaps.length);
      for (var i = 0; i < laps.length; i++) {
        expect(laps[i]['index'], expectedLaps[i]['index']);
        expect(laps[i]['start_offset_s'], expectedLaps[i]['start_offset_s']);
        expect(laps[i]['distance_m'], expectedLaps[i]['distance_m']);
        expect(laps[i]['duration_s'], expectedLaps[i]['duration_s']);
      }
    });

    test('track waypoint count + per-point bpm round-trip', () {
      final run = runFromWatchPayload(payload);
      expect(run.track.length, fixture['expectedTrackCount']);
      expect(run.track.first.bpm, fixture['expectedFirstPointBpm']);
      // Elevation + timestamp also round-trip on the first point.
      expect(run.track.first.elevationMetres, isNotNull);
      expect(run.track.first.timestamp, isNotNull);
    });
  });
}
