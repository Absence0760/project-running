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

    test('_onSnapshot updates L0/L1 stats before any L4 effect', () {
      // Reason: the layering rule (docs/conventions.md § Layered
      // resilience, docs/run_recording.md § Layering) says L0 (clock)
      // and L1 (GPS distance / pace) must not be broken by any L4
      // failure. Concretely: the mirror-field write + _statsNotifier
      // publish must complete before the first L4 try-block runs.
      // If a future edit hoists an effect (workout runner, race ping,
      // pace alert, lock-screen update, etc.) above the publish, an
      // unhandled throw inside it freezes the visible counters.
      final body = _extractMethodBody(
        source,
        r'void _onSnapshot\(RunSnapshot snapshot\)\s*\{',
      );
      final notifierIdx = body.indexOf('_statsNotifier.value = _LiveStats(');
      final firstTryIdx = body.indexOf('try {');
      expect(
        notifierIdx,
        greaterThan(-1),
        reason: '_onSnapshot must publish to _statsNotifier — '
            'this is what drives the visible stats.',
      );
      expect(
        firstTryIdx,
        greaterThan(notifierIdx),
        reason: '_onSnapshot has a try-block before the _statsNotifier '
            'publish. Move the L0/L1 update (mirror fields + '
            '_statsNotifier.value = ...) above every L4 effect, so a '
            'thrown auxiliary cannot freeze the clock and distance.',
      );
    });

    test('_onSnapshot wraps every L4 effect in its own try/catch', () {
      // Reason: layering rule again. A single shared outer try would
      // mean the first L4 throw skips every later effect (race ping
      // dies → off-route cue, pace alert, split snackbar, lock-screen
      // refresh all silently stop). Each effect gets its own try so
      // failures are isolated.
      final body = _extractMethodBody(
        source,
        r'void _onSnapshot\(RunSnapshot snapshot\)\s*\{',
      );
      final tryCount = RegExp(r'\btry\s*\{').allMatches(body).length;
      final catchCount = RegExp(r'\}\s*catch\s*\(').allMatches(body).length;
      expect(
        tryCount,
        equals(catchCount),
        reason: 'Every try in _onSnapshot must have a matching catch. '
            'A bare try with no catch lets a throw escape and kill the '
            'snapshot pipeline.',
      );
      // We expect at least one try per L4 effect: workout runner,
      // race ping, live broadcaster, off-route cue, pace alert, split
      // snackbar, lock-screen refresh = 7. If this drops, someone
      // collapsed effects under a shared catch — re-split them.
      expect(
        tryCount,
        greaterThanOrEqualTo(7),
        reason: '_onSnapshot is expected to host >=7 individually '
            'wrapped L4 effects. A drop usually means effects were '
            'collapsed under a shared try, which re-introduces the '
            'failure mode the layering rule is meant to prevent.',
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
      expect(
        body,
        contains('_ScreenState.countdown'),
        reason: '_onPrefsChange must bail during countdown — '
            'same rebuild storm applies while waiting to start.',
      );
      expect(
        body,
        contains('_ScreenState.paused'),
        reason: '_onPrefsChange must bail while paused — '
            'runStore.notifyListeners fires every 10s regardless.',
      );
    });

    test('_HoldToStopButton Listener is HitTestBehavior.opaque', () {
      // Reason: the hold-to-stop button on the COLLAPSED stats bar
      // didn't fire on Android — taps inside the 48 px square but
      // outside the painted red circle (the corners + the ring
      // overlay during a hold) passed straight through. Listener's
      // default `HitTestBehavior.deferToChild` only claims hits a
      // child claims as opaque; the BoxDecoration circle only paints
      // within the circle, leaving ~21 % of the touch area
      // transparent for hit-testing. The expanded panel happened to
      // work because its 68 px button has a bigger circle vs the
      // same corner-gap proportion. `HitTestBehavior.opaque` makes
      // the Listener itself claim the full square — fixes both the
      // collapsed-bar bug and the proportionally-smaller miss
      // window in the expanded variant.
      final body = _extractMethodBody(
        source,
        r'class _HoldToStopButtonState extends State<_HoldToStopButton>',
      );
      // _extractMethodBody slices to the next top-level `}`, but
      // class bodies span more than the build method we care about.
      // Just regex the build() body for the Listener and its
      // behavior arg in one go.
      final m = RegExp(
        r'return Listener\(\s*behavior:\s*HitTestBehavior\.opaque',
      ).firstMatch(source);
      expect(
        m,
        isNotNull,
        reason: '_HoldToStopButton must wrap its Listener with '
            'HitTestBehavior.opaque so taps anywhere inside the 48–68 px '
            'square fire onPointerDown — see the collapsed-bar stop '
            'button regression.',
      );
      // Use `body` so the test fails clearly if someone renames or
      // splits the state class beyond the regex above.
      expect(
        body,
        contains('Listener('),
        reason: 'The Listener call site must live inside '
            '_HoldToStopButtonState.build — moving it elsewhere defeats '
            'the regression check.',
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

    test('_loadAll keeps the directory walk synchronous', () {
      // Reason: we *want* this to be async for the UI-freeze argument,
      // but the streaming form (`_dir.list()...toList()`) deadlocks
      // inside `testWidgets` — RunsScreen's widget tests hang for >10
      // minutes because the I/O isolate's reply ports interact poorly
      // with the test binding's fake-async zone. Until we have a fix
      // that doesn't trip the test environment, the directory walk
      // stays sync; the per-file decode that follows is still async +
      // parallel via Future.wait, which is where the bulk of the cost
      // actually lives anyway.
      final body = _extractMethodBody(
        source,
        r'Future<void> _loadAll\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('listSync'),
        reason: '_loadAll must use _dir.listSync() — the async _dir.list() '
            'form deadlocks RunsScreen widget tests under the flutter_test '
            'binding. Per-file reads stay async via Future.wait.',
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
      expect(
        body,
        contains('listSync'),
        reason: 'routeStore._loadAll must use _dir.listSync() — '
            'mirrors the runStore listing decision (async _dir.list() '
            'deadlocks RunsScreen widget tests under flutter_test).',
      );
    });
  });

  group('heavy parsers run in compute() isolates', () {
    test('StravaImporter.importFromZip dispatches to compute()', () {
      // Reason: a 5-year Strava export contains hundreds of activities,
      // each requiring GZip decode + XML / FIT parse. Doing that on the
      // UI thread freezes the foreground for tens of seconds. The whole
      // sync-parse body must run inside compute() so the import progress
      // dialog can keep rendering.
      final src = File('lib/strava_importer.dart').readAsStringSync();
      final body = _extractMethodBody(
        src,
        r'static Future<StravaImportResult> importFromZip\([^)]*\)\s*async\s*\{',
      );
      expect(
        body,
        contains('compute('),
        reason: 'importFromZip must dispatch ZipDecoder + per-file parse '
            'into compute() — the parsers run synchronously and would '
            'otherwise block the UI for tens of seconds on a large export.',
      );
    });

    test('BackupService zip encode runs in a background isolate', () {
      // Reason: ZipEncoder().encode(archive) on a multi-MB backup
      // (thousands of runs + tracks) blocks the UI for seconds. The
      // _encodeArchiveInIsolate helper extracts entries on the main
      // isolate and pushes the encoder into compute().
      final src = File('lib/backup.dart').readAsStringSync();
      expect(
        src,
        contains('_encodeArchiveInIsolate'),
        reason: 'backup.dart must keep the _encodeArchiveInIsolate helper '
            '— inlining ZipEncoder().encode(archive) on the main isolate '
            'reintroduces a multi-second UI freeze on a large backup.',
      );
      expect(
        src,
        contains('_decodeArchiveInIsolate'),
        reason: 'backup.dart must keep the _decodeArchiveInIsolate helper '
            '— inlining ZipDecoder().decodeBytes(bytes) on the main isolate '
            'reintroduces a multi-second UI freeze when restoring.',
      );
    });

    test('Single-file route import dispatches to compute()', () {
      // Reason: a 5MB GPX file (long ride exported as a route) parses on
      // a single XmlDocument call that takes hundreds of ms on a phone.
      // The routes-screen import must wrap the parse in compute() so the
      // user-tap → save flow doesn't lock up.
      final src = File('lib/screens/routes_screen.dart').readAsStringSync();
      final body = _extractMethodBody(
        src,
        r'Future<void> _importFile\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('compute('),
        reason: '_importFile must run RouteParser.fromGpx / fromKml inside '
            'compute() so a large file does not freeze the routes screen.',
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
      //
      // The Kotlin source only exists in the android/ host project of
      // `apps/mobile_android`. The byte-identical test file also runs
      // from `apps/mobile_ios` — skip the assertion there since the
      // host file is shared between targets and only ever lives once.
      final file = File(
        'android/app/src/main/kotlin/com/runonward/app/RunNotificationBridge.kt',
      );
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
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

  group('thumbnail privacy-zone clipping', () {
    test('RunTrackPreview routes non-owner fetches through clip-public-track EF',
        () {
      // Reason: feed thumbnails are shown to non-owner viewers. The
      // pre-20260619_001 pattern was "fetchTrackByPath then
      // clipTrackForUser client-side" but that leaked the unclipped
      // blob via direct Storage download. Non-owner thumbnails must
      // now go through fetchClippedTrackForRun (which calls the
      // clip-public-track Edge Function — server-side download +
      // clip). Owners keep the direct path since the per-user-folder
      // Storage policy still gates them.
      final source = File('lib/widgets/run_track_preview.dart')
          .readAsStringSync();
      expect(
        source,
        contains('fetchClippedTrackForRun'),
        reason: 'Non-owner thumbnails must use fetchClippedTrackForRun '
            '— direct Storage download leaks the unclipped blob. See '
            'decisions §33.',
      );
    });

    test('feed_screen passes runId + ownerUserId to RunTrackPreview', () {
      // Reason: the EF non-owner clip path needs the run id (server
      // resolves track_url + clips inline). Without the prop,
      // RunTrackPreview can't reach the EF and renders a placeholder
      // instead of the clipped polyline.
      final source =
          File('lib/screens/feed_screen.dart').readAsStringSync();
      expect(
        source,
        matches(RegExp(r'RunTrackPreview\([^)]*runId:', dotAll: true)),
        reason: 'feed_screen must thread the run id into '
            'RunTrackPreview so the clip-public-track EF can resolve it.',
      );
      expect(
        source,
        matches(RegExp(r'RunTrackPreview\([^)]*ownerUserId:', dotAll: true)),
        reason: 'feed_screen must thread the run owner id into '
            'RunTrackPreview so the privacy-zone clip kicks in.',
      );
    });

    test('RunTrackPreview cache is bounded (LRU)', () {
      // Reason: without the cap a long session through 1000+ runs
      // holds every deserialised track in memory until app restart.
      // Map preserves insertion order so dropping `keys.first` evicts
      // the oldest.
      final source = File('lib/widgets/run_track_preview.dart')
          .readAsStringSync();
      expect(
        source,
        contains('_cacheMax'),
        reason: 'RunTrackPreview cache must have a bounded size — see '
            'the _cacheMax constant.',
      );
      expect(
        source,
        contains('_cache.remove(_cache.keys.first)'),
        reason: 'LRU eviction must drop the oldest entry when the cache '
            'is full.',
      );
    });

    test('public_run_screen routes non-owner tracks through clip-public-track EF',
        () {
      // Reason: /share/run/[id] (and the feed-card → public_run_screen
      // navigation path) renders runs from arbitrary owners. The pre-
      // 20260619_001 pattern of "fetchTrackByPath then clipTrackForUser"
      // leaked the unclipped blob via direct Storage download. The
      // screen must now branch on `api.userId == row.userId`: owners
      // take fetchTrackByPath (direct, gated by per-user-folder
      // policy), non-owners take fetchClippedTrackForRun (EF,
      // server-side clip).
      final source =
          File('lib/screens/public_run_screen.dart').readAsStringSync();
      expect(
        source,
        contains('fetchClippedTrackForRun'),
        reason: 'public_run_screen must use fetchClippedTrackForRun '
            'for non-owner viewers. See decisions §33.',
      );
      // The owner gate must compare against widget.api.userId — not
      // some hard-coded "always clip" or "never clip".
      expect(
        source,
        matches(RegExp(r'widget\.api\.userId')),
        reason: 'public_run_screen must read the viewer id from '
            'widget.api.userId so the clip step is skipped only for the '
            'run owner.',
      );
    });

    test('public_route_screen routes non-owner waypoints through clipTrackForUser',
        () {
      // Reason: /share/route/[id] is reachable by anyone with the
      // link, including unauthenticated viewers. Routes own a planned
      // polyline that leaks the same start / end / interior locations
      // a recorded run would. Same gate as public_run_screen — clip
      // unless the viewer is the route owner.
      final source =
          File('lib/screens/public_route_screen.dart').readAsStringSync();
      expect(
        source,
        contains('clipTrackForUser'),
        reason: 'public_route_screen must clip non-owner waypoints '
            'through the privacy-zone RPC. See decisions §33.',
      );
      expect(
        source,
        matches(RegExp(r'widget\.api\.userId')),
        reason: 'public_route_screen must read the viewer id from '
            'widget.api.userId so the clip step is skipped only for the '
            'route owner.',
      );
    });

    test('fetchRouteById exposes owner id alongside the Route', () {
      // Reason: Route (the domain class) drops `user_id` to keep its
      // surface display-only. Without an ownerId in the fetch result
      // the public_route_screen can't tell viewer from owner and
      // either over-clips (blanks the owner's own map) or under-clips
      // (privacy leak). The record-shaped return is the contract that
      // makes the clip gate safe.
      final source =
          File('../../packages/api_client/lib/src/api_client.dart')
              .readAsStringSync();
      expect(
        source,
        matches(RegExp(
            r'Future<\(\{Route\? route, String\? ownerId\}\)>\s+fetchRouteById')),
        reason: 'fetchRouteById must return both the Route and the '
            'owner id so public_route_screen can clip for non-owner '
            'viewers. See decisions §33.',
      );
    });

    test('route_detail_screen clips waypoints for non-owner viewers', () {
      // Reason: pre-prod privacy-zones audit (June 2026) found this
      // surface rendered LiveRunMap(plannedRoute: route.waypoints)
      // with no clip step. Bookmarked / public / club-readable routes
      // were leaking the unclipped polyline. Must derive
      // _displayWaypoints via clipRouteForViewer for non-owners; the
      // owner branch reads route.waypoints directly so an outage
      // doesn't blank the owner's own map.
      final source =
          File('lib/screens/route_detail_screen.dart').readAsStringSync();
      expect(
        source,
        contains('clipRouteForViewer'),
        reason: 'route_detail_screen must call clipRouteForViewer for '
            'non-owner viewers — bare route.waypoints render leaks the '
            'unclipped polyline. See decisions §33.',
      );
      expect(
        source,
        matches(RegExp(r'plannedRoute:\s*_displayWaypoints')),
        reason: 'route_detail_screen must hand _displayWaypoints to '
            'LiveRunMap, not route.waypoints — the row column is the '
            'unclipped polyline for non-owners.',
      );
    });

    test('routes_screen + club_detail + explore_routes use RouteTrackPreview',
        () {
      // Reason: same audit. Three list-view screens previously
      // rendered <TrackPreview points: route.waypoints>. Owned rows
      // were fine but bookmarked / club / community-public rows leaked.
      // RouteTrackPreview wraps with the same lazy clip + cache
      // pattern as RunTrackPreview so non-owner viewers see clipped
      // output and owners short-circuit to the row column.
      for (final path in const [
        'lib/screens/routes_screen.dart',
        'lib/screens/club_detail_screen.dart',
        'lib/screens/explore_routes_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('RouteTrackPreview'),
          reason:
              '$path must use RouteTrackPreview rather than bare TrackPreview — '
              'non-owner thumbnails leak the unclipped polyline otherwise. '
              'See decisions §33.',
        );
      }
    });

    test('RouteTrackPreview routes non-owner fetches through clip_route_for_viewer',
        () {
      // Reason: clipRouteForViewer is the only path that returns
      // clipped waypoints without first leaking the row's `waypoints`
      // column to the wire. Owner reads use the prop directly;
      // non-owner reads must call ApiClient.clipRouteForViewer.
      final source =
          File('lib/widgets/route_track_preview.dart').readAsStringSync();
      expect(
        source,
        contains('clipRouteForViewer'),
        reason: 'RouteTrackPreview must use ApiClient.clipRouteForViewer '
            'for non-owner viewers. See decisions §33.',
      );
      // LRU bound — same shape as RunTrackPreview.
      expect(
        source,
        contains('_cacheMax'),
        reason: 'RouteTrackPreview cache must have a bounded size — '
            'see RunTrackPreview for the LRU shape.',
      );
    });

    test('clipRouteForViewer fails closed on RPC error', () {
      // Reason: same fail-closed contract as clipTrackForUser. Returning
      // the unclipped row column on RPC error would defeat the helper.
      final source =
          File('../../packages/api_client/lib/src/api_client.dart')
              .readAsStringSync();
      final body = _extractMethodBody(
        source,
        r'Future<List<Waypoint>> clipRouteForViewer\([^)]*\)\s*async\s*\{',
      );
      final tail = body.substring(body.indexOf('try'));
      final catchMatch = RegExp(r'catch \([^)]*\) \{[^}]*\}').firstMatch(tail);
      expect(catchMatch, isNotNull,
          reason: 'clipRouteForViewer must have an explicit catch branch.');
      expect(
        catchMatch!.group(0)!.contains('return const []'),
        isTrue,
        reason: 'clipRouteForViewer must return [] on RPC failure — '
            'see decisions §33.',
      );
    });

    test('public-runs readers go through the public_runs view', () {
      // Reason: pre-prod public-rows audit (June 2026) found that
      // `select * from runs where is_public = true` exposes
      // external_id, training-plan-linkage metadata, sync-state
      // metadata, and link-existence to private routes/events. The
      // public_runs view (migration 20260626_001) strips these.
      // Every public-runs reader must read from the view. fetchRunById
      // was renamed to fetchPublicRunById in the same change to make
      // the contract explicit.
      final source =
          File('../../packages/api_client/lib/src/api_client.dart')
              .readAsStringSync();
      for (final fn in const [
        'fetchPublicRunById',
        'fetchPublicRunsByUser',
        'fetchFollowingFeed',
      ]) {
        final start = source.indexOf(' $fn(');
        expect(start >= 0, isTrue,
            reason: 'Could not locate $fn — rename?');
        // Walk forward to the next blank-line + close-brace which is
        // the natural end of an api_client method body. Concrete
        // enough for the assertion: we just need the .from() call
        // present somewhere in the body region.
        final end = source.indexOf('\n  }\n', start);
        expect(end > start, isTrue,
            reason: 'Could not locate end of $fn body');
        final body = source.substring(start, end);
        expect(
          body.contains("from('public_runs')"),
          isTrue,
          reason:
              '$fn must read from public_runs view rather than the runs '
              'table — see decisions §33 and migration 20260626_001.',
        );
        expect(
          RegExp(r"from\(\s*RunRow\.table\s*\)").hasMatch(body),
          isFalse,
          reason:
              '$fn must NOT read from the bare RunRow.table — that path '
              'leaks external_id, training-plan-linkage metadata, etc.',
        );
      }
    });

    test('clipTrackForUser fails closed on RPC error', () {
      // Reason: returning the unclipped input on RPC error was the
      // privacy leak this helper exists to prevent. Fail-closed
      // (return []) so a transient outage renders an empty map for
      // non-owner viewers instead of leaking the full track. The
      // empty-input early-return is fine — `points.isEmpty ? points`
      // is the same shape as `[]`, just no allocation.
      final source =
          File('../../packages/api_client/lib/src/api_client.dart')
              .readAsStringSync();
      final body = _extractMethodBody(
        source,
        r'Future<List<Map<String, dynamic>>> clipTrackForUser\([^)]*\)\s*async\s*\{',
      );
      // Pull just the catch block and the post-rpc shape-validation
      // path so the assertion doesn't trip on the empty-input guard.
      final tail = body.substring(body.indexOf('try'));
      expect(
        tail.contains('return const [];'),
        isTrue,
        reason: 'clipTrackForUser must return [] on RPC failure — see '
            'decisions §33.',
      );
      // The catch / shape-fail branches must not return the unclipped
      // input.
      final catchMatch = RegExp(r'catch \([^)]*\) \{[^}]*\}').firstMatch(tail);
      expect(catchMatch, isNotNull,
          reason: 'clipTrackForUser must have an explicit catch branch.');
      expect(
        catchMatch!.group(0)!.contains('return points'),
        isFalse,
        reason: 'clipTrackForUser must not fall back to the input track '
            'on RPC error — that is the leak this helper exists to '
            'prevent.',
      );
    });
  });
}
