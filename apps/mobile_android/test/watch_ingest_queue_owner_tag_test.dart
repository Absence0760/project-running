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
}
