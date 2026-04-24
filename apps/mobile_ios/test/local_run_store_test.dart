import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ios/local_run_store.dart';

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
