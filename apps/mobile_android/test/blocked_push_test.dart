import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_run_store.dart';

/// Parking a permanently-refused push. decisions § 1009 measured the first
/// terminal upload failure; § 1070 is what the drain and the runner do about it.
///
/// The claim under test is narrow and load-bearing: a parked run leaves the
/// drainable set — so nothing re-sends bytes the bucket has already refused,
/// and nothing holds its track resident to do it — while staying reachable,
/// nameable, and resolvable by the one action the runner is offered.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('blocked_push_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Run makeRun(String id, {DateTime? startedAt, List<Waypoint>? track}) => Run(
        id: id,
        startedAt: startedAt ?? DateTime(2026, 4, 10, 8),
        duration: const Duration(minutes: 25),
        distanceMetres: 5000,
        track: track ?? const [],
        source: RunSource.app,
      );

  Waypoint wp(int i) => Waypoint(
        lat: 38.5 + i * 0.0001,
        lng: -109.5 + i * 0.0001,
        timestamp: DateTime(2026, 4, 10, 8).add(Duration(seconds: i)),
      );

  Future<LocalRunStore> openStore() async {
    final store = LocalRunStore();
    await store.init(overrideDirectory: tempDir);
    return store;
  }

  group('parking leaves the drainable set', () {
    test('a blocked run is absent from unsyncedRuns and named separately',
        () async {
      final store = await openStore();
      await store.save(makeRun('r-big'));
      await store.save(makeRun('r-ok'));

      await store.markBlocked(
          {'r-big': RunPushBlockReason.trackTooLarge});

      expect(store.unsyncedRuns.map((r) => r.id), ['r-ok'],
          reason: 'the drain must not be handed a run it cannot send');
      expect(store.unsyncedCount, 1);
      expect(store.blockedCount, 1);
      expect(store.blockedReason('r-big'), RunPushBlockReason.trackTooLarge);
      expect(store.blockedReason('r-ok'), isNull);
    });

    test('the park survives a cold reload', () async {
      final store = await openStore();
      await store.save(makeRun('r-big'));
      await store.markBlocked(
          {'r-big': RunPushBlockReason.trackTooLarge});

      final reloaded = await openStore();

      expect(reloaded.blockedReason('r-big'), RunPushBlockReason.trackTooLarge);
      expect(reloaded.unsyncedRuns, isEmpty,
          reason: 'a park that only lives in memory is one relaunch from '
              'resuming the retry it exists to stop');
    });

    test('a parked run outside the window is not hydrated on cold load',
        () async {
      // The residency invariant is "the newest window ∪ everything drainable",
      // and a parked run is not drainable — so the million-point track § 1009
      // measured stops being held for a drain that will never run.
      final store = await openStore();
      await store.save(makeRun('r-old',
          startedAt: DateTime(2026, 1, 1), track: [wp(0), wp(1), wp(2)]));
      await store.save(makeRun('r-new', startedAt: DateTime(2026, 6, 1)));
      await store.markSynced('r-new');
      await store.markBlocked({'r-old': RunPushBlockReason.trackTooLarge});

      final reloaded = LocalRunStore()..residentWindow = 1;
      await reloaded.init(overrideDirectory: tempDir);

      expect(reloaded.runs.map((r) => r.id), ['r-new']);
      expect(reloaded.summaryRuns.map((r) => r.id), containsAll(['r-old']),
          reason: 'evicted from residency, still in the history');
      expect((await reloaded.runById('r-old'))!.track, hasLength(3),
          reason: 'and still hydratable on demand, so the runner can act');
    });
  });

  group('the park is about the bytes, so any edit clears it', () {
    test('update() un-parks the run', () async {
      final store = await openStore();
      await store.save(makeRun('r-big'));
      await store.markBlocked({'r-big': RunPushBlockReason.trackTooLarge});

      await store.update(makeRun('r-big', track: [wp(0)]));

      expect(store.blockedReason('r-big'), isNull);
      expect(store.unsyncedRuns.map((r) => r.id), ['r-big']);
      expect((await openStore()).blockedRuns, isEmpty,
          reason: 'the un-park has to be durable for the same reason the '
              'un-sync does — otherwise the next launch re-parks it');
    });

    test('save() of the same id un-parks the run', () async {
      final store = await openStore();
      await store.save(makeRun('r-big'));
      await store.markBlocked({'r-big': RunPushBlockReason.trackTooLarge});

      await store.save(makeRun('r-big', track: [wp(0)]));

      expect(store.blockedReason('r-big'), isNull);
      expect(store.unsyncedRuns.map((r) => r.id), ['r-big']);
    });

    test('delete() drops the entry rather than leaving a ghost', () async {
      final store = await openStore();
      await store.save(makeRun('r-big'));
      await store.markBlocked({'r-big': RunPushBlockReason.trackTooLarge});

      await store.delete('r-big');

      expect(store.blockedRuns, isEmpty);
      expect(File('${tempDir.path}/blocked_runs.json').existsSync(), isFalse);
    });
  });

  group('dropTrack — the action the runner is offered', () {
    test('empties the track, un-parks, and leaves the run drainable', () async {
      final store = await openStore();
      await store.save(makeRun('r-big', track: [wp(0), wp(1), wp(2)]));
      await store.markBlocked({'r-big': RunPushBlockReason.trackTooLarge});

      final stripped = await store.dropTrack('r-big');

      expect(stripped!.track, isEmpty);
      expect(stripped.distanceMetres, 5000,
          reason: 'the numbers are columns; only the trace could not be held');
      expect(store.blockedRuns, isEmpty);
      expect(store.unsyncedRuns.map((r) => r.id), ['r-big'],
          reason: 'the whole point is that it can now sync');
      expect((await store.runById('r-big'))!.track, isEmpty);
    });

    test('works on a run evicted from residency', () async {
      final store = LocalRunStore()..residentWindow = 1;
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun('r-old',
          startedAt: DateTime(2026, 1, 1), track: [wp(0), wp(1)]));
      await store.save(makeRun('r-new', startedAt: DateTime(2026, 6, 1)));
      await store.markSynced('r-new');
      await store.markBlocked({'r-old': RunPushBlockReason.trackTooLarge});

      final reloaded = LocalRunStore()..residentWindow = 1;
      await reloaded.init(overrideDirectory: tempDir);
      expect(reloaded.runs.map((r) => r.id), ['r-new'],
          reason: 'precondition: the parked run is not resident');

      final stripped = await reloaded.dropTrack('r-old');

      expect(stripped!.track, isEmpty);
      expect(reloaded.unsyncedRuns.map((r) => r.id), ['r-old'],
          reason: 'update() restores residency for a now-drainable run');
    });

    test('returns null for an id this device does not hold', () async {
      final store = await openStore();
      expect(await store.dropTrack('nope'), isNull);
    });
  });

  group('sidecar', () {
    test('a reason this build cannot name is dropped, not parked blindly',
        () async {
      // Parking under a reason no surface can explain strands the run with no
      // exit. Dropping it lets this build's own uploader re-derive its verdict.
      final store = await openStore();
      await store.save(makeRun('r-x'));
      await File('${tempDir.path}/blocked_runs.json').writeAsString(jsonEncode({
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'blocked': {'r-x': 'someFutureReason'},
      }));

      final reloaded = await openStore();

      expect(reloaded.blockedRuns, isEmpty);
      expect(reloaded.unsyncedRuns.map((r) => r.id), ['r-x']);
    });

    test('a malformed sidecar does not take the store down with it', () async {
      final store = await openStore();
      await store.save(makeRun('r-x'));
      await File('${tempDir.path}/blocked_runs.json')
          .writeAsString('{not json');

      final reloaded = await openStore();

      expect(reloaded.blockedRuns, isEmpty);
      expect(reloaded.summaryRuns.map((r) => r.id), ['r-x']);
    });

    test("a write merges the other process's parks rather than replacing them",
        () async {
      // background_sync.dart builds its own store over this directory in the
      // WorkManager isolate and is one of the five push sites, so a whole-file
      // write from either snapshot would hand the drain back a run it cannot
      // send.
      final a = await openStore();
      await a.save(makeRun('r-a'));
      await a.save(makeRun('r-b'));
      final b = await openStore();

      await a.markBlocked({'r-a': RunPushBlockReason.trackTooLarge});
      await b.markBlocked({'r-b': RunPushBlockReason.trackTooLarge});

      final reloaded = await openStore();
      expect(reloaded.blockedRuns.keys.toSet(), {'r-a', 'r-b'});
    });

    test('the blocked sidecar is not read back as a run file', () async {
      final store = await openStore();
      await store.save(makeRun('r-x'));
      await store.markBlocked({'r-x': RunPushBlockReason.trackTooLarge});

      final reloaded = await openStore();

      expect(reloaded.summaryRuns.map((r) => r.id), ['r-x']);
    });
  });
}
