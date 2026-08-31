// On-disk tests for the WatchIngestQueue shared-device owner-tag
// behaviour. The pure decoder is covered in watch_ingest_queue_test.dart;
// this file pins the queue's I/O + owner-tag contract.
//
// The headline guarantee: a payload that arrived during User A's
// signed-out window must NOT drain to User B when B signs in on the
// same device. Without the stamp, the queue file (a bare JSON payload
// keyed by uuid) gets fed to api.saveRun under B's session and RLS
// silently accepts the row — A's run lands under B's account on a
// shared device. Same shared-device contamination pattern as the
// per-user pending-delete queue.

import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../lib/watch_ingest_queue.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this._docsPath);
  final String _docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

/// Uploads always fail — the transient half of the drain's failure
/// classification.
class _FailingUploadApi extends _FakeApiClient {
  @override
  Future<void> saveRun(Run run, {bool? isPublic}) async {
    throw StateError('network down');
  }
}

class _FakeApiClient extends ApiClient {
  String? fakeUserId;
  final List<Run> saved = [];

  @override
  String? get userId => fakeUserId;

  @override
  Future<void> saveRun(Run run, {bool? isPublic}) async {
    saved.add(run);
  }
}

Map<String, dynamic> _payload({String id = 'watch-1'}) => {
      'id': id,
      'started_at': '2026-04-10T08:00:00.000Z',
      'duration_s': 1500,
      'distance_m': 5000.0,
      'source': 'watch',
      'track': const <dynamic>[],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WatchIngestQueue queue;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('watch_ingest_owner_');
    // Point path_provider at the temp dir so init() lands the queue
    // under <tempDir>/watch_ingest_queue/.
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    queue = WatchIngestQueue();
    await queue.init();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ── Overlapping owner stamps (§ 828) ────────────────────────────────
  group('setLastKnownOwner — overlapping calls', () {
    File ownerFile() => File('${tempDir.path}/watch_ingest_queue/last_owner.txt');

    test('a clear fired against an in-flight stamp is not undone', () async {
      // Both call sites in main.dart fire this unawaited, so a sign-out
      // landing on a sign-in put a delete and an atomic write over one file in
      // flight together: the delete found no target yet, the write's rename
      // put the stamp back, and the next cold start hydrated an owner the
      // store had been told to forget.
      await queue.setLastKnownOwner('user-a');

      final stamp = queue.setLastKnownOwner('user-b');
      final clear = queue.setLastKnownOwner(null);
      await Future.wait([stamp, clear]);

      expect(queue.debugLastKnownOwner, isNull);
      expect(ownerFile().existsSync(), isFalse,
          reason: 'a cold start must not hydrate a stamp the store was told '
              'to clear — an adopted watch run lands in the wrong account');
    });

    test('the last stamp wins on disk as well as in memory', () async {
      final a = queue.setLastKnownOwner('user-a');
      final b = queue.setLastKnownOwner('user-b');
      await Future.wait([a, b]);

      expect(queue.debugLastKnownOwner, 'user-b');
      expect(ownerFile().readAsStringSync(), 'user-b');
    });
  });

  // ── Headline guarantee ──────────────────────────────────────────────
  group('drain — shared-device owner filter', () {
    test('payload enqueued under user-a does NOT drain under user-b',
        () async {
      // Simulate user-a being signed in at some point in the past,
      // then signing out, then a watch payload arriving during the
      // signed-out window.
      await queue.setLastKnownOwner('user-a');
      await queue.enqueue(_payload(id: 'a-run-1'));
      expect(queue.pendingCount, 1);

      // user-b signs in. main.dart calls setLastKnownOwner before
      // drain — that update is what makes the stamp test discriminate.
      await queue.setLastKnownOwner('user-b');

      final api = _FakeApiClient()..fakeUserId = 'user-b';
      await queue.drain(api);

      expect(api.saved, isEmpty,
          reason: 'user-b drain must NOT push user-a\'s queued payload — '
              'RLS would accept the row under b\'s id and a\'s watch '
              'run would silently land under the wrong account.');
      expect(queue.pendingCount, 1,
          reason: 'foreign-owned payload stays on disk for its '
              'rightful owner to drain when they sign back in');
    });

    test('user-a drain consumes user-a\'s queued payload', () async {
      await queue.setLastKnownOwner('user-a');
      await queue.enqueue(_payload(id: 'a-run-1'));

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      await queue.drain(api);

      expect(api.saved.length, 1);
      expect(api.saved.single.id, 'a-run-1');
      expect(queue.pendingCount, 0,
          reason: 'drained file must be deleted on success');
    });

    test('mixed queue (a + b) drains only a\'s under a\'s session', () async {
      await queue.setLastKnownOwner('user-a');
      await queue.enqueue(_payload(id: 'a-run-1'));
      await queue.enqueue(_payload(id: 'a-run-2'));
      await queue.setLastKnownOwner('user-b');
      await queue.enqueue(_payload(id: 'b-run-1'));

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      await queue.drain(api);

      expect(api.saved.map((r) => r.id).toSet(), {'a-run-1', 'a-run-2'});
      expect(queue.pendingCount, 1,
          reason: 'b-run-1 stays on disk for user-b');
    });

    test('drain with no current user is a no-op', () async {
      await queue.setLastKnownOwner('user-a');
      await queue.enqueue(_payload(id: 'a-run-1'));

      final api = _FakeApiClient()..fakeUserId = null;
      await queue.drain(api);

      expect(api.saved, isEmpty);
      expect(queue.pendingCount, 1,
          reason: 'no-user drain must not touch the queue');
    });
  });

  // ── Owner-stamp lifecycle ───────────────────────────────────────────
  group('setLastKnownOwner', () {
    test('persists across init (process restart)', () async {
      await queue.setLastKnownOwner('user-a');

      // Simulate a fresh app launch — same tempDir, fresh queue
      // instance. init() must rehydrate the cache from the sidecar.
      final queue2 = WatchIngestQueue();
      await queue2.init();
      expect(queue2.debugLastKnownOwner, 'user-a',
          reason: 'last-owner sidecar must persist across init() so a '
              'process kill between sign-out and sign-in doesn\'t '
              'forget the stamp');

      // And a subsequent enqueue carries the rehydrated stamp.
      await queue2.enqueue(_payload(id: 'after-restart'));
      final api = _FakeApiClient()..fakeUserId = 'user-b';
      await queue2.drain(api);
      expect(api.saved, isEmpty,
          reason: 'rehydrated stamp must still skip foreign-user drain');
    });

    test('null clears the sidecar', () async {
      await queue.setLastKnownOwner('user-a');
      await queue.setLastKnownOwner(null);

      final queue2 = WatchIngestQueue();
      await queue2.init();
      expect(queue2.debugLastKnownOwner, isNull);
    });
  });

  // ── Legacy + backwards compat ───────────────────────────────────────
  group('legacy unwrapped payloads', () {
    test('files written before the envelope shipped drain as untagged',
        () async {
      // Drop a bare-payload file (the pre-envelope format) into the
      // queue dir directly, simulating an old file from before the
      // owner-tag landed. init() must accept it and drain must treat
      // it as untagged (adoption rule).
      final docPath = '${tempDir.path}/watch_ingest_queue';
      File('$docPath/legacy-1.json')
          .writeAsStringSync(jsonEncode(_payload(id: 'legacy-1')));

      final api = _FakeApiClient()..fakeUserId = 'user-fresh';
      await queue.drain(api);

      expect(api.saved.single.id, 'legacy-1',
          reason: 'a pre-envelope bare-payload file is untagged → '
              'drains under whichever user signs in next, matching '
              'the legacy adoption rule');
    });
  });

  // ── pendingCount excludes sidecar ───────────────────────────────────
  group('pendingCount', () {
    test('does not count last_owner.txt', () async {
      await queue.setLastKnownOwner('user-a');
      // No enqueues — count should be 0 even though the sidecar exists.
      expect(queue.pendingCount, 0);
    });
  });

  // ── Durability: atomic write + parse-vs-upload failure classes ──────
  group('durability', () {
    test('enqueue writes atomically, leaving no partial file behind',
        () async {
      await queue.setLastKnownOwner('user-a');
      await queue.enqueue(_payload(id: 'a-run-1'));

      final names = Directory('${tempDir.path}/watch_ingest_queue')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
      expect(names.where((n) => n.endsWith('.json')), hasLength(1));
    });

    test('an unparseable entry is quarantined, not retried forever', () async {
      // A process death mid-write used to leave a truncated file that drain
      // hit, logged, and left in place — so it was re-read on every sign-in
      // and pendingCount reported a phantom queued run indefinitely.
      final docPath = '${tempDir.path}/watch_ingest_queue';
      File('$docPath/truncated.json').writeAsStringSync('{"payload": {"id"');

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      await queue.drain(api);

      expect(api.saved, isEmpty);
      expect(queue.pendingCount, 0,
          reason: 'a payload nothing can parse is not a pending run');
      expect(queue.rejectedCount, 1);

      // A second sign-in must not re-read it.
      await queue.drain(api);
      expect(queue.rejectedCount, 1);
    });

    test('a payload with no id is quarantined, never uploaded', () async {
      // L4: `raw['id'] as String? ?? ''` made a missing id decode "cleanly",
      // so the failure surfaced on the upload side — where every error is
      // classified transient. Postgres rejects '' as a uuid on every attempt,
      // so the entry retried on every sign-in for the life of the install.
      final docPath = '${tempDir.path}/watch_ingest_queue';
      File('$docPath/no-id.json').writeAsStringSync(jsonEncode({
        'payload': {
          'started_at': '2026-04-10T08:00:00.000Z',
          'duration_s': 1500,
          'distance_m': 5000.0,
        }
      }));

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      await queue.drain(api);

      expect(api.saved, isEmpty,
          reason: 'an id-less run must never reach saveRun');
      expect(queue.pendingCount, 0);
      expect(queue.rejectedCount, 1);
    });

    test('the last-owner stamp is written atomically', () async {
      // L2: a bare writeAsString truncates to zero bytes first, and init()
      // reads an empty file as "no owner" — so a kill mid-write drops the
      // stamp and the next account adopts the previous user's watch run.
      await queue.setLastKnownOwner('user-a');
      final names = Directory('${tempDir.path}/watch_ingest_queue')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(names, contains('last_owner.txt'));
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty,
          reason: 'the atomic write renames its temp sibling away');

      final reloaded = WatchIngestQueue();
      await reloaded.init();
      expect(reloaded.debugLastKnownOwner, 'user-a');
    });

    test('a stale atomic-write orphan is swept at init', () async {
      final docPath = '${tempDir.path}/watch_ingest_queue';
      final stale = File('$docPath/abc.json.0.tmp')..writeAsStringSync('{}');
      stale.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 3)));

      final reloaded = WatchIngestQueue();
      await reloaded.init();

      expect(stale.existsSync(), isFalse);
      expect(reloaded.pendingCount, 0);
    });

    test('a structurally valid but incomplete payload is quarantined too',
        () async {
      // runFromWatchPayload casts started_at / duration_s / distance_m
      // unguarded, so a payload missing one throws exactly like a decode
      // failure — and is just as permanent.
      final docPath = '${tempDir.path}/watch_ingest_queue';
      File('$docPath/incomplete.json').writeAsStringSync(
          jsonEncode({'payload': {'id': 'x', 'distance_m': 100}}));

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      await queue.drain(api);

      expect(queue.pendingCount, 0);
      expect(queue.rejectedCount, 1);
    });

    test('an upload failure keeps retrying — it is not quarantined', () async {
      // The other half of the classification: a transient network failure
      // must leave the entry queued.
      await queue.setLastKnownOwner('user-a');
      await queue.enqueue(_payload(id: 'a-run-1'));

      final api = _FailingUploadApi()..fakeUserId = 'user-a';
      await queue.drain(api);

      expect(queue.pendingCount, 1);
      expect(queue.rejectedCount, 0);

      final ok = _FakeApiClient()..fakeUserId = 'user-a';
      await queue.drain(ok);
      expect(ok.saved.single.id, 'a-run-1');
      expect(queue.pendingCount, 0);
    });

    test('a rejected entry is swept once it passes the retention window',
        () async {
      final docPath = '${tempDir.path}/watch_ingest_queue';
      final old = File('$docPath/stale.json.rejected')
        ..writeAsStringSync('{')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 31)));
      final recent = File('$docPath/recent.json.rejected')
        ..writeAsStringSync('{');

      final fresh = WatchIngestQueue();
      await fresh.init();

      expect(old.existsSync(), isFalse,
          reason: 'a payload nothing can read is residue, and it carries GPS');
      expect(recent.existsSync(), isTrue);
    });
  });
}
