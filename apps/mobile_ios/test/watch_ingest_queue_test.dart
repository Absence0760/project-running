// Unit tests for the pure decoders in `lib/watch_ingest_queue.dart`:
// `runFromWatchPayload` (canonical watch-run JSON → cm.Run) and
// `parseRunSource` (enum-name string → RunSource with watch fallback).
//
// The full `WatchIngestQueue` class is disk-backed (PathProvider) and
// is covered by integration-style screen tests; this file scopes to
// the pure helpers exposed for unit testing per the file's docstring
// ("Pure — exposed for tests so the payload schema can be exercised
// without disk IO.").
//
// The watch-run JSON is the wire format produced by both the Wear OS
// (Kotlin) sender and the watchOS (Swift) sender — see
// `apps/watch_wear/.../WatchRunMetadata.kt` + `apps/watch_ios/...`.
// A regression in either field-extraction or fallback behaviour here
// would silently drop runs that arrived from the watch before
// sign-in (the queue's whole purpose).

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/watch_ingest_queue.dart';

void main() {
  group('parseRunSource', () {
    test('round-trips every RunSource value through its .name', () {
      // The payload's `source` field carries the lowercase enum
      // identifier. Pairing must round-trip — a regression in
      // either half would silently mis-classify watch runs on the
      // wire (e.g. an HKHealthKit-derived run landing as `app`).
      for (final src in RunSource.values) {
        expect(parseRunSource(src.name), src,
            reason: 'round-trip failed for ${src.name}');
      }
    });

    test('unknown name falls back to watch', () {
      // The fallback is `watch` (not `app`) because every caller
      // of this function is the watch-payload decoder — any
      // unrecognised source string came from a watch sender, by
      // contract. A regression that defaulted to `app` would
      // make watch-origin runs disappear from the by-source
      // filter chip row.
      expect(parseRunSource('not-a-source'), RunSource.watch);
      expect(parseRunSource(''), RunSource.watch);
    });
  });

  group('runFromWatchPayload', () {
    Map<String, dynamic> baseline({
      String id = 'run-123',
      String startedAt = '2026-05-19T08:00:00Z',
      int durationS = 1800,
      double distanceM = 5000,
      String source = 'watch',
    }) =>
        {
          'id': id,
          'started_at': startedAt,
          'duration_s': durationS,
          'distance_m': distanceM,
          'source': source,
        };

    test('decodes the minimum-valid payload', () {
      final run = runFromWatchPayload(baseline());
      expect(run.id, 'run-123');
      expect(run.startedAt.toUtc().toIso8601String(), '2026-05-19T08:00:00.000Z');
      expect(run.duration, const Duration(seconds: 1800));
      expect(run.distanceMetres, 5000.0);
      expect(run.source, RunSource.watch);
      expect(run.track, isEmpty);
      expect(run.metadata, isNull);
    });

    test('empty id field falls back to "" (caller assigns id)', () {
      // Watch senders that don't generate their own UUID let the
      // pre-save path mint one. A regression that threw on missing
      // id would break the watch-handoff path entirely.
      final raw = baseline()..remove('id');
      final run = runFromWatchPayload(raw);
      expect(run.id, '');
    });

    test('missing source field falls back to RunSource.watch', () {
      // Older watch senders pre-dated the `source` field. The
      // decoder must not throw on its absence — every legacy
      // queued payload would be permanently stuck otherwise.
      final raw = baseline()..remove('source');
      final run = runFromWatchPayload(raw);
      expect(run.source, RunSource.watch);
    });

    test('decodes a track with mixed-detail waypoints', () {
      final raw = baseline();
      raw['track'] = [
        // Minimal: just lat/lng.
        {'lat': 51.5, 'lng': -0.1},
        // With elevation.
        {'lat': 51.51, 'lng': -0.11, 'ele': 25.3},
        // With timestamp.
        {'lat': 51.52, 'lng': -0.12, 'ts': '2026-05-19T08:01:00Z'},
        // With BPM.
        {'lat': 51.53, 'lng': -0.13, 'bpm': 142},
        // Full.
        {
          'lat': 51.54,
          'lng': -0.14,
          'ele': 30.0,
          'ts': '2026-05-19T08:02:00Z',
          'bpm': 148,
        },
      ];
      final run = runFromWatchPayload(raw);
      expect(run.track.length, 5);
      expect(run.track[0].lat, 51.5);
      expect(run.track[0].elevationMetres, isNull);
      expect(run.track[0].timestamp, isNull);
      expect(run.track[0].bpm, isNull);
      expect(run.track[1].elevationMetres, 25.3);
      expect(run.track[2].timestamp?.toUtc().toIso8601String(),
          '2026-05-19T08:01:00.000Z');
      expect(run.track[3].bpm, 142);
      expect(run.track[4].bpm, 148);
      expect(run.track[4].elevationMetres, 30.0);
    });

    test('decimal bpm is floored to int (Waypoint.bpm is int?)', () {
      // Health Services + HKLiveWorkoutBuilder both emit doubles
      // (heart rate is technically a continuous measure). The
      // floor preserves the integer-typed Waypoint.bpm contract —
      // a regression to .round() would change the wire shape
      // observed by every downstream consumer (HR zone math, the
      // run-detail BPM column).
      final raw = baseline();
      raw['track'] = [
        {'lat': 51.5, 'lng': -0.1, 'bpm': 142.9},
      ];
      final run = runFromWatchPayload(raw);
      expect(run.track[0].bpm, 142, reason: 'decimal 142.9 should floor to 142');
    });

    test('non-Map track entries are silently skipped (malformed-input safety)', () {
      // A watch sender could ship a partially-corrupted track
      // array. The decoder must drop non-Map entries rather than
      // throw — losing one point is fine; losing the whole run
      // because of one point isn't.
      final raw = baseline();
      raw['track'] = [
        {'lat': 51.5, 'lng': -0.1},
        'corrupt-string',
        42,
        null,
        {'lat': 51.51, 'lng': -0.11},
      ];
      final run = runFromWatchPayload(raw);
      expect(run.track.length, 2);
    });

    test('null track field yields an empty track (no throw)', () {
      // Same defensive contract as missing track field — the
      // payload-without-track shape must work for senders that
      // don't carry a GPS trace (HRM-only watch sessions).
      final raw = baseline();
      raw['track'] = null;
      final run = runFromWatchPayload(raw);
      expect(run.track, isEmpty);
    });

    test('avg_bpm + activity_type forward into metadata', () {
      final raw = baseline();
      raw['avg_bpm'] = 145;
      raw['activity_type'] = 'run';
      final run = runFromWatchPayload(raw);
      expect(run.metadata, isNotNull);
      expect(run.metadata!['avg_bpm'], 145.0);
      expect(run.metadata!['activity_type'], 'run');
    });

    test('decimal avg_bpm is preserved as double (not floored)', () {
      // avg_bpm lives in jsonb metadata — no integer constraint
      // there. Preserving the double matches the watch sender's
      // (Health Services / HKHealthStore) precision.
      final raw = baseline();
      raw['avg_bpm'] = 145.7;
      final run = runFromWatchPayload(raw);
      expect(run.metadata!['avg_bpm'], 145.7);
    });

    test('non-string activity_type is dropped from metadata', () {
      // Defensive: a sender bug that emitted `activity_type: 42`
      // must not land a non-string in metadata that downstream
      // readers (web + Dart) would then crash on. The `is String`
      // guard silently drops it; the rest of metadata still
      // forwards.
      final raw = baseline();
      raw['avg_bpm'] = 145;
      raw['activity_type'] = 42;
      final run = runFromWatchPayload(raw);
      expect(run.metadata!.containsKey('activity_type'), isFalse);
      expect(run.metadata!['avg_bpm'], 145.0);
    });

    test('laps array forwards verbatim per docs/metadata.md § laps', () {
      // The canonical lap shape is per-lap deltas: `[{ index,
      // start_offset_s, distance_m, duration_s }]`. The decoder
      // forwards the array as-is so a watch sender that emits the
      // registered shape round-trips through the queue without
      // mutation. A regression that re-cumulated or re-indexed
      // would corrupt every queued run's lap display.
      final raw = baseline();
      raw['laps'] = [
        {'index': 0, 'start_offset_s': 0, 'distance_m': 1000.0, 'duration_s': 300},
        {'index': 1, 'start_offset_s': 300, 'distance_m': 1000.0, 'duration_s': 305},
      ];
      final run = runFromWatchPayload(raw);
      expect(run.metadata!['laps'], hasLength(2));
      final firstLap = (run.metadata!['laps'] as List)[0] as Map;
      expect(firstLap['index'], 0);
      expect(firstLap['start_offset_s'], 0);
      expect(firstLap['distance_m'], 1000.0);
      expect(firstLap['duration_s'], 300);
    });

    test('malformed laps entries are silently filtered', () {
      // Same malformed-input safety as the track array — non-Map
      // entries get dropped, the surviving rows ship to metadata.
      final raw = baseline();
      raw['laps'] = [
        {'index': 0, 'distance_m': 1000.0},
        'not-a-map',
        null,
        42,
        {'index': 1, 'distance_m': 1000.0},
      ];
      final run = runFromWatchPayload(raw);
      expect(run.metadata!['laps'], hasLength(2));
    });

    test('non-list laps field is silently ignored', () {
      // A sender bug emitting `laps: "n/a"` (a string) must not
      // throw; the metadata simply omits the laps key.
      final raw = baseline();
      raw['laps'] = 'n/a';
      final run = runFromWatchPayload(raw);
      expect(run.metadata, isNull);
    });

    test('integer distance_m + duration_s tolerated (num coercion)', () {
      // Senders may serialise these as int or double depending on
      // the precision at the source. The decoder must accept both
      // — a JSON.encode roundtrip might emit either depending on
      // the platform's serialiser.
      final raw = baseline(durationS: 1800, distanceM: 5000)
        ..['distance_m'] = 5000 // int instead of double
        ..['duration_s'] = 1800.0; // double instead of int
      final run = runFromWatchPayload(raw);
      expect(run.distanceMetres, 5000.0);
      expect(run.duration, const Duration(seconds: 1800));
    });
  });
}
