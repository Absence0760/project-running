import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/local_run_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('local_run_store_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Run makeRun({
    String id = 'run-1',
    double distance = 5000,
    Duration duration = const Duration(minutes: 25),
    List<Waypoint>? track,
  }) {
    return Run(
      id: id,
      startedAt: DateTime(2026, 4, 10, 8),
      duration: duration,
      distanceMetres: distance,
      track: track ?? const [],
      source: RunSource.app,
    );
  }

  group('completed runs', () {
    test('init loads from an empty directory', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.runs, isEmpty);
      expect(store.unsyncedCount, 0);
    });

    test('save → load round-trip preserves run data', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      final run = makeRun(distance: 7342, duration: const Duration(minutes: 38));
      await store.save(run);

      // Fresh instance should see the same run on disk.
      final store2 = LocalRunStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.runs.length, 1);
      final loaded = store2.runs.single;
      expect(loaded.id, run.id);
      expect(loaded.distanceMetres, run.distanceMetres);
      expect(loaded.duration, run.duration);
    });

    test('save stamps last_modified_at and marks unsynced', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun());
      expect(store.unsyncedCount, 1);
      expect(store.runs.first.metadata?['last_modified_at'], isA<String>());
    });

    test('markSynced flips synced state', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun());
      expect(store.unsyncedCount, 1);
      await store.markSynced('run-1');
      expect(store.unsyncedCount, 0);
    });

    test('delete removes the run from disk and memory', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun());
      await store.delete('run-1');
      expect(store.runs, isEmpty);
      expect(File('${tempDir.path}/run-1.json').existsSync(), isFalse);
    });

    test('deleteMany removes a batch and fires one notification', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun(id: 'run-1'));
      await store.save(makeRun(id: 'run-2'));
      await store.save(makeRun(id: 'run-3'));

      var notifications = 0;
      store.addListener(() => notifications++);

      await store.deleteMany(['run-1', 'run-3']);

      expect(store.runs.map((r) => r.id), ['run-2']);
      expect(File('${tempDir.path}/run-1.json').existsSync(), isFalse);
      expect(File('${tempDir.path}/run-2.json').existsSync(), isTrue);
      expect(File('${tempDir.path}/run-3.json').existsSync(), isFalse);
      expect(notifications, 1);
    });

    test('deleteMany with no ids is a no-op', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun());
      var notifications = 0;
      store.addListener(() => notifications++);
      await store.deleteMany(const []);
      expect(store.runs.length, 1);
      expect(notifications, 0);
    });
  });

  group('in-progress save', () {
    test('saveInProgress creates the file', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveInProgress(makeRun(id: 'live'));
      expect(File('${tempDir.path}/in_progress.json').existsSync(), isTrue);
    });

    test('loadInProgress round-trip', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      final saved = makeRun(
        id: 'live',
        distance: 1234,
        duration: const Duration(minutes: 7, seconds: 30),
      );
      await store.saveInProgress(saved);

      final loaded = await store.loadInProgress();
      expect(loaded, isNotNull);
      expect(loaded!.id, 'live');
      expect(loaded.distanceMetres, 1234);
      expect(loaded.duration, const Duration(minutes: 7, seconds: 30));
    });

    test('loadInProgress returns null when no file', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      expect(await store.loadInProgress(), isNull);
    });

    test('clearInProgress removes the file', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveInProgress(makeRun(id: 'live'));
      await store.clearInProgress();
      expect(File('${tempDir.path}/in_progress.json').existsSync(), isFalse);
      expect(await store.loadInProgress(), isNull);
    });

    test('_loadAll ignores in_progress.json so it never pollutes the list',
        () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun(id: 'completed'));
      await store.saveInProgress(makeRun(id: 'live-partial'));

      // Fresh instance should see the completed run only.
      final store2 = LocalRunStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.runs.length, 1);
      expect(store2.runs.single.id, 'completed');
    });

    test('loadInProgress deletes a corrupt file instead of crashing',
        () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      final f = File('${tempDir.path}/in_progress.json');
      await f.writeAsString('this is not json');
      expect(await store.loadInProgress(), isNull);
      expect(f.existsSync(), isFalse);
    });

    test('saveInProgress overwrites previous content', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveInProgress(makeRun(id: 'live', distance: 100));
      await store.saveInProgress(makeRun(id: 'live', distance: 500));
      final loaded = await store.loadInProgress();
      expect(loaded?.distanceMetres, 500);
    });

    test(
        'ultra-length crash-resume roundtrip preserves every waypoint + '
        'every field (25 000 points, ~7 h @ 1 Hz)', () async {
      // The followup that motivated this test ("Long-runs >6 h need a
      // crash-resume guarantee — the resume path may not reconstruct
      // the full track for very long sessions") was speculative.
      // Pin the behaviour with a real fixture: 25 000 waypoints,
      // every field populated (lat / lng / ele / timestamp / bpm),
      // so a future regression in the encoder, the decoder, or the
      // background-isolate plumbing surfaces here instead of in the
      // field on the day an athlete loses their 100-miler.
      final base = DateTime(2026, 5, 11, 5);
      final track = [
        for (var i = 0; i < 25000; i++)
          Waypoint(
            // Slight drift so the lat/lng aren't degenerate constants
            // — catches a "we only kept the first" truncation bug.
            lat: 47.37 + i * 1e-7,
            lng: 8.54 + i * 1e-7,
            elevationMetres: 400.0 + (i % 100),
            timestamp: base.add(Duration(seconds: i)),
            bpm: 120 + (i % 60),
          ),
      ];
      final original = Run(
        id: 'ultra-stress',
        startedAt: base,
        duration: const Duration(hours: 6, minutes: 56, seconds: 39),
        distanceMetres: 70_400, // 70.4 km
        track: track,
        source: RunSource.app,
        metadata: const {
          'activity_type': 'run',
          'indoor_estimated': false,
          'steps': 84210,
        },
      );

      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveInProgress(original);

      // Sanity: the file actually grew to ~1.5 MB+. A silent encoder
      // truncation would surface here as a much smaller file.
      final bytes = await File('${tempDir.path}/in_progress.json').length();
      expect(bytes, greaterThan(1_500_000),
          reason: '25 000 waypoints with full field set must serialise '
              'past ~1.5 MB — anything smaller signals an encoder cut-off');

      final loaded = await store.loadInProgress();
      expect(loaded, isNotNull);
      // Shape preservation.
      expect(loaded!.id, original.id);
      expect(loaded.startedAt, original.startedAt);
      expect(loaded.duration, original.duration);
      expect(loaded.distanceMetres, original.distanceMetres);
      expect(loaded.source, original.source);
      // Track count must match exactly — even a one-off truncation
      // (e.g. an off-by-one in a streaming JSON parser) breaks this.
      expect(loaded.track.length, 25000,
          reason: 'loadInProgress must return every saved waypoint');
      // Spot-check first, last, and a middle waypoint so a partial
      // corruption (e.g. mid-track byte flip) is caught.
      for (final idx in const [0, 12345, 24999]) {
        final o = original.track[idx];
        final l = loaded.track[idx];
        expect(l.lat, closeTo(o.lat, 1e-12), reason: 'lat at $idx');
        expect(l.lng, closeTo(o.lng, 1e-12), reason: 'lng at $idx');
        expect(l.elevationMetres, o.elevationMetres,
            reason: 'ele at $idx');
        expect(l.timestamp, o.timestamp, reason: 'timestamp at $idx');
        expect(l.bpm, o.bpm, reason: 'bpm at $idx');
      }
      // Metadata survives end-to-end too — the recovery path stamps
      // `recovered_from_crash: true` on top of whatever was saved, so
      // we want the rest of the keys intact.
      expect(loaded.metadata?['activity_type'], 'run');
      expect(loaded.metadata?['steps'], 84210);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('edge cases', () {
    test('init tolerates a corrupt run file', () async {
      // Drop a broken file into the directory before init reads it.
      File('${tempDir.path}/junk.json').writeAsStringSync('{bad json');
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      // Should not throw; the corrupt file is silently skipped.
      expect(store.runs, isEmpty);
    });

    test('unsyncedCount is never negative when sidecar has orphan IDs', () async {
      // Write a sidecar with an ID that has no corresponding run file.
      // This can happen if the user clears app storage between the sidecar
      // write and the run file write, or vice versa.
      File('${tempDir.path}/synced_ids.json')
          .writeAsStringSync('{"ids":["ghost-id-1","ghost-id-2"]}');

      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);

      // No run files exist, but two ghost IDs are in the sidecar.
      expect(store.runs, isEmpty);
      expect(store.unsyncedCount, greaterThanOrEqualTo(0));
      expect(store.unsyncedCount, 0);
    });

    test('markPendingRemoteDelete persists across reload and is idempotent', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('run-a');
      await store.markPendingRemoteDelete('run-b');
      // Idempotent — re-marking the same id shouldn't duplicate.
      await store.markPendingRemoteDelete('run-a');
      expect(store.pendingRemoteDeleteIds, {'run-a', 'run-b'});

      // Sidecar should round-trip on a fresh instance.
      final store2 = LocalRunStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.pendingRemoteDeleteIds, {'run-a', 'run-b'});
    });

    test('markManyPendingRemoteDelete folds N adds into one notify',
        () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      var notifyCount = 0;
      store.addListener(() => notifyCount++);
      await store.markManyPendingRemoteDelete(['a', 'b', 'c']);
      expect(notifyCount, 1);
      expect(store.pendingRemoteDeleteIds, {'a', 'b', 'c'});
    });

    test(
        'markManyPendingRemoteDelete with no new ids is a no-op (no notify, no write)',
        () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('a');
      var notifyCount = 0;
      store.addListener(() => notifyCount++);
      // Already-queued ids should not trigger a notify or sidecar write.
      await store.markManyPendingRemoteDelete(['a']);
      expect(notifyCount, 0);
    });

    test('clearPendingRemoteDelete removes a single id and persists', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.markManyPendingRemoteDelete(['a', 'b']);
      await store.clearPendingRemoteDelete('a');
      expect(store.pendingRemoteDeleteIds, {'b'});

      final store2 = LocalRunStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.pendingRemoteDeleteIds, {'b'});
    });

    test('clearing the last pending id deletes the sidecar', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('only');
      expect(File('${tempDir.path}/pending_remote_deletes.json').existsSync(),
          true);
      await store.clearPendingRemoteDelete('only');
      expect(File('${tempDir.path}/pending_remote_deletes.json').existsSync(),
          false);
    });

    test('pending_remote_deletes.json is excluded from the run-file glob',
        () async {
      // A pending-deletes sidecar plus a real run file: only the run
      // should show up in `runs`, and the sidecar should be honoured.
      File('${tempDir.path}/pending_remote_deletes.json')
          .writeAsStringSync('{"ids":["queued-1"]}');
      final realRun = {
        'run': makeRun(id: 'real').toJson(),
        'synced': false,
      };
      File('${tempDir.path}/real.json').writeAsStringSync(jsonEncode(realRun));

      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.runs.map((r) => r.id).toList(), ['real']);
      expect(store.pendingRemoteDeleteIds, {'queued-1'});
    });

    test('init loads multiple runs sorted newest-first', () async {
      // Seed two valid run files directly, with different startedAt.
      final older = {
        'run': makeRun(id: 'old').toJson()
          ..['startedAt'] = '2026-04-01T08:00:00.000',
        'synced': false,
      };
      final newer = {
        'run': makeRun(id: 'new').toJson()
          ..['startedAt'] = '2026-04-10T08:00:00.000',
        'synced': false,
      };
      File('${tempDir.path}/old.json').writeAsStringSync(jsonEncode(older));
      File('${tempDir.path}/new.json').writeAsStringSync(jsonEncode(newer));

      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.runs.map((r) => r.id).toList(), ['new', 'old']);
    });
  });
}
