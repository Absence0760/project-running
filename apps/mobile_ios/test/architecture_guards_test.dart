// Guard-rail tests that pin the mobile app's efficiency + layering
// invariants in place. Each test parses a source file as text and asserts
// a pattern is (or isn't) present, with a **why** comment explaining the
// rule so a future editor can decide whether it's safe to break.
//
// When one of these fails, it means a recent change reversed an
// optimization or broke a layering rule we deliberately codified. Read
// the reason before blindly updating the test.

import 'dart:io';

import 'package:api_client/api_client.dart';
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

    test('live tree wraps stats-driven subtrees in ValueListenableBuilder',
        () {
      // Reason: if the map / off-route banner / route-remaining badge /
      // stats panel stop subscribing to _statsNotifier, they'll freeze at
      // whatever values they held at the last setState.
      final buildLive = _extractMethodBody(
        source,
        r'Widget _buildLive\(BuildContext context\)\s*\{',
      );
      final matches = RegExp(r'ValueListenableBuilder<_LiveStats>')
          .allMatches(buildLive);
      expect(
        matches.length,
        greaterThanOrEqualTo(4),
        reason: '_buildLive expects at least 4 '
            'ValueListenableBuilder<_LiveStats> wrappers (map, '
            'route-remaining badge, off-route banner, stats panel).',
      );
    });

    test('_buildLive shares one LiveRunMap across countdown and recording',
        () {
      // Reason: keeping a single LiveRunMap mounted across the
      // countdown→recording stage flip is what kills the brief "flash to
      // default backdrop" the runner used to see at the end of the
      // count. Element identity is what preserves the flutter_map
      // MapController + tile-cache attachment + interpolated-dot tween
      // state, so the stage transition becomes a chrome swap instead of
      // an unmount-and-remount. A future refactor that returns to the
      // pre-2026 shape (separate `_buildCountdown` that owns its own
      // LiveRunMap, plus `_buildRecording` that owns another) would
      // re-introduce the flash. Mirrors the watch_wear CountdownOverlay
      // (RunWatchApp.kt:264) which solves the same problem.
      final src = source;
      // `_buildCountdown` should no longer exist as a separate method.
      expect(
        RegExp(r'Widget _buildCountdown\b').hasMatch(src),
        isFalse,
        reason: '_buildCountdown was unified into _buildLive — '
            're-introducing it splits the map across two subtrees and '
            'brings back the flash.',
      );
      // _buildLive should contain exactly one LiveRunMap construction.
      final body =
          _extractMethodBody(src, r'Widget _buildLive\(BuildContext context\)\s*\{');
      final mapCtors = RegExp(r'\bLiveRunMap\(').allMatches(body).length;
      expect(
        mapCtors,
        1,
        reason: '_buildLive must contain exactly one LiveRunMap '
            'construction; found $mapCtors. Two would defeat the '
            'shared-element optimisation.',
      );
    });

    test('_saveInProgress stamps workout review metadata', () {
      // Reason: a crash mid-workout must preserve the planned-vs-actual
      // review trail. The in-progress save path calls
      // `WorkoutRunner.reviewMetadata` so the recovered run lands with
      // `plan_workout_id`, `workout_step_results`, and
      // `workout_adherence` already on its metadata bag. If a future
      // refactor removes the call from _saveInProgress, a crashed
      // workout silently drops the review trail again. (7d in followups)
      final body = _extractMethodBody(
        source,
        r'Future<void> _saveInProgress\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('reviewMetadata'),
        reason: '_saveInProgress must call WorkoutRunner.reviewMetadata '
            'so a crashed workout keeps its review on recovery.',
      );
    });

    test('_stop stamps workout review metadata via the same helper', () {
      // Reason: pairs with the in-progress save guard above. Both call
      // sites must use the same helper so a final save and a crash-
      // recovered partial save produce identical metadata shape.
      final body = _extractMethodBody(
        source,
        r'Future<void> _stop\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('reviewMetadata'),
        reason: '_stop must call WorkoutRunner.reviewMetadata — '
            'keeps the contract symmetric with _saveInProgress.',
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

    test('_onOverlaySizeChanged defers setState to a post-frame callback', () {
      // Reason: SizeChangedLayoutNotification dispatches *synchronously*
      // from inside `_RenderSizeChangedWithCallback.performLayout` —
      // we're still in the layout phase when the notification fires.
      // Calling `setState` directly from here throws a "Build scheduled
      // during frame" assertion. Repro: hold the stop button on the
      // collapsed bar; the per-tick progress-ring rebuild triggers a
      // panel relayout which fires the size notifier mid-layout.
      // Schedule the state change for the next frame instead.
      final body = _extractMethodBody(
        source,
        r'bool _onOverlaySizeChanged\(SizeChangedLayoutNotification _\)\s*\{',
      );
      expect(
        body,
        contains('addPostFrameCallback'),
        reason: '_onOverlaySizeChanged must wrap its setState in '
            'WidgetsBinding.instance.addPostFrameCallback so the '
            'rebuild lands in the next frame, not during the layout '
            'pass that fired the notification.',
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

  group('privacy_default → run-save wiring', () {
    test('run_screen._stop reads newRunsArePublic when calling saveRun', () {
      // Reason: the user-flagged gap — the `privacy_default` setting
      // was previously stranded (set in the UI but never read at
      // save time). Catches a regression that drops the
      // `isPublic:` arg or hardcodes a literal value.
      final source = File('lib/screens/run_screen.dart').readAsStringSync();
      expect(
        source,
        contains('widget.preferences.newRunsArePublic'),
        reason:
            'run_screen must read `widget.preferences.newRunsArePublic` '
            'to honour the user\'s privacy_default setting on save. '
            'See decisions / docs/settings.md.',
      );
      expect(
        source.contains('api.saveRun(\n          run,\n          isPublic:') ||
            source.contains('api.saveRun(run, isPublic:'),
        isTrue,
        reason:
            'The api.saveRun call in _stop must pass isPublic so the '
            'privacy_default setting reaches RunRow.isPublic at upsert.',
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

    test('BackupService streams encode + decode to / from disk', () {
      // Reason: pre-May-2026 backup built the entire `Archive`
      // in-memory then `ZipEncoder().encode(archive)`'d it in one
      // shot (offloaded to compute() to avoid UI freeze). For a
      // backup at scale (5 000 runs × ~50 KB gzipped tracks ≈
      // 250 MB), that path OOMs on mid-tier Android phones — the
      // background isolate held the entire ZIP plus a duplicated
      // `[name, bytes]` copy.
      //
      // The new design uses `ZipFileEncoder` (writes incrementally
      // to disk as each track lands) on the write side, and
      // `InputFileStream` + `ZipDecoder().decodeStream` on the
      // read side (lazy per-file reads). Peak heap is now
      // O(concurrency × avg-track-size), regardless of total run
      // count. See [decisions.md § 66] for the rationale.
      final src = File('lib/backup.dart').readAsStringSync();
      expect(
        src,
        contains('ZipFileEncoder'),
        reason: 'backup.dart must keep the ZipFileEncoder streaming '
            'writer — buffering an in-memory Archive instead OOMs on '
            'phones at ~2000 runs (decisions.md § 66).',
      );
      expect(
        src,
        contains('InputFileStream'),
        reason: 'backup.dart restore must read via InputFileStream — '
            'zipFile.readAsBytes() pulls the whole archive into RAM '
            '(decisions.md § 66).',
      );
      expect(
        src,
        contains('decodeStream'),
        reason: 'backup.dart restore must use ZipDecoder.decodeStream — '
            'decodeBytes pulls all entries into RAM at once.',
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
        'android/app/src/main/kotlin/com/threkir/app/RunNotificationBridge.kt',
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

    test('public_route_screen routes non-owner waypoints through clipRouteForViewer',
        () {
      // Reason: /share/route/[id] is reachable by anyone with the
      // link, including unauthenticated viewers. Routes own a planned
      // polyline that leaks the same start / end / interior locations
      // a recorded run would. Same gate as public_run_screen — clip
      // unless the viewer is the route owner. Use the route-specific
      // RPC `clipRouteForViewer`, NOT the run-bound `clipTrackForUser`
      // (which downloads from the runs Storage bucket and skips route
      // visibility entirely).
      final source =
          File('lib/screens/public_route_screen.dart').readAsStringSync();
      expect(
        source,
        contains('clipRouteForViewer'),
        reason: 'public_route_screen must clip non-owner waypoints '
            'through `clipRouteForViewer`, the route-specific RPC. '
            'See decisions §33.',
      );
      expect(
        source,
        isNot(matches(RegExp(r'\.clipTrackForUser\s*\('))),
        reason: 'public_route_screen must not call `clipTrackForUser` — '
            'that helper is for runs (Storage-backed) and skips route '
            'visibility / club-member checks. Use clipRouteForViewer.',
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

    test('race_controller relies on the DB trigger, not client-side filter', () {
      // Reason: race_pings are clipped server-side by the
      // `race_pings_drop_in_zone` BEFORE-INSERT trigger
      // (migration 20260704_001, pinned by
      // `apps/backend/supabase/tests/rls_race_pings_trigger_test.sql`).
      // The mobile race controller must not introduce a parallel
      // client-side privacy_in_any_zone / clipPointsToZones pass —
      // doing so would either leak the broadcaster's zones to the
      // device (defeating the purpose) or produce a second clip
      // pass that drifts from the trigger semantics. Same trust
      // contract documented on `live_spectator_screen.dart` and the
      // web equivalents.
      final source =
          File('lib/race_controller.dart').readAsStringSync();
      expect(
        source.contains('privacy_in_any_zone'),
        isFalse,
        reason: 'race_controller.dart must not call privacy_in_any_zone — '
            'the DB trigger is the single line of defence; see '
            'apps/backend/supabase/migrations/20260704_001_clip_race_pings_to_privacy_zones.sql.',
      );
      expect(
        source.contains('clipPointsToZones'),
        isFalse,
        reason: 'race_controller.dart must not call clipPointsToZones — '
            'the DB trigger is the single line of defence.',
      );
      // Audit pass 3 widened this check: lib/privacy.dart exposes both
      // `isInAnyZone` (point-membership) and `clipPointsToZones`
      // (clipping). Both client-side calls would pull zones onto the
      // device, which is exactly what the trigger-only contract
      // forbids.
      expect(
        source.contains('isInAnyZone'),
        isFalse,
        reason: 'race_controller.dart must not call isInAnyZone — '
            'fetching the broadcaster\'s zones to the client (which is '
            'what isInAnyZone requires) defeats the trigger-only '
            'trust contract documented in decisions §33.',
      );
    });
  });

  group('top banner is the canonical notification primitive', () {
    // Reason: SnackBar floats at the bottom of the screen and on the
    // recording surface overlapped the Pause / Stop / Lap controls; the
    // runner couldn't reach Stop without dismissing a snack first. We
    // standardised on the top-anchored banner in
    // lib/widgets/top_banner.dart so notifications never cover bottom
    // controls. Direct showSnackBar / ScaffoldMessenger.of(context) calls
    // anywhere under lib/screens/ or lib/widgets/ are a regression — go
    // through showTopBanner instead.

    Iterable<File> _libDartFiles(String subdir) sync* {
      final dir = Directory('lib/$subdir');
      if (!dir.existsSync()) return;
      for (final e in dir.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) yield e;
      }
    }

    test('no direct showSnackBar calls in lib/screens or lib/widgets', () {
      final offenders = <String>[];
      for (final f in [..._libDartFiles('screens'), ..._libDartFiles('widgets')]) {
        // Skip the helper itself; its doc comment legitimately mentions
        // the API it replaces.
        if (f.path.endsWith('top_banner.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('showSnackBar')) {
          offenders.add(f.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Use showTopBanner(context, ...) instead of '
            'ScaffoldMessenger.showSnackBar — see '
            'lib/widgets/top_banner.dart. Offenders: $offenders',
      );
    });

    test('no ScaffoldMessenger.of(context) lookups in lib/screens or lib/widgets',
        () {
      final offenders = <String>[];
      for (final f in [..._libDartFiles('screens'), ..._libDartFiles('widgets')]) {
        if (f.path.endsWith('top_banner.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('ScaffoldMessenger.of(')) {
          offenders.add(f.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'ScaffoldMessenger.of(context) is the SnackBar entrypoint; '
            'route notifications through showTopBanner instead. '
            'Offenders: $offenders',
      );
    });
  });

  group('explore-screen save clips non-owner routes', () {
    // Reason: Explore browsing reads from `search_public_routes` /
    // `nearby_routes` / `routes_within_box`, which (after migration
    // 20260703_001_public_routes_view.sql) return rows from the
    // `public_routes` view — i.e. with no waypoints. Naively saving
    // such a row to LocalRouteStore stores an empty-waypoint route
    // (broken offline preview), and reaching for the original
    // unclipped waypoints would leak the original author's start
    // coordinate to anyone the saver shares the route with. The
    // mitigation is `_saveRoute` calling `ApiClient.fetchRouteById`
    // before `routeStore.save` — that helper does owner-aware
    // clipping (full polyline if the saver IS the owner, server-
    // clipped polyline via `clip_route_for_viewer` otherwise). This
    // guard pins that flow in place.

    test('_saveRoute fetches via ApiClient before persisting', () {
      final src =
          File('lib/screens/explore_routes_screen.dart').readAsStringSync();
      final body = _extractMethodBody(
        src,
        r'Future<void> _saveRoute\(cm\.Route route\)\s*async\s*\{',
      );
      expect(
        body.contains('fetchRouteById'),
        isTrue,
        reason: '_saveRoute must call ApiClient.fetchRouteById to fetch '
            'the privacy-zone-clipped polyline before saving — see the '
            'audit/privacy-zones High finding from /audit/all on '
            '2026-05-03.',
      );
      expect(
        body.contains('routeStore.save'),
        isTrue,
        reason: '_saveRoute should still persist via routeStore.save '
            'once it has the clipped Route in hand.',
      );
      // Order check: the fetch must come BEFORE the save.
      final fetchIdx = body.indexOf('fetchRouteById');
      final saveIdx = body.indexOf('routeStore.save');
      expect(
        fetchIdx < saveIdx,
        isTrue,
        reason: 'fetchRouteById must run before routeStore.save — '
            'persisting before clipping defeats the whole point.',
      );
    });
  });

  group('release builds never load .env.local', () {
    // Reason: pubspec.yaml ships .env.local as a Flutter asset for
    // local development convenience. A developer building a release
    // APK locally without first overwriting their .env.local would
    // bake real SUPABASE_ANON_KEY, MAPTILER_KEY, dev creds, and any
    // BYPASS_PAYWALL=true into the APK assets. The runtime guard is
    // the kDebugMode gate around the dotenv.load call in main.dart —
    // release builds skip the load entirely so the asset bytes,
    // even if extractable from the APK, are never read by the app.
    // /audit/all High (secrets agent, 2026-05-07).
    test('main.dart only calls dotenv.load(\'.env.local\') under kDebugMode',
        () {
      final source = File('lib/main.dart').readAsStringSync();
      final loadIdx = source.indexOf("dotenv.load(fileName: '.env.local'");
      expect(
        loadIdx,
        greaterThan(0),
        reason:
            'Expected dotenv.load(fileName: \'.env.local\', ...) in main.dart. '
            'If the call has been replaced or removed, update this guard.',
      );
      // Walk backwards to find the nearest `if (` opening — the load
      // must sit inside an `if (kDebugMode) { ... }` block.
      final preceding = source.substring(0, loadIdx);
      final guardIdx = preceding.lastIndexOf('if (kDebugMode)');
      expect(
        guardIdx,
        greaterThan(0),
        reason:
            'dotenv.load(\'.env.local\', ...) must sit inside an '
            '`if (kDebugMode) { ... }` block. Removing the guard re-opens '
            'the audit/secrets High where release-built APKs leak the '
            'developer\'s local secrets via the bundled asset.',
      );
      // Sanity check: no other `if (` clause must intercede between
      // the kDebugMode guard and the load — otherwise the kDebugMode
      // block could be empty while the load lives elsewhere.
      final between = source.substring(guardIdx, loadIdx);
      expect(
        between.indexOf('if (', 'if (kDebugMode)'.length),
        -1,
        reason: 'The kDebugMode guard must directly wrap the dotenv.load '
            'call — no intermediate conditional.',
      );
    });
  });

  group('column-grant lockdown discipline (clubs + events)', () {
    // Reason: `clubs.invite_token` and `events.meet_lat` / `meet_lng`
    // are revoked from anon + authenticated at the column level
    // (migrations 20260801_001 + 20260723_001 + 20260806_001 +
    // 20260818_001). PostgREST's `select('*')` (i.e. supabase-dart's
    // `.select()` with no args, OR a nested `<table>(*)` embed)
    // expands to all columns at the SQL layer and raises 42501 because
    // the role lacks SELECT on the revoked columns. CI surfaced this
    // as widespread Playwright failure when the audit migration
    // landed without the call-site fix.
    //
    // Pin the discipline statically so the next regression fails the
    // `Test Flutter packages` job in PR CI before it reaches Postgres.
    // The fix at any failing call site is "enumerate the columns
    // explicitly via the constants in social_service.dart /
    // api_client.dart", or for nested embeds use the `($_safeCols)`
    // form.

    final mobileSources = <String>[
      'lib/social_service.dart',
      'lib/race_controller.dart',
      'lib/backup.dart',
    ];
    final apiClientPath =
        '../../packages/api_client/lib/src/api_client.dart';

    for (final path in [...mobileSources, apiClientPath]) {
      test('$path enumerates columns on clubs/events reads', () {
        final source = File(path).readAsStringSync();
        // Strip line comments + block comments so the regex can't
        // false-positive on documentation that mentions the pattern.
        final stripped = source
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//.*'), '');
        // a. `.from('clubs').select()` (no arg = `*`) is forbidden.
        // b. `.from('events').select()` (no arg) is forbidden.
        // c. nested `clubs(*)` / `events(*)` via PostgREST embed is
        //    forbidden. The arg form `clubs($_clubSafeCols)` is fine.
        // Note: `from(ClubRow.table)` and `from(EventRow.table)` are
        // covered too — both expand to the literal table name in the
        // wire request.
        final patterns = <RegExp>[
          RegExp(r'''\.from\(['"]clubs['"]\)\.select\(\s*\)'''),
          RegExp(r'''\.from\(['"]events['"]\)\.select\(\s*\)'''),
          RegExp(r'''\.from\(ClubRow\.table\)\.[^.]*\.select\(\s*\)'''),
          RegExp(r'''\.from\(EventRow\.table\)\.[^.]*\.select\(\s*\)'''),
          RegExp(r'''['"`]clubs\(\*\)'''),
          RegExp(r'''['"`]events\(\*\)'''),
        ];
        for (final p in patterns) {
          expect(
            p.hasMatch(stripped),
            isFalse,
            reason: 'Pattern ${p.pattern} matched in $path. '
                'PostgREST `*` expansion raises 42501 against the '
                'column-grant lockdown on clubs / events — enumerate '
                'columns via `_clubSafeCols` / `_eventSafeCols` (or '
                'the equivalent in the calling file). See migration '
                '20260818_001_redo_column_grant_lockdowns.sql.',
          );
        }
      });
    }
  });

  group('iOS Info.plist', () {
    // These tests are gated on the iOS Info.plist being present —
    // they auto-skip on the Android twin (which has no `ios/`
    // directory). The twin-share rule keeps the test file byte-
    // identical; the runtime check below picks the right target.
    test('every plugin-required usage-description key is set', () {
      final file = File('ios/Runner/Info.plist');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      // Without these keys iOS silently denies the permission and
      // the corresponding feature fails at runtime — the worst kind
      // of regression because nothing throws, the feature just
      // returns empty / never streams. Pin them in place.
      final required = <String, String>{
        'NSLocationWhenInUseUsageDescription': 'geolocator (foreground GPS)',
        'NSLocationAlwaysAndWhenInUseUsageDescription':
            'geolocator (background GPS during a run)',
        'NSHealthShareUsageDescription':
            'health (HealthKit reads for the import surface)',
        'NSBluetoothAlwaysUsageDescription':
            'flutter_reactive_ble (BLE chest-strap HR)',
        'NSMotionUsageDescription':
            'pedometer (treadmill step count / cadence)',
        'NSPhotoLibraryUsageDescription':
            'image_picker (attaching photos to runs)',
      };
      for (final entry in required.entries) {
        expect(
          body,
          contains('<key>${entry.key}</key>'),
          reason: 'Info.plist must declare ${entry.key} '
              '(used by ${entry.value}). iOS denies the permission '
              'silently when the key is missing.',
        );
      }
    });

    test('Workmanager background-task identifier is registered', () {
      final file = File('ios/Runner/Info.plist');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      // Workmanager (`registerPeriodicTask` in background_sync.dart)
      // uses BGTaskScheduler under the hood on iOS 13+. Without the
      // identifier listed in BGTaskSchedulerPermittedIdentifiers
      // the task ID gets rejected at registration time.
      expect(
        body,
        contains('com.threkir.backgroundSync'),
        reason: 'BGTaskSchedulerPermittedIdentifiers must include '
            'the Workmanager task ID (com.threkir.backgroundSync) '
            'or the periodic sync job will not run on iOS.',
      );
      expect(
        body,
        contains('<string>processing</string>'),
        reason: 'UIBackgroundModes must include `processing` so the '
            'BGTaskScheduler permitted-identifier above is honoured.',
      );
    });
  });

  group('segments v2 wiring', () {
    test('SegmentsPanel widget calls the v2 tiered RPC, not the v1 fetcher',
        () {
      // Reason: the panel switched to fetchSegmentLeaderboardTiered when
      // v2 shipped. Reaching for v1 silently drops the gender + age-band
      // filtering even when the dropdowns are populated.
      final source = File('lib/widgets/segments_panel.dart').readAsStringSync();
      expect(
        source.contains('fetchSegmentLeaderboardTiered'),
        isTrue,
        reason: 'segments_panel.dart must route through the v2 RPC',
      );
    });

    test('SegmentsPanel uses the shared kSegmentAgeBands constant', () {
      // Reason: a panel-local copy of the age bins would drift from the
      // RPC's regex (the migration parses `^[0-9]+-[0-9]+$` plus '75+').
      // Reading the shared constant keeps both ends in lockstep.
      final source = File('lib/widgets/segments_panel.dart').readAsStringSync();
      expect(
        source.contains('kSegmentAgeBands'),
        isTrue,
        reason: 'segments_panel.dart must read kSegmentAgeBands from api_client',
      );
      expect(
        source.contains("const kSegmentAgeBands = <String>["),
        isFalse,
        reason: 'segments_panel.dart must not redeclare kSegmentAgeBands',
      );
    });

    test('api_client v1 + v2 fetchers both share assignCompetitionRanks', () {
      // Reason: previously v1 assigned i+1 unconditionally (ties got
      // distinct ranks) while v2 ran its own in-line loop with a
      // lastTime=-1 sentinel that collided with a real time of 0/-1.
      // Both paths now route through the shared helper. The check pulls
      // each function body by slicing between known anchor points.
      final source =
          File('../../packages/api_client/lib/src/api_client.dart')
              .readAsStringSync();
      final v1Start = source.indexOf('fetchSegmentLeaderboardWithAthletes(');
      final v2Start = source.indexOf('fetchSegmentLeaderboardTiered(');
      final fetchEffortsStart = source.indexOf('fetchEffortsForRunWithSegments(');
      expect(v1Start, greaterThan(0), reason: 'v1 fetcher missing');
      expect(v2Start, greaterThan(v1Start), reason: 'v2 fetcher missing');
      expect(fetchEffortsStart, greaterThan(v2Start),
          reason: 'method ordering changed — update the slice anchors');
      final v1Body = source.substring(v1Start, v2Start);
      final v2Body = source.substring(v2Start, fetchEffortsStart);
      expect(v1Body.contains('assignCompetitionRanks'), isTrue,
          reason: 'v1 must route through assignCompetitionRanks');
      expect(v2Body.contains('assignCompetitionRanks'), isTrue,
          reason: 'v2 must route through assignCompetitionRanks');
    });

    test('SegmentsPanel widget renders a KOM/QOM crown on rank-1 rows', () {
      // Reason: the gold trophy is the parity surface with Strava's
      // KOM/QOM crowns. Conditioning on `entry.rank == 1` keeps it on
      // exactly one row per filtered view. The crownLabel() pipe means
      // the tooltip mentions the active tier rather than a generic
      // "King" label.
      final source =
          File('lib/widgets/segments_panel.dart').readAsStringSync();
      expect(source.contains('Icons.emoji_events'), isTrue,
          reason: 'crown glyph missing');
      expect(source.contains('entry.rank == 1'), isTrue,
          reason: 'crown gate missing');
      expect(source.contains('crownLabel'), isTrue,
          reason: 'crown tooltip not piped through crownLabel()');
      expect(source.contains("'You hold this crown"), isTrue,
          reason: 'viewer-holds-crown banner copy missing');
    });

    test('Dashboard wires its streak card through computeRunStreaks()', () {
      // Reason: the streak figures must come from the pure helper in
      // lib/streaks.dart, not an inline reimplementation. The helper
      // is unit-tested and twinned with web; inline drift would silently
      // disagree on the Strava grace rule.
      final source =
          File('lib/screens/dashboard_screen.dart').readAsStringSync();
      expect(source.contains('computeRunStreaks'), isTrue,
          reason: 'dashboard must call the pure helper');
      expect(source.contains('_StreakRow'), isTrue,
          reason: 'streak card widget missing');
    });

    test('kSegmentAgeBands list matches the migration SQL regex', () {
      // The plpgsql RPC accepts '^[0-9]+-[0-9]+$' OR the literal '75+'.
      // Read the migration, extract the regex, validate every band the
      // client will send.
      final sql = File(
        '../backend/supabase/migrations/'
        '20260829_001_segments_v2_tiered_leaderboards.sql',
      ).readAsStringSync();
      final match = RegExp(r"p_age_band\s*~\s*'(\^[^']+\$)'").firstMatch(sql);
      expect(match, isNotNull, reason: 'age-band regex missing from migration');
      final rpcAccepts = RegExp(match!.group(1)!);
      for (final band in kSegmentAgeBands) {
        expect(
          band == '75+' || rpcAccepts.hasMatch(band),
          isTrue,
          reason: "band '$band' would be rejected by the RPC's regex",
        );
      }
    });
  });

  group('rate-limit error wiring', () {
    // Reason for each guard: rate_limit_errors.dart converts the
    // P0001 raised by migration 20260907_001 into a friendly "wait N
    // minutes" message. Each catch site that handles a create-club
    // or save-route failure must run the helper before falling back
    // to the raw exception toString. A future refactor that swaps
    // the catch block for a generic one would silently lose the
    // friendlier UX — that's exactly the gap the migration commit
    // 37f9ff6 flagged as "Wiring a friendlier 'slow down' toast in
    // data.ts is a small follow-up" and that commit eee128c / 3c71481
    // closed. These guards keep it closed.

    test('club_form_sheet imports + calls rateLimitErrorMessage', () {
      final source =
          File('lib/widgets/club_form_sheet.dart').readAsStringSync();
      expect(
        source.contains("import '../rate_limit_errors.dart'"),
        isTrue,
        reason: 'club_form_sheet must import rate_limit_errors.dart so the '
            'create-club catch path runs through the helper.',
      );
      expect(
        source.contains('rateLimitErrorMessage('),
        isTrue,
        reason:
            'club_form_sheet catch block must call rateLimitErrorMessage.',
      );
    });

    test('route_builder_screen imports + calls rateLimitErrorMessage', () {
      final source =
          File('lib/screens/route_builder_screen.dart').readAsStringSync();
      expect(
        source.contains("import '../rate_limit_errors.dart'"),
        isTrue,
        reason: 'route_builder_screen must import rate_limit_errors.dart '
            'so the saveRoute catch path runs through the helper.',
      );
      expect(
        source.contains('rateLimitErrorMessage('),
        isTrue,
        reason: 'route_builder_screen save catch block must call '
            'rateLimitErrorMessage.',
      );
    });
  });

  group('client-side timeouts on remote helpers', () {
    // Reason: the route-builder iteration awaits four kinds of remote
    // call (OSRM nearest, OSRM route, Open-Meteo elevation, MapTiler
    // geocoding). Without a per-call ceiling, a single slow upstream
    // pins the "Calculating route…" spinner indefinitely — that's
    // the bug that hung shard 3 generate-loop on the Open-Meteo path
    // (fixed in 65fafcd) and the parallel hang risk on routing +
    // geocoding (closed in fc59f59). The constants and the
    // `.timeout(...)` call sites must stay.

    test('routing.dart pins kOsrmSnapTimeout + kOsrmRouteTimeout', () {
      final source = File('lib/routing.dart').readAsStringSync();
      expect(source.contains('const Duration kOsrmSnapTimeout'), isTrue,
          reason: 'kOsrmSnapTimeout constant removed — restore.');
      expect(source.contains('const Duration kOsrmRouteTimeout'), isTrue,
          reason: 'kOsrmRouteTimeout constant removed — restore.');
      expect(source.contains('.timeout(kOsrmSnapTimeout)'), isTrue,
          reason:
              'snapToRoad must apply .timeout(kOsrmSnapTimeout) to the fetcher call.');
      expect(source.contains('.timeout(kOsrmRouteTimeout)'), isTrue,
          reason:
              'fetchRouteThrough must apply .timeout(kOsrmRouteTimeout).');
    });

    test('elevation.dart pins kElevationFetchTimeout', () {
      final source = File('lib/elevation.dart').readAsStringSync();
      expect(source.contains('const Duration kElevationFetchTimeout'), isTrue,
          reason: 'kElevationFetchTimeout constant removed — restore.');
      expect(source.contains('.timeout(kElevationFetchTimeout)'), isTrue,
          reason:
              'fetchElevations batch loop must apply .timeout(kElevationFetchTimeout).');
    });

    test('geocoding.dart pins kGeocodingTimeout', () {
      final source = File('lib/geocoding.dart').readAsStringSync();
      expect(source.contains('const Duration kGeocodingTimeout'), isTrue,
          reason: 'kGeocodingTimeout constant removed — restore.');
      expect(source.contains('.timeout(kGeocodingTimeout)'), isTrue,
          reason: 'searchPlaces must apply .timeout(kGeocodingTimeout).');
    });
  });

  group('route_builder_screen._SaveRouteDialog scrollable content', () {
    // Reason: AlertDialog clips content that exceeds its content area
    // under the actions strip. The 'Save route' dialog has a Name
    // input + a multi-line description + a Make-public toggle — on a
    // short viewport (small phone, IME open) the toggle disappeared
    // behind the Save / Cancel buttons. Field report:
    //   "the save route -> save button is hiding the make public toggle"
    // The fix wraps the content Column in a SingleChildScrollView so
    // excess height scrolls inside the dialog. Pin the wrapping so a
    // future refactor that 'simplifies' the dialog can't drop it.

    test('_SaveRouteDialog wraps its Column in SingleChildScrollView', () {
      final source =
          File('lib/screens/route_builder_screen.dart').readAsStringSync();
      // Find the dialog's build() body and assert it goes
      //   content: SingleChildScrollView( child: Column(...
      // not
      //   content: Column(...
      final dialogIdx = source.indexOf('class _SaveRouteDialogState');
      expect(dialogIdx, greaterThanOrEqualTo(0),
          reason: '_SaveRouteDialogState class moved or renamed.');
      final tail = source.substring(dialogIdx);
      expect(
        tail.contains('content: SingleChildScrollView('),
        isTrue,
        reason:
            "_SaveRouteDialog's AlertDialog content must be wrapped in "
            'SingleChildScrollView so the Make-public toggle is not '
            'clipped behind the actions strip on short screens.',
      );
      // And the toggle still needs to be inside that scrollable content
      // so users can reach it via scroll.
      expect(
        tail.contains("title: const Text('Make public')"),
        isTrue,
        reason:
            'The Make-public SwitchListTile is the field most prone to '
            'clipping — keep it inside the dialog content.',
      );
    });
  });

  group('Supabase bootstrap guard — defends the "Field client has not '
      'been initialized" class of bug', () {
    // Reported as: "Save Failed: LateInitializationError: Field
    // 'client' has not been initialized" when Supabase.initialize
    // failed silently (the `.catchError` in main.dart) but downstream
    // code constructed an ApiClient and tried to call saveRoute.
    // These guards pin the multi-part fix in place so a future
    // refactor doesn't quietly undo it.

    test('main.dart gates ApiClient construction on ApiClient.isInitialized',
        () {
      // Without this gate, a silent Supabase init failure leaves the
      // SDK's `late client` field unset and the first call into
      // ApiClient explodes with LateInitializationError.
      final src = File('lib/main.dart').readAsStringSync();
      expect(
        src,
        contains('ApiClient.isInitialized'),
        reason: 'main.dart must gate `api = ApiClient()` on the static '
            '`ApiClient.isInitialized` flag — otherwise a silent '
            'Supabase.initialize failure produces ApiClient instances '
            'whose first method call throws LateInitializationError.',
      );
    });

    test('_client getter has a non-bypassable initialized check', () {
      // The override branch lets tests inject a fake; the non-override
      // branch must check the static `isInitialized` probe before
      // falling through to `Supabase.instance.client`.
      final src = File('../../packages/api_client/lib/src/api_client.dart')
          .readAsStringSync();
      expect(
        src,
        matches(
            RegExp(r'SupabaseClient\s+get\s+_client\s*\{[^}]*isInitialized')),
        reason: 'The `_client` getter must inspect `isInitialized` (after '
            'falling through the test override). Returning '
            '`Supabase.instance.client` unconditionally re-introduces '
            'the LateInitializationError surface.',
      );
    });

    test('formatSaveRouteError translates the bootstrap signature into '
        'user-friendly copy', () {
      // The defence is what users see when the gate above fails. Pin
      // both the error-type matcher and the friendly copy so the two
      // sides can't drift apart.
      final src =
          File('lib/screens/route_builder_screen.dart').readAsStringSync();
      expect(
        src,
        contains('LateInitializationError'),
        reason: 'formatSaveRouteError must explicitly match '
            'LateInitializationError so the SDK\'s late-field error '
            'surfaces a friendly "Can\'t reach the server" message '
            'instead of leaking the SDK\'s internal field name.',
      );
      expect(
        src,
        contains("Can't reach the server"),
        reason: 'The friendly translation must be the literal copy '
            'shown to the user. Tests in route_builder_screen_test.dart '
            'assert the same phrase.',
      );
    });

    test('TrainingService / SocialService / RaceController each guard '
        'their _c getter on ApiClient.isInitialized', () {
      // These services bypass ApiClient and read Supabase.instance.client
      // directly via their own getter. Before the guard, each of them
      // had the same latent LateInitializationError surface as
      // ApiClient.saveRoute. Apply the same pattern here so the
      // Plans / Clubs / Race screens fail with a typed error instead
      // of the SDK\'s opaque late-field crash.
      for (final path in const [
        'lib/training_service.dart',
        'lib/social_service.dart',
        'lib/race_controller.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src,
          contains('ApiClient.isInitialized'),
          reason: '$path must guard its _c getter on '
              'ApiClient.isInitialized — same bug class as the '
              'original ApiClient.saveRoute report.',
        );
      }
    });

    test('SettingsService guards on ApiClient.isInitialized too', () {
      // Lives in the api_client package alongside ApiClient itself —
      // imports ApiClient by relative path.
      final src = File(
        '../../packages/api_client/lib/src/settings_service.dart',
      ).readAsStringSync();
      expect(
        src,
        contains('ApiClient.isInitialized'),
        reason: 'SettingsService.dart must guard its static _client '
            'getter on ApiClient.isInitialized. Without the guard, '
            'reading any setting from a half-initialized session '
            'reproduces the original LateInitializationError surface.',
      );
    });
  });

  // ---- WearRoutesBridge cross-language wiring guards -------------------
  //
  // Reason: the phone→watch route push spans three source files in
  // two languages (Dart + Kotlin), plus two more in a different
  // Gradle module (watch_wear). Drift on any single side breaks the
  // wire silently. Source-grep guards close the loop without
  // requiring a Kotlin test source set on the phone app (which
  // doesn't exist today).
  //
  // Schema: 4 channel names + 1 DataLayer path + 2 data map keys
  // must agree across:
  //
  //   apps/mobile_android/lib/wear_routes_bridge.dart           (Dart writer)
  //   apps/mobile_android/android/.../WearRoutesBridge.kt       (Kotlin native bridge)
  //   apps/mobile_android/android/.../MainActivity.kt           (registration)
  //   apps/watch_wear/.../RoutesBridge.kt                       (Kotlin parser)
  //   apps/watch_wear/.../RunViewModel.kt                       (consumer)
  //
  // See decisions.md § 64 for the design rationale.
  group('WearRoutesBridge cross-language wiring guards', () {
    test('Dart-side WearRoutesBridge declares the channel name + path keys',
        () {
      final src =
          File('lib/wear_routes_bridge.dart').readAsStringSync();
      expect(src, contains("MethodChannel('run_app/wear_routes')"),
          reason: 'channel name must match the Kotlin handler in '
              'android/app/src/main/kotlin/com/threkir/app/WearRoutesBridge.kt — '
              'if you rename it, rename it in BOTH files in the same commit');
      expect(src, contains("'routes_json'"),
          reason: 'routes_json data-map key — must match the Kotlin '
              'WearRoutesBridge.kt writer AND the watch-side RoutesBridge.kt '
              'parser');
      expect(src, contains("'updated_at_ms'"),
          reason: 'updated_at_ms data-map key — drives the stale-push '
              'protection on the watch side');
      expect(src, contains('kMaxRoutesPerPush'),
          reason: 'the 50-route Wearable Data Layer 100 KB cap is '
              'load-bearing; do not remove the constant without a '
              'corresponding bump on the watch picker side');
    });

    test('Phone-side WearRoutesBridge.kt mirrors the Dart channel + path',
        () {
      final src = File(
              'android/app/src/main/kotlin/com/threkir/app/WearRoutesBridge.kt')
          .readAsStringSync();
      expect(src, contains('"run_app/wear_routes"'),
          reason: 'Kotlin channel name must match the Dart writer');
      expect(src, contains('"/saved_routes"'),
          reason: 'DataLayer path must match the watch-side RoutesBridge.kt — '
              "drift here means the watch's listener never fires");
      expect(src, contains('"routes_json"'),
          reason: 'routes_json data-map key must match BOTH the Dart '
              'writer and the watch parser');
      expect(src, contains('"updated_at_ms"'),
          reason: 'updated_at_ms data-map key must match the Dart writer '
              "AND the watch's stale-push gate");
      expect(src, contains('PutDataMapRequest'),
          reason: 'the bridge must use PutDataMapRequest, not raw '
              'PutDataRequest — DataMap fields are how the keys ship');
    });

    test('MainActivity.kt registers the WearRoutesBridge in '
        'configureFlutterEngine', () {
      // The bridge is constructed in configureFlutterEngine alongside
      // WearAuthBridge + RunNotificationBridge. Without this line
      // the MethodChannel handler never registers and every push
      // from the Dart side throws MissingPluginException (which
      // the Dart bridge swallows — the user sees no error, but
      // the watch never gets updates).
      final src = File(
              'android/app/src/main/kotlin/com/threkir/app/MainActivity.kt')
          .readAsStringSync();
      expect(src, contains('WearRoutesBridge('),
          reason: 'MainActivity must construct WearRoutesBridge inside '
              'configureFlutterEngine; dropping the registration means '
              'every phone→watch push silently fails');
      expect(src, contains('flutterEngine.dartExecutor.binaryMessenger'),
          reason: 'the bridge needs the FlutterEngine binary messenger '
              'to bind its MethodChannel');
    });

    test('main.dart attaches WearRoutesBridge after Supabase init '
        'with the LocalRouteStore', () {
      // The bridge is wired in main.dart's post-Supabase
      // post-frame callback, alongside WearAuthBridge.attach. If
      // attach() is dropped, no LocalRouteStore changes fire the
      // push — the watch never sees the user's starred set.
      final src = File('lib/main.dart').readAsStringSync();
      expect(src, contains('WearRoutesBridge'),
          reason: 'main.dart must import + attach WearRoutesBridge — '
              'see the wear_auth_bridge import alongside it');
      expect(src, contains('.attach(routeStore)'),
          reason: 'WearRoutesBridge must be attached to the same '
              'LocalRouteStore that drives the routes screen — '
              "otherwise stars on the phone don't propagate");
    });

    test('pickRoutesForWatchPush + encodeRoutesForWatch are @visibleForTesting',
        () {
      // The extracted pure helpers are the testable seam — a future
      // refactor that inlines them back into _push must update the
      // tests in lockstep. Pin the @visibleForTesting attribute so
      // the helpers stay reachable from the test surface.
      final src =
          File('lib/wear_routes_bridge.dart').readAsStringSync();
      expect(src, contains('@visibleForTesting'),
          reason: 'pickRoutesForWatchPush + encodeRoutesForWatch must '
              'stay @visibleForTesting so the tests can reach them; '
              'inlining them back into _push without the annotation '
              'means a tests-go-stale situation');
      expect(src, contains('static List<Route> pickRoutesForWatchPush('),
          reason: 'extracted helper for the starred filter + cap');
      expect(src,
          contains('static List<Map<String, Object>> encodeRoutesForWatch('),
          reason: 'extracted helper for the wire-format encoding');
    });

    test('debounce window + Timer wiring stays intact', () {
      // Reason: a 250ms coalescing window catches star-storm + bulk
      // import bursts. Without it, every individual save() fires
      // a separate DataLayer push, wasting bandwidth + watch
      // battery. Three load-bearing pieces:
      //
      //   1. The static `kPushDebounceWindow` constant — settable
      //      via @visibleForTesting so tests can run with zero
      //      delay.
      //   2. A `_pendingPush: Timer?` field that the listener
      //      restarts on each notification.
      //   3. detach() cancelling the timer so an in-flight
      //      debounce doesn't fire AFTER the bridge stops.
      //
      // The first push from attach() is INTENTIONALLY not
      // debounced — a newly-paired watch sees data immediately.
      final src =
          File('lib/wear_routes_bridge.dart').readAsStringSync();
      expect(src, contains('static Duration kPushDebounceWindow'),
          reason: 'debounce window constant must exist as a static '
              'so tests + future ops tuning can override it');
      expect(src, contains('Timer? _pendingPush'),
          reason: 'pending debounce Timer must exist; without it '
              "the bridge can't coalesce rapid bursts");
      expect(src, contains('_pendingPush?.cancel()'),
          reason: 'detach() must cancel the pending timer or a '
              'fire-after-detach race produces ghost pushes');
      expect(src, contains('_scheduleDebouncedPush'),
          reason: 'the listener must route through the debounce '
              'scheduler — calling _push directly would skip '
              'coalescing entirely');
      // The initial push from attach() goes through _push directly,
      // NOT through the scheduler — a fresh watch should see data
      // immediately, not 250ms late.
      expect(
        src,
        contains(RegExp(
          r'store\.addListener\(_listener!\);\s*_push\(store\)',
        )),
        reason: 'attach must call _push directly for the initial '
            'sync (not _scheduleDebouncedPush) so a freshly '
            'paired watch sees state without delay',
      );
    });

    test('Protomaps tile-URL override: all three platforms agree on the '
        'same semantics', () {
      // Reason: web, mobile, and Wear OS each have their own
      // builder (`buildMapStyleUrl`, `resolveTileUrl`, `buildTileUrl`)
      // for choosing between the local-dev override and the
      // MapTiler fallback. The contract MUST be identical across
      // the three so a stray space in one platform's .env.local
      // doesn't behave differently from another. See
      // `decisions.md § 68`.

      // Web (TypeScript): map-style-url.ts uses `.trim()` +
      // length check.
      final webSrc =
          File('../web/src/lib/map-style-url.ts').readAsStringSync();
      expect(webSrc, contains('.trim()'),
          reason: 'web builder must trim the override before length-checking — '
              'otherwise whitespace in .env.local silently disables MapTiler');

      // Mobile (Dart): live_run_map.dart uses `.trim()` +
      // isNotEmpty.
      final mobileSrc =
          File('lib/widgets/live_run_map.dart').readAsStringSync();
      expect(mobileSrc, contains("env['TILE_URL_TEMPLATE']"),
          reason: 'mobile builder must read the canonical env var name');
      expect(mobileSrc, contains('.trim()'),
          reason: 'mobile builder must trim the override (May 2026 audit)');
      expect(mobileSrc, contains('isNotEmpty'));

      // Wear OS (Kotlin): TileSource.kt uses `.isNotBlank()`
      // (Kotlin's equivalent of trim-then-check-empty).
      final wearSrc = File(
              '../watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/ui/TileSource.kt')
          .readAsStringSync();
      expect(wearSrc, contains('template.isNotBlank()'),
          reason: 'Wear OS builder must use isNotBlank — equivalent '
              'of Dart trim-then-isNotEmpty');
      expect(wearSrc, contains('tileSourceEnabled('),
          reason: 'enabled-flag must be extracted as a testable helper, '
              'not inlined as a BuildConfig OR-chain');
    });

    test('Protomaps env-var documentation is consistent across '
        '.env.example files', () {
      // Reason: each app declares its own override env var with a
      // different name per `decisions.md § 68`. The names differ on
      // purpose, but every .env.example must document its variant
      // so a new contributor doesn't miss any.
      final webEnv = File('../web/.env.example').readAsStringSync();
      expect(webEnv, contains('PUBLIC_TILE_STYLE_URL='),
          reason: 'web .env.example must document the override');

      final mobileEnv = File('.env.example').readAsStringSync();
      expect(mobileEnv, contains('TILE_URL_TEMPLATE='),
          reason: 'mobile .env.example must document the override');

      final wearEnv = File(
        '../watch_wear/android/.env.example',
      ).readAsStringSync();
      expect(wearEnv, contains('PUBLIC_TILE_URL_TEMPLATE='),
          reason: 'Wear .env.example must document the override');

      // Cross-reference doc: each must point at the canonical
      // setup guide or the ADR. A future cleanup pass that loses
      // the link would orphan the env vars from their explanation.
      for (final entry in {
        'web': webEnv,
        'mobile': mobileEnv,
        'wear': wearEnv,
      }.entries) {
        expect(
          entry.value,
          anyOf(
            contains('protomaps_local_setup.md'),
            contains('decisions.md § 68'),
            contains('decisions.md#68'),
          ),
          reason: '${entry.key} .env.example must link to the setup '
              "guide or the ADR — otherwise the var sits unexplained",
        );
      }
    });

    test('Protomaps bootstrap script exists + is executable + has clean '
        'bash syntax + only real config', () {
      final script = File('../../bin/protomaps-dev.sh');
      expect(script.existsSync(), isTrue,
          reason: 'bin/protomaps-dev.sh must exist as the documented '
              'entry point in docs/protomaps_local_setup.md');

      // Permission bit — owner-exec is what makes
      // `bin/protomaps-dev.sh start` work without an explicit bash
      // prefix.
      final mode = script.statSync().modeString();
      expect(mode.contains('x'), isTrue,
          reason: 'script must be executable (`chmod +x`) — '
              "else `bin/protomaps-dev.sh start` errors with permission denied");

      final body = script.readAsStringSync();
      // Subcommand dispatch must include every documented command.
      // A future rewrite that drops one silently breaks the docs.
      for (final cmd in const ['fetch', 'start', 'stop', 'status',
        'logs', 'env']) {
        expect(body, contains('cmd_$cmd'),
            reason: 'subcommand `$cmd` must be implemented + dispatched');
      }

      // Pin the Docker image is a real tag (not the made-up v5.0.0
      // the May 2026 audit caught). `latest` is also forbidden —
      // a moving tag would silently break the schema below it.
      expect(body, contains('maptiler/tileserver-gl:v5.'),
          reason: 'Docker tag must be a real v5.x pin, not `latest` '
              "and not the audit's bogus v5.0.0");

      // Pin the bogus `build.protomaps.com/<region>.pmtiles` URL
      // doesn't sneak back. (It was wrong — Protomaps publishes
      // daily world builds, not per-region pre-builds.)
      expect(
        body,
        isNot(contains(RegExp(r'build\.protomaps\.com/[a-z-]+\.pmtiles'))),
        reason: 'Protomaps does not publish per-region .pmtiles '
            "pre-builds — the May 2026 audit removed the fake URL; "
            "use `pmtiles extract` from the world build instead",
      );

      // No accidental C-style comments — bash would try to execute
      // a leading `//` as a command. Caught twice during the May 2026
      // pass.
      expect(
        body,
        isNot(contains(RegExp(r'^\s*//', multiLine: true))),
        reason: 'lines starting with `//` (C-style comments) will fail '
            'as bash commands — use `#` for shell comments',
      );
    });

    test('LocalRunStore owner-tag stamping (offline-record contract)', () {
      // Reason: the headline "record without an account, sync
      // later" feature lives on a shared device too. Without the
      // owner tag, User A's runs would silently sync under User
      // B's account after a sign-out/sign-in. Three load-bearing
      // wires must stay intact:
      //
      //   1. `LocalRunStore` exposes a `currentUserIdProvider`
      //      setter so production can wire `() => api?.userId`.
      //   2. `save()` calls the provider + stamps the metadata
      //      when the userId is non-null + non-empty.
      //   3. `main.dart` wires the provider after the ApiClient
      //      lands.
      //   4. `SyncService._trySync` consults
      //      `filterRunsForCurrentUser` before pushing.
      //
      // See `docs/decisions.md § 67`.
      final storeSrc =
          File('lib/local_run_store.dart').readAsStringSync();
      expect(
        storeSrc,
        contains('String? Function()? currentUserIdProvider'),
        reason: 'LocalRunStore must expose currentUserIdProvider — '
            'without it, save() has no way to know who owns the run',
      );
      expect(
        storeSrc,
        contains(RegExp(r'currentUserIdProvider\?\.call\(\)')),
        reason: 'save() must invoke the provider on EACH save '
            '(not memoise) — otherwise sign-out + sign-in mid-session '
            'still stamps the stale userId',
      );
      expect(
        storeSrc,
        contains('_withCreatedByUserId'),
        reason: 'the stamping helper must exist so save() can produce '
            'a fresh Run with the owner tag without mutating input',
      );
      expect(
        storeSrc,
        contains('static Run withCreatedByUserId'),
        reason: 'public static for the SyncService to adopt untagged '
            'runs onto the current user (legacy / signed-out-at-save)',
      );

      final mainSrc = File('lib/main.dart').readAsStringSync();
      expect(
        mainSrc,
        contains('store.currentUserIdProvider = () => api?.userId'),
        reason: 'main.dart must wire the provider — without this, '
            'production saved runs never carry the tag and the '
            "filter can't differentiate User A's runs from User B's",
      );

      final syncSrc =
          File('lib/sync_service.dart').readAsStringSync();
      expect(
        syncSrc,
        contains('filterRunsForCurrentUser'),
        reason: 'SyncService must call the filter before invoking '
            'saveRunsBatch — otherwise the queue pushes foreign runs '
            'under the current user',
      );
    });

    test('payload-diff cache is wired in _push + reset on detach', () {
      // Reason: every LocalRouteStore.save() fires the listener,
      // including for mutations that don't affect the wire payload
      // (description edit, is_public toggle, tag add). Without the
      // diff cache the bridge wakes the watch's DataClient listener
      // on every such edit. Pin the production code keeps:
      //
      //   1. A `_lastPushedRoutesJson` field for the byte cache.
      //   2. An early-return when the encoded payload matches the
      //      cached value.
      //   3. A reset on detach so a re-attach always fires once.
      //   4. The cache update happens ONLY on successful push (a
      //      swallowed PlatformException must not poison the cache
      //      so the next attempt re-fires).
      final src =
          File('lib/wear_routes_bridge.dart').readAsStringSync();
      expect(src, contains('_lastPushedRoutesJson'),
          reason: 'diff cache field must exist; without it every '
              'LocalRouteStore.save fires a redundant DataLayer push');
      expect(src, contains('if (routesJson == _lastPushedRoutesJson) return'),
          reason: 'diff gate must short-circuit BEFORE the channel '
              'invocation — otherwise the gate is a no-op');
      expect(
        src,
        contains(
            RegExp(r'_lastPushedRoutesJson = null\s*;[\s\S]*?Future<void> _push'),
        ),
        reason: 'detach() must reset _lastPushedRoutesJson so a re-attach '
            'fires unconditionally',
      );
      // The cache update is INSIDE the try block, after the
      // channel.invoke await — so a thrown PlatformException
      // skips the assignment. Pin the order.
      expect(
        src.indexOf("_lastPushedRoutesJson = routesJson"),
        greaterThan(src.indexOf("await _channel.invokeMethod")),
        reason: 'cache must be updated AFTER the channel invoke '
            'succeeds — otherwise a swallowed PlatformException '
            'leaves the cache claiming we sent something that '
            'never landed',
      );
    });
  });

  // ---- Cross-language fixture path guards ------------------------------
  group('Wear routes wire-format fixture', () {
    test('canonical fixture lives at fixtures/wear_routes_payload.json', () {
      // The fixture path is referenced by BOTH the Dart test
      // (apps/mobile_android/test/wear_routes_fixture_test.dart)
      // AND the Kotlin test (apps/watch_wear/.../WearRoutesFixtureTest.kt).
      // Moving the file silently skips both — pin the canonical
      // path here.
      final f = File('../../fixtures/wear_routes_payload.json');
      expect(f.existsSync(), isTrue,
          reason: 'fixture must live at ${f.absolute.path} so both '
              'platform tests can read it');
    });

    test('fixture declares the three contract keys the tests rely on', () {
      final f = File('../../fixtures/wear_routes_payload.json');
      final body = f.readAsStringSync();
      expect(body, contains('"input_routes"'),
          reason: 'Dart side reads input_routes to feed the encoder');
      expect(body, contains('"expected_payload_json"'),
          reason: 'wire shape — both the Dart side asserts the encoder '
              'produces this AND the Kotlin side parses this');
      expect(body, contains('"expected_parsed_routes"'),
          reason: 'Kotlin side asserts parseRoutesJson produces this '
              'from expected_payload_json');
    });
  });
}
