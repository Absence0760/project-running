// Guard-rail tests that pin the mobile app's efficiency + layering
// invariants in place. Each test parses a source file as text and asserts
// a pattern is (or isn't) present, with a **why** comment explaining the
// rule so a future editor can decide whether it's safe to break.
//
// When one of these fails, it means a recent change reversed an
// optimization or broke a layering rule we deliberately codified. Read
// the reason before blindly updating the test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Extract the body of a named method from Dart source by walking balanced
/// braces. Fragile — relies on the file being well-formatted — but good
/// enough for single-file invariants we control. The [signaturePattern]
/// must match up to and INCLUDING the opening `{` of the method body.
String _extractMethodBody(String source, String signaturePattern) {
  final match = RegExp(signaturePattern).firstMatch(source);
  if (match == null) {
    fail('Could not find "$signaturePattern" — rename? '
        'Update this guard to match the new name.');
  }
  // Regex consumed the opening `{`; start inside the body with depth 1.
  final start = match.end;
  int depth = 1;
  int i = start;
  while (depth > 0 && i < source.length) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') depth--;
    i++;
  }
  return source.substring(start, i - 1);
}

void main() {
  group('run_screen.dart', () {
    late String source;
    setUpAll(() {
      source = File('lib/screens/run_screen.dart').readAsStringSync();
    });

    test('_onSnapshot never calls setState', () {
      // Reason: the per-snapshot handler fires at >=1 Hz (GPS rate). A
      // setState at the top level of _RunScreenState rebuilds the whole
      // recording Stack — map, chips, banners, layout — at that cadence.
      // Stats updates flow through _statsNotifier instead; only the
      // ValueListenableBuilder subtrees rebuild. See
      // apps/mobile_android/CLAUDE.md § "Hot-path exception".
      final body = _extractMethodBody(
        source,
        r'void _onSnapshot\(RunSnapshot snapshot\)\s*\{',
      );
      expect(
        body.contains('setState('),
        isFalse,
        reason: '_onSnapshot must not call setState — '
            'update _statsNotifier.value instead.',
      );
    });

    test('_formattedElevation reads the accumulator field, not a loop', () {
      // Reason: was O(n) over the full track on every build. For a 60-min
      // run (~3600 waypoints) that's millions of iterator steps per
      // minute. Now maintained incrementally in _onSnapshot.
      final match = RegExp(
        r"String get _formattedElevation =>\s*'\$\{_elevationGainMetres\.round\(\)\}';",
      ).firstMatch(source);
      expect(
        match,
        isNotNull,
        reason: '_formattedElevation must read the incrementally-updated '
            '_elevationGainMetres field. Do not iterate _track here.',
      );
    });

    test('_LiveStats value class exists with the expected shape', () {
      // Reason: this is the immutable bundle carried by _statsNotifier.
      // If someone removes it or deletes a field, the ValueListenableBuilder
      // subtrees lose the data they need.
      expect(source, contains('class _LiveStats {'));
      for (final field in const [
        'Duration elapsed',
        'double distanceMetres',
        'double? pace',
        'List<cm.Waypoint> track',
        'cm.Waypoint? currentPosition',
        'double? offRouteDistance',
        'double? routeRemaining',
      ]) {
        expect(
          source,
          contains(field),
          reason: '_LiveStats is missing "$field" — the hot-path UI '
              'depends on this field. See run_screen.dart.',
        );
      }
    });

    test('recording tree wraps stats-driven subtrees in ValueListenableBuilder',
        () {
      // Reason: if the map / off-route banner / route-remaining badge /
      // stats panel stop subscribing to _statsNotifier, they'll freeze at
      // whatever values they held at the last setState.
      final buildRecording = _extractMethodBody(
        source,
        r'Widget _buildRecording\(BuildContext context\)\s*\{',
      );
      final matches = RegExp(r'ValueListenableBuilder<_LiveStats>')
          .allMatches(buildRecording);
      expect(
        matches.length,
        greaterThanOrEqualTo(4),
        reason: '_buildRecording expects at least 4 '
            'ValueListenableBuilder<_LiveStats> wrappers (map, '
            'route-remaining badge, off-route banner, stats panel).',
      );
    });

    test('_onPrefsChange skips rebuilds during recording', () {
      // Reason: runStore.notifyListeners() fires every 10s via
      // _saveInProgress. Without this gate, we'd get a full-screen
      // rebuild every 10s for no visible change.
      final body = _extractMethodBody(
        source,
        r'void _onPrefsChange\(\)\s*\{',
      );
      expect(
        body,
        contains('_ScreenState.recording'),
        reason: '_onPrefsChange must bail out while recording — see '
            'the runStore-notify rebuild storm fix.',
      );
    });
  });

  group('local_run_store.dart', () {
    late String source;
    setUpAll(() {
      source = File('lib/local_run_store.dart').readAsStringSync();
    });

    test('markSynced writes only the sidecar, not the run file', () {
      // Reason: used to read-decode-re-encode-write the full run file
      // just to flip a boolean. The synced_ids.json sidecar replaces it.
      final body = _extractMethodBody(
        source,
        r'Future<void> markSynced\(String runId\)\s*async\s*\{',
      );
      expect(
        body.contains('writeAsString(jsonEncode'),
        isFalse,
        reason: 'markSynced must not rewrite the run JSON. '
            'Use the sidecar (_persistSyncedIds).',
      );
      expect(
        body,
        contains('_syncedIds.add'),
        reason: 'markSynced should update the in-memory set.',
      );
      expect(
        body,
        contains('_persistSyncedIds'),
        reason: 'markSynced should flush the sidecar.',
      );
    });

    test('saveInProgress offloads to compute()', () {
      // Reason: jsonEncode of a 1500-point track on the UI thread causes
      // visible jank every 10s. Must run on an isolate.
      final body = _extractMethodBody(
        source,
        r'Future<void> saveInProgress\(Run run\)\s*async\s*\{',
      );
      expect(
        body,
        contains('compute('),
        reason: 'saveInProgress must offload jsonEncode + write to '
            'an isolate.',
      );
    });

    test('_loadAll reads run files in parallel', () {
      // Reason: serial reads made cold-start scale linearly with run
      // count (a user with 500 runs waited seconds on the first frame).
      final body = _extractMethodBody(
        source,
        r'Future<void> _loadAll\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('Future.wait'),
        reason: '_loadAll should batch file reads with Future.wait, '
            'not loop-await each one.',
      );
    });

    test('save() stamps metadata.last_modified_at', () {
      // Reason: sync uses `metadata.last_modified_at` for newer-wins
      // conflict resolution (see saveFromRemote). A local save that
      // doesn't stamp can be silently clobbered by the next remote pull
      // if the remote carries a later timestamp from a different device.
      final body = _extractMethodBody(
        source,
        r'Future<void> save\(Run run\)\s*async\s*\{',
      );
      expect(
        body,
        contains('_withLastModified('),
        reason: 'save() must route the incoming run through '
            '_withLastModified so metadata.last_modified_at is set. '
            'Without this, conflict resolution degrades to '
            'created_at / started_at — incorrect after any local edit.',
      );
    });

    test('update() stamps metadata.last_modified_at', () {
      // Reason: same as save(). Edit-dialog changes (title, notes) flow
      // through update(). If this stops stamping, web/watch edits to the
      // same run can race and the older write silently wins.
      final body = _extractMethodBody(
        source,
        r'Future<void> update\(Run updated\)\s*async\s*\{',
      );
      expect(
        body,
        contains('_withLastModified('),
        reason: 'update() must call _withLastModified on the incoming '
            'run. Newer-wins sync depends on this stamp — see '
            'saveFromRemote for the counterparty.',
      );
    });

    test('saveFromRemote() compares timestamps and preserves remote', () {
      // Reason: this is the counterparty to save/update. The remote copy
      // carries its own `last_modified_at`; overwriting it here would
      // collapse the whole newer-wins mechanism into "last writer wins".
      // The regex looks for the timestamp comparison that gates the
      // preserve-local branch.
      final body = _extractMethodBody(
        source,
        r'Future<void> saveFromRemote\(Run run\)\s*async\s*\{',
      );
      expect(
        body,
        contains('_lastModifiedOf('),
        reason: 'saveFromRemote() must call _lastModifiedOf() on both '
            'the local and remote copies to decide which to keep. If '
            'someone drops this comparison, the cloud will clobber '
            'local-only edits on every sync.',
      );
      expect(
        body.contains('_withLastModified('),
        isFalse,
        reason: 'saveFromRemote() must NOT stamp — it preserves the '
            "remote's timestamp. Stamping here would make the local "
            "copy look newer than the write that produced it, "
            'breaking newer-wins on the NEXT sync.',
      );
    });
  });

  group('sync paths use saveRunsBatch', () {
    test('SyncService._trySync uses the batch API', () {
      // Reason: was N round-trips + N markSynced file rewrites per sync.
      // saveRunsBatch does 8-parallel uploads + 100-row upserts.
      final source = File('lib/sync_service.dart').readAsStringSync();
      expect(
        source,
        contains('saveRunsBatch'),
        reason: 'SyncService should batch-push — see ApiClient.saveRunsBatch.',
      );
      expect(
        RegExp(r'for\s*\(final\s+\w+\s+in\s+unsynced\)').hasMatch(source),
        isFalse,
        reason: 'No per-run saveRun loop. Use saveRunsBatch + markManySynced.',
      );
    });

    test('background_sync uses the batch API', () {
      final source = File('lib/background_sync.dart').readAsStringSync();
      expect(
        source,
        contains('saveRunsBatch'),
        reason: 'Background sync should batch-push — parity with SyncService.',
      );
    });

    test('import_screen uses markManySynced', () {
      // Reason: bulk import of Strava/GPX — each import can produce
      // dozens of runs. N sidecar writes > 1 sidecar write.
      final source = File('lib/screens/import_screen.dart').readAsStringSync();
      expect(
        source,
        contains('markManySynced'),
        reason: 'Bulk importers should flush the sidecar once, '
            'not per run.',
      );
    });
  });

  group('run_recorder coupling', () {
    test('ActivityType.strideMetres exists for the pedometer fallback', () {
      // Reason: indoor runs display steps × stride instead of 0 km.
      // Removing the getter would quietly zero indoor distances.
      final source = File('lib/preferences.dart').readAsStringSync();
      expect(
        source,
        contains('double get strideMetres'),
        reason: 'ActivityType.strideMetres feeds the indoor pedometer '
            'distance fallback. Do not remove without also dropping '
            '_displayDistanceMetres in run_screen.dart.',
      );
    });
  });

  group('local_route_store.dart', () {
    test('_loadAll reads route files in parallel', () {
      // Reason: same cold-start concern as runs — a user with 50 saved
      // routes should see them load in one batch, not 50 serial reads.
      final source = File('lib/local_route_store.dart').readAsStringSync();
      final body = _extractMethodBody(
        source,
        r'Future<void> _loadAll\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('Future.wait'),
        reason: 'routeStore._loadAll must use Future.wait — mirrors '
            'the same optimization applied to runStore.',
      );
    });
  });

  group('main.dart launch path', () {
    test('local inits run in parallel', () {
      // Reason: dotenv, TileCache, runStore, routeStore, prefs, Supabase
      // init are all independent. Sequential awaits add up to hundreds
      // of ms of scheduler overhead before the first frame. Future.wait
      // multiplexes them.
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains('Future.wait'),
        reason: 'main() must use Future.wait for the local-init batch.',
      );
      expect(
        source,
        contains('TileCache.init()'),
        reason: 'TileCache.init must be part of the parallel batch.',
      );
      expect(
        source,
        contains('store.init()'),
        reason: 'runStore.init must be part of the parallel batch.',
      );
      expect(
        source,
        contains('routeStore.init()'),
        reason: 'routeStore.init must be part of the parallel batch.',
      );
      expect(
        source,
        contains('prefs.init()'),
        reason: 'prefs.init must be part of the parallel batch.',
      );
    });

    test('network-gated work is deferred to post-first-frame', () {
      // Reason: settingsSync.onSignedIn() + dev auto-sign-in + WearAuthBridge
      // attach + registerBackgroundSync are all invisible to the first
      // frame. Awaiting them before runApp holds the splash screen open
      // on slow connections. Must schedule via addPostFrameCallback or
      // an unawaited Future.
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains('addPostFrameCallback'),
        reason: 'main() must defer the network-gated init block via '
            'addPostFrameCallback.',
      );
      // settingsSync.onSignedIn() should appear AFTER the
      // addPostFrameCallback call site (i.e. inside the deferred block),
      // not before it in the main() body.
      final mainBody = _extractMethodBody(
        source,
        r'void main\(\)\s*async\s*\{',
      );
      final postFrameIdx = mainBody.indexOf('addPostFrameCallback');
      final settingsSyncIdx = mainBody.indexOf('settingsSync?.onSignedIn()');
      if (settingsSyncIdx != -1) {
        expect(
          settingsSyncIdx > postFrameIdx,
          isTrue,
          reason: 'settingsSync.onSignedIn() must run inside the '
              'addPostFrameCallback block — not on the critical path.',
        );
      }
    });
  });

  group('main.dart error boundary', () {
    test('release-mode ErrorWidget.builder override is present', () {
      // Reason: a subtree crash (most likely in flutter_map on a bad
      // tile response) would otherwise take down the entire run screen
      // with the red-screen ErrorWidget.
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains('ErrorWidget.builder'),
        reason: 'main.dart must install an ErrorWidget.builder in '
            'release builds so a widget crash replaces only the '
            'offending subtree, not the whole screen.',
      );
      expect(
        source,
        contains('kReleaseMode'),
        reason: 'The override must be gated on kReleaseMode — keep the '
            'default red screen in debug so developers see crashes.',
      );
    });
  });

  group('lock-screen notification bridge', () {
    test('RunNotificationBridge pins geolocator channel constants', () {
      // Reason: the bridge replaces geolocator's foreground-service
      // notification by posting with the SAME channel id + notification
      // id. If a future geolocator release changes these, the
      // replacement silently becomes a second row.
      final source = File(
        'android/app/src/main/kotlin/com/betterrunner/app/RunNotificationBridge.kt',
      ).readAsStringSync();
      expect(
        source,
        contains('"geolocator_channel_01"'),
        reason: 'GEOLOCATOR_CHANNEL_ID must match '
            'com.baseflow.geolocator.GeolocatorLocationService.CHANNEL_ID. '
            'Check the geolocator_android changelog on bumps.',
      );
      expect(
        source,
        contains('75415'),
        reason: 'GEOLOCATOR_NOTIFICATION_ID must match '
            'GeolocatorLocationService.ONGOING_NOTIFICATION_ID.',
      );
    });
  });
}
