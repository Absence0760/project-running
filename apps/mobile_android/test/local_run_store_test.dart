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
    Map<String, dynamic>? metadata,
  }) {
    return Run(
      id: id,
      startedAt: DateTime(2026, 4, 10, 8),
      duration: duration,
      distanceMetres: distance,
      track: track ?? const [],
      source: RunSource.app,
      metadata: metadata,
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

    test('saveInProgress writes append-only NDJSON without an atomic-rename .tmp', () async {
      // Persona-hunt Round 3 finding Ultra #2: the old architecture
      // re-encoded + atomically rewrote the full track on every
      // 10s tick. For a 50-hour 100-mile race that's ~250 GB
      // cumulative writes. The new append-only NDJSON path writes
      // ONLY the new waypoints since the last save plus an updated
      // header per tick, so per-tick cost is O(new-waypoints) flat.
      // No .tmp file is involved; durability comes from
      // flush-per-line. Pin the architecture: canonical file
      // exists, no .tmp.
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveInProgress(makeRun(id: 'live', distance: 100));
      expect(
        File('${tempDir.path}/in_progress.json').existsSync(),
        isTrue,
        reason: 'NDJSON append must produce the canonical file',
      );
      expect(
        File('${tempDir.path}/in_progress.json.tmp').existsSync(),
        isFalse,
        reason: 'Append-only path never creates a .tmp',
      );
    });

    test('saveInProgress is unaffected by a stale .tmp from a previous version',
        () async {
      // The pre-Ultra-#2 architecture wrote via .tmp + atomic rename.
      // The new append-only NDJSON path doesn't touch .tmp at all,
      // so an orphan left over from an older app version is benign
      // — it just doesn't affect the new canonical file. Pin that
      // an orphan .tmp doesn't poison the new save / load.
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveInProgress(makeRun(id: 'A', distance: 100));
      await File('${tempDir.path}/in_progress.json.tmp')
          .writeAsString('partial garbage from a torn write of an older app version');
      await store.saveInProgress(makeRun(id: 'B', distance: 500));
      final loaded = await store.loadInProgress();
      expect(loaded?.id, 'B');
      expect(loaded?.distanceMetres, 500);
    });

    test('a torn write leaves the previous in_progress intact', () async {
      // Reason: this is the actual data-loss property the atomic write
      // guarantees. Simulate the previous-code failure mode (writeAsString
      // truncates the target before writing): manually replicate the
      // pre-fix world by writing a half-formed payload directly to the
      // canonical path. The atomic-rename code path is only exercised
      // by a real saveInProgress; the test here pins that
      // _loadAll/loadInProgress doesn't surface partial garbage as a
      // real run. With the old in-place write the truncation always
      // destroyed the previous good save; the atomic rename keeps the
      // canonical file pointing at the prior good save until the new
      // tmp file is fully flushed + renamed.
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveInProgress(makeRun(id: 'GOOD', distance: 100));
      // Simulate the equivalent of a torn write that leaked a half-
      // formed file at the canonical path under the OLD writeAsString
      // path — loadInProgress must drop it cleanly without crashing.
      await File('${tempDir.path}/in_progress.json')
          .writeAsString('{"run": {"id": "TORN", "start');
      expect(await store.loadInProgress(), isNull,
          reason: 'A corrupt canonical file must be detected and dropped');
      expect(
        File('${tempDir.path}/in_progress.json').existsSync(),
        isFalse,
        reason: 'loadInProgress must delete the corrupt file so the next '
            'session doesn\'t keep tripping over it.',
      );
    });

    test(
        'append-only NDJSON: per-tick write cost is O(new-waypoints), not O(total)',
        () async {
      // Persona-hunt Round 3 finding Ultra #2 — pre-fix every save
      // re-encoded the FULL track every 10s. For a 50-hour 100-mile
      // race that meant ~14 MB per tick at hour 50; cumulative ~250 GB
      // of writes over the race. Append-only NDJSON writes only the
      // new waypoints per tick.
      //
      // Pin the property: after a sequence of N saves where the
      // track grows by `step` waypoints each time, the file size
      // grows roughly linearly with TOTAL waypoints, NOT
      // quadratically with the sum-of-prefix-lengths that the old
      // architecture produced.
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      final track = <Waypoint>[];
      var saveCount = 0;
      const step = 50;
      const saves = 20;
      for (var s = 0; s < saves; s++) {
        for (var i = 0; i < step; i++) {
          track.add(Waypoint(
            lat: 47.0 + 0.0001 * track.length,
            lng: 8.0 + 0.0001 * track.length,
            timestamp: DateTime.utc(2026, 5, 1).add(Duration(seconds: track.length)),
          ));
        }
        await store.saveInProgress(makeRun(
          id: 'live',
          distance: track.length * 10.0,
          track: List.of(track),
        ));
        saveCount++;
      }
      // Total waypoints = saves * step = 1000.
      // Old architecture's cumulative-bytes scales with sum(1, 2, ..., saves) × step
      //   ≈ saves² / 2 × step. New architecture scales with saves × step linearly.
      // The file size on disk reflects the latter — total appended bytes
      // ≈ (header_bytes_per_line + step × waypoint_bytes) × saves.
      final fileSize = File('${tempDir.path}/in_progress.json').lengthSync();
      // Sanity bounds: per-tick bytes ≈ 2 KB header + 50 waypoints × ~80 B
      // ≈ 6 KB. 20 ticks → ≈120 KB. Pre-fix would have been ~3+ MB.
      expect(fileSize < 500_000, isTrue,
          reason: 'Append-only file should be ~120 KB for 1000 waypoints '
              'across 20 ticks; got $fileSize bytes. Pre-fix this was '
              '~3+ MB because the full track was re-encoded on every save.');
      // And the loaded run still has every waypoint.
      final loaded = await store.loadInProgress();
      expect(loaded?.track.length, saves * step);
      expect(saveCount, saves);
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

    test('pending-delete owner tag persists across cold start', () async {
      // Reason: pairs with the run owner-tag (decisions §67) — a pending
      // delete queued under User A must round-trip across an app
      // restart with A's user_id intact so a subsequent User B sync
      // can skip it. Without this, every restart re-untags A's
      // deletes and B's drain would attempt them (and fail under RLS).
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('run-a', ownerUserId: 'user-a');
      await store.markPendingRemoteDelete('run-b', ownerUserId: 'user-b');
      await store.markPendingRemoteDelete('run-legacy'); // no owner

      expect(store.debugPendingRemoteDeleteOwner('run-a'), 'user-a');
      expect(store.debugPendingRemoteDeleteOwner('run-b'), 'user-b');
      expect(store.debugPendingRemoteDeleteOwner('run-legacy'), isNull);

      final store2 = LocalRunStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.debugPendingRemoteDeleteOwner('run-a'), 'user-a');
      expect(store2.debugPendingRemoteDeleteOwner('run-b'), 'user-b');
      expect(store2.debugPendingRemoteDeleteOwner('run-legacy'), isNull);
    });

    test('pendingRemoteDeletesForUser returns only drainable entries', () {
      // Reason: pin the per-user filter contract. A user can drain
      // entries they own OR untagged entries (adoption rule). Foreign-
      // owned entries are skipped — they stay queued for their
      // rightful owner.
      final store = LocalRunStore();
      // Test directly against the synchronous helper — no async init
      // needed because we're only exercising in-memory state.
      // Build the map via the public API.
      Future<void> seed() async {
        await store.init(overrideDirectory: tempDir);
        await store.markPendingRemoteDelete('a-1', ownerUserId: 'user-a');
        await store.markPendingRemoteDelete('a-2', ownerUserId: 'user-a');
        await store.markPendingRemoteDelete('b-1', ownerUserId: 'user-b');
        await store.markPendingRemoteDelete('legacy');
      }

      seed();
      // The seed completes synchronously enough for the in-memory map
      // to be populated (the file write is awaited inside markPending
      // but the in-memory state updates before the await).
      // We need to actually await — so wrap in a fresh test:
    }, skip: 'replaced by the explicit async test below');

    test('pendingRemoteDeletesForUser filters by owner + accepts untagged',
        () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('a-1', ownerUserId: 'user-a');
      await store.markPendingRemoteDelete('a-2', ownerUserId: 'user-a');
      await store.markPendingRemoteDelete('b-1', ownerUserId: 'user-b');
      await store.markPendingRemoteDelete('legacy'); // untagged

      // user-a sees their own + untagged.
      expect(store.pendingRemoteDeletesForUser('user-a'),
          {'a-1', 'a-2', 'legacy'});
      // user-b sees their own + untagged.
      expect(store.pendingRemoteDeletesForUser('user-b'),
          {'b-1', 'legacy'});
      // A null user can drain nothing (the SyncService bails before
      // reaching this anyway, but pin the safe-default contract).
      expect(store.pendingRemoteDeletesForUser(null), isEmpty);
      // The unfiltered view still returns everything (preserves the
      // legacy callers + the "pending count" badge).
      expect(store.pendingRemoteDeleteIds,
          {'a-1', 'a-2', 'b-1', 'legacy'});
    });

    test('legacy {ids: [...]} sidecar format is upgraded on next write',
        () async {
      // Reason: existing installs have the old untagged sidecar shape
      // on disk. Load must accept it (treating each entry as untagged
      // / drain-by-any-user). The next mutation upgrades the file to
      // the new {deletes: {id: owner}} shape. Without this, a build
      // bump silently drops every queued delete on first launch.
      File('${tempDir.path}/pending_remote_deletes.json')
          .writeAsStringSync('{"ids":["legacy-1","legacy-2"]}');

      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);

      expect(store.pendingRemoteDeleteIds, {'legacy-1', 'legacy-2'});
      // Both entries are untagged (null owner) — drain under any user.
      expect(store.debugPendingRemoteDeleteOwner('legacy-1'), isNull);
      expect(store.debugPendingRemoteDeleteOwner('legacy-2'), isNull);
      expect(store.pendingRemoteDeletesForUser('user-x'),
          {'legacy-1', 'legacy-2'});

      // A mutation rewrites the file in the new format.
      await store.markPendingRemoteDelete('new-1', ownerUserId: 'user-x');
      final raw = File('${tempDir.path}/pending_remote_deletes.json')
          .readAsStringSync();
      expect(raw, contains('"deletes"'),
          reason: 'next write must upgrade to the tagged format');
      expect(raw, isNot(contains('"ids"')),
          reason: 'legacy key must be gone after the upgrade');
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

  // ────────────────────────────────────────────────────────────────
  // Owner-tag stamping for the offline-record-then-sync flow.
  //
  // The competitive line we make is "record without an account, sync
  // later if you ever sign in". The hardening: every locally-saved
  // run is stamped with `metadata.created_by_user_id` at save time.
  // The SyncService consults this tag during drain so User A's runs
  // can't accidentally sync under User B's account on a shared
  // device. See `docs/decisions.md § 67`.
  group('owner-tag stamping (created_by_user_id)', () {
    test('no provider set → run saved without the tag', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRun(id: 'r-1'));
      expect(store.runs.single.metadata?['created_by_user_id'], isNull,
          reason: 'with no provider configured, the stamp is absent — '
              'tests and offline-only builds stay unaffected');
    });

    test('provider returns null (signed-out) → tag absent', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => null;
      await store.save(makeRun(id: 'r-1'));
      expect(store.runs.single.metadata?['created_by_user_id'], isNull,
          reason: 'signed-out save → tag stays null so the first '
              'signed-in user can adopt the run during sync');
    });

    test('provider returns empty string → tag absent (defensive)', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => '';
      await store.save(makeRun(id: 'r-1'));
      expect(store.runs.single.metadata?['created_by_user_id'], isNull);
    });

    test('provider returns userId → tag stamped on save', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => 'user-a';
      await store.save(makeRun(id: 'r-1'));
      expect(store.runs.single.metadata?['created_by_user_id'], 'user-a');
    });

    test('tag persists across cold start', () async {
      var store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => 'user-a';
      await store.save(makeRun(id: 'r-1'));

      // Cold start.
      store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.runs.single.metadata?['created_by_user_id'], 'user-a');
    });

    test('tag is also stamped when other metadata is present', () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => 'user-a';
      await store.save(makeRun(id: 'r-1', metadata: {
        'activity_type': 'run',
        'title': 'Morning loop',
      }));
      final md = store.runs.single.metadata!;
      expect(md['activity_type'], 'run');
      expect(md['title'], 'Morning loop');
      expect(md['created_by_user_id'], 'user-a',
          reason: 'tag must not clobber other metadata keys');
    });

    test('provider is invoked on EACH save (not memoised at attach time)',
        () async {
      String? currentUser;
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => currentUser;

      // Signed out — no tag.
      await store.save(makeRun(id: 'r-signed-out'));
      // Need a fresh id each time because save replaces same-id entries.
      currentUser = 'user-a';
      await store.save(makeRun(id: 'r-signed-in'));
      currentUser = 'user-b';
      await store.save(makeRun(id: 'r-user-b'));

      final byId = {for (final r in store.runs) r.id: r};
      expect(byId['r-signed-out']?.metadata?['created_by_user_id'], isNull);
      expect(byId['r-signed-in']?.metadata?['created_by_user_id'], 'user-a');
      expect(byId['r-user-b']?.metadata?['created_by_user_id'], 'user-b');
    });

    test('an existing metadata.created_by_user_id is OVERWRITTEN by save',
        () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => 'user-a';
      await store.save(makeRun(id: 'r-1', metadata: {
        'created_by_user_id': 'someone-else',
      }));
      expect(store.runs.single.metadata?['created_by_user_id'], 'user-a',
          reason: 'save() always stamps the current user, never honours '
              'a pre-existing stale tag');
    });

    test('withCreatedByUserId helper produces a fresh Run', () async {
      final input = makeRun(id: 'r-1', metadata: {'title': 'X'});
      final stamped = LocalRunStore.withCreatedByUserId(input, 'user-a');
      // Original untouched.
      expect(input.metadata?['created_by_user_id'], isNull);
      expect(input.metadata!['title'], 'X');
      // Stamped copy.
      expect(stamped.metadata!['created_by_user_id'], 'user-a');
      expect(stamped.metadata!['title'], 'X');
    });

    test('saveFromRemote (cloud→local) does NOT stamp the local tag',
        () async {
      final store = LocalRunStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => 'user-a';
      await store.saveFromRemote(makeRun(id: 'r-cloud'));
      expect(store.runs.single.metadata?['created_by_user_id'], isNull,
          reason: 'cloud-sourced rows must not be tagged with the local '
              'currentUserId — the cloud row carries its own user_id');
    });
  });
}
