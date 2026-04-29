import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/watch_ingest_queue.dart';

void main() {
  group('parseRunSource', () {
    test('matches every enum value by name', () {
      for (final s in RunSource.values) {
        expect(parseRunSource(s.name), s);
      }
    });

    test('falls back to RunSource.watch for unknown / empty input', () {
      expect(parseRunSource(''), RunSource.watch);
      expect(parseRunSource('not-a-real-source'), RunSource.watch);
      // Mixed-case is also unknown — enum names are lowercase.
      expect(parseRunSource('WATCH'), RunSource.watch);
    });
  });

  group('runFromWatchPayload', () {
    Map<String, dynamic> _basePayload() => {
          'id': 'r-1',
          'started_at': '2026-04-15T07:30:00Z',
          'duration_s': 1800,
          'distance_m': 5234.5,
          'source': 'watch',
        };

    test('decodes the required fields', () {
      final run = runFromWatchPayload(_basePayload());
      expect(run.id, 'r-1');
      expect(run.startedAt.toUtc(), DateTime.utc(2026, 4, 15, 7, 30));
      expect(run.duration, const Duration(minutes: 30));
      expect(run.distanceMetres, 5234.5);
      expect(run.source, RunSource.watch);
      expect(run.track, isEmpty);
      expect(run.metadata, isNull);
    });

    test('falls back to id="" and source="watch" when missing', () {
      // The watch native bridge occasionally posts a payload without an
      // explicit source — the queue must still accept it.
      final raw = _basePayload();
      raw.remove('id');
      raw.remove('source');
      final run = runFromWatchPayload(raw);
      expect(run.id, '');
      expect(run.source, RunSource.watch);
    });

    test('decodes track waypoints with optional ele + ts', () {
      final raw = _basePayload()
        ..['track'] = [
          {'lat': 37.0, 'lng': -122.0, 'ele': 50, 'ts': '2026-04-15T07:30:05Z'},
          {'lat': 37.0001, 'lng': -122.0001},
        ];
      final run = runFromWatchPayload(raw);
      expect(run.track, hasLength(2));
      expect(run.track.first.lat, 37.0);
      expect(run.track.first.elevationMetres, 50);
      expect(run.track.first.timestamp,
          DateTime.utc(2026, 4, 15, 7, 30, 5));
      expect(run.track.last.elevationMetres, isNull);
      expect(run.track.last.timestamp, isNull);
    });

    test('decodes per-point bpm into Waypoint.bpm', () {
      // Reason: both watch platforms ship per-point heart rate; the
      // Apr 2026 audit caught the decoder dropping it. The phone
      // re-uploads the run with track.bpm preserved, which is what
      // the web HR-zones panel and mobile run-detail screens read.
      final raw = _basePayload()
        ..['track'] = [
          {'lat': 37.0, 'lng': -122.0, 'bpm': 145},
          {'lat': 37.0001, 'lng': -122.0001, 'bpm': 152.7}, // float → floor
          {'lat': 37.0002, 'lng': -122.0002}, // no bpm → null
        ];
      final run = runFromWatchPayload(raw);
      expect(run.track, hasLength(3));
      expect(run.track[0].bpm, 145);
      expect(run.track[1].bpm, 152);
      expect(run.track[2].bpm, isNull);
    });

    test('skips non-Map entries inside the track list', () {
      final raw = _basePayload()
        ..['track'] = [
          {'lat': 1.0, 'lng': 2.0},
          'not a map',
          42,
        ];
      final run = runFromWatchPayload(raw);
      expect(run.track, hasLength(1));
    });

    test('promotes avg_bpm + activity_type into metadata', () {
      final raw = _basePayload()
        ..['avg_bpm'] = 145
        ..['activity_type'] = 'run';
      final run = runFromWatchPayload(raw);
      expect(run.metadata, isNotNull);
      expect(run.metadata!['avg_bpm'], 145.0);
      expect(run.metadata!['activity_type'], 'run');
    });

    test('omits metadata when neither avg_bpm nor activity_type is present',
        () {
      // Reason: the saveRun pipeline treats null and empty-map metadata
      // differently — null means "leave the column alone", empty means
      // "overwrite with {}". We must keep null when nothing was set.
      final run = runFromWatchPayload(_basePayload());
      expect(run.metadata, isNull);
    });

    test('non-num avg_bpm is ignored', () {
      // Defensive: the ObjC bridge has historically sent strings here
      // for a beat or two before the type-checker lands.
      final raw = _basePayload()..['avg_bpm'] = 'one-fifty';
      final run = runFromWatchPayload(raw);
      expect(run.metadata, isNull);
    });

    test('an unknown source string still resolves to RunSource.watch',
        () {
      final raw = _basePayload()..['source'] = 'mystery';
      final run = runFromWatchPayload(raw);
      expect(run.source, RunSource.watch);
    });

    test('forwards a laps array verbatim into metadata', () {
      // Reason: per docs/metadata.md § laps the canonical shape is
      // { index, start_offset_s, distance_m, duration_s }. Wear OS
      // already writes this shape; the watch ingest path must preserve
      // it byte-for-byte so a future watch sender that pipes through
      // the phone (instead of uploading direct) doesn't lose the
      // user's mid-run lap markers.
      final raw = _basePayload()
        ..['laps'] = [
          {
            'index': 1,
            'start_offset_s': 0,
            'distance_m': 1000.0,
            'duration_s': 300,
          },
          {
            'index': 2,
            'start_offset_s': 300,
            'distance_m': 1200.0,
            'duration_s': 360,
          },
        ];
      final run = runFromWatchPayload(raw);
      expect(run.metadata, isNotNull);
      expect(run.metadata!['laps'], hasLength(2));
      expect(run.metadata!['laps'][0]['index'], 1);
      expect(run.metadata!['laps'][1]['distance_m'], 1200.0);
    });

    test('a non-list laps payload is ignored (no metadata.laps key)', () {
      // Defensive: if the watch ever ships laps as a Map (or anything
      // else) by mistake, drop it rather than crashing the decoder.
      final raw = _basePayload()..['laps'] = {'oops': 'wrong shape'};
      final run = runFromWatchPayload(raw);
      // metadata stays null because no other field was set either.
      expect(run.metadata, isNull);
    });
  });
}
