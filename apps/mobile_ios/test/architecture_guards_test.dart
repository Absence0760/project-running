// Guard-rail tests that pin the mobile app's efficiency + layering
// invariants in place. Each test parses a source file as text and asserts
// a pattern is (or isn't) present, with a **why** comment explaining the
// rule so a future editor can decide whether it's safe to break.
//
// When one of these fails, it means a recent change reversed an
// optimization or broke a layering rule we deliberately codified. Read
// the reason before blindly updating the test.

import 'dart:convert';
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

/// The body of every `} catch (...) { ... }` in [body], brace-matched so a
/// nested block inside a catch does not truncate it.
List<String> _catchBlocks(String body) {
  final out = <String>[];
  for (final m in RegExp(r'\}\s*catch\s*\([^)]*\)\s*\{').allMatches(body)) {
    final start = m.end;
    var depth = 1;
    var i = start;
    while (depth > 0 && i < body.length) {
      if (body[i] == '{') depth++;
      if (body[i] == '}') depth--;
      i++;
    }
    out.add(body.substring(start, i - 1));
  }
  return out;
}

/// [body] with every `try { ... } catch (...) { ... }` span removed, so what
/// is left is the code that runs with no wrapper around it.
String _withoutTryCatchBlocks(String body) {
  final buf = StringBuffer();
  var cursor = 0;
  while (true) {
    final t = body.indexOf('try {', cursor);
    if (t < 0) {
      buf.write(body.substring(cursor));
      return buf.toString();
    }
    buf.write(body.substring(cursor, t));
    var i = body.indexOf('{', t);
    var depth = 0;
    while (i < body.length) {
      if (body[i] == '{') depth++;
      if (body[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    final catchMatch =
        RegExp(r'^\s*catch\s*\([^)]*\)\s*\{').firstMatch(body.substring(i + 1));
    if (catchMatch == null) {
      cursor = i + 1;
      continue;
    }
    var j = i + 1 + catchMatch.end - 1;
    depth = 0;
    while (j < body.length) {
      if (body[j] == '{') depth++;
      if (body[j] == '}') {
        depth--;
        if (depth == 0) break;
      }
      j++;
    }
    cursor = j + 1;
  }
}

void main() {
  group('run_screen.dart', () {
    late String source;
    setUpAll(() {
      source = File('lib/screens/run_screen.dart').readAsStringSync();
    });

    test('turn-cue announced state is cleared at the start of every recording',
        () {
      // TurnCueAnnouncer latches each fired band for its lifetime, and the
      // announcer is only rebuilt when the SELECTED ROUTE changes — so without
      // a per-recording reset a second run over the same route announces
      // nothing at all (the repeated-loop / backyard-ultra case). _begin() is
      // the one path every recording funnels through.
      final begin = _extractMethodBody(source, r'Future<void> _begin\(\) async \{');
      expect(
        begin.contains('_turnAnnouncer?.reset()'),
        isTrue,
        reason: 'every recording must start from a cleared announced-turn set',
      );
    });

    test('a foreground-only location grant is disclosed when it costs the run, '
        'never at run start', () {
      // Reason: Android's first-run dialog only ever grants "While using the
      // app"; "Allow all the time" is a separate trip to Settings. The
      // recorder used to REFUSE that grant, so the default Android runner got
      // no position stream at all — the live map sat on "Waiting for GPS" for
      // the whole run, distance stayed 0, and the run saved as indoor. GPS now
      // records under it (#784). The disclosure that used to fire at _begin
      // read as "recording is broken" at the exact moment nothing was wrong;
      // it belongs on the real event — the runner returning to a recording run
      // that received no fix while the app was off screen (#785).
      final begin = _extractMethodBody(source, r'Future<void> _begin\(\) async \{');
      expect(
        begin.contains('_notifyBackgroundLocationLimited()'),
        isFalse,
        reason: 'run start must not warn about background permission — '
            'nothing has gone wrong yet',
      );
      final lifecycle = _extractMethodBody(
        source,
        r'void didChangeAppLifecycleState\(AppLifecycleState state\) \{',
      );
      expect(
        lifecycle.contains('shouldDiscloseBackgroundLocationLimit('),
        isTrue,
        reason: 'the disclosure must be driven by the app-lifecycle event and '
            'gated on the evidenced-gap decision',
      );
      expect(
        lifecycle.contains('_notifyBackgroundLocationLimited()'),
        isTrue,
        reason: 'the disclosure must reach the runner as a banner, not be '
            'dropped on the floor',
      );
      // L4: the disclosure is auxiliary to recording and carries its own
      // catch, so nothing in it can reach the recording state machine.
      expect(
        lifecycle.contains('catch'),
        isTrue,
        reason: 'the lifecycle disclosure path must be L4-isolated',
      );
      // The disclosure is a warning about a recording run — it must never
      // reuse the GPS-unavailable path, which describes a run with no fixes.
      final notify = _extractMethodBody(
        source,
        r'void _notifyBackgroundLocationLimited\(\)\s*\{',
      );
      expect(
        notify.contains('_notifyGpsUnavailable('),
        isFalse,
        reason: 'a limited grant still records — it is not GPS unavailable',
      );
    });

    test('auto-live-share hook is opt-in, L4-isolated, and duplicate-safe', () {
      // Reason: docs/features/safety.md — the auto_live_share device pref (and
      // a manual "Share live link") start a broadcast at _begin(). Three
      // load-bearing properties: (1) fail-closed opt-in — the gate fires only
      // when the pref is on OR the runner explicitly asked to share, both
      // default-false; (2) a manual pre-GO share must not double-begin
      // (broadcasterActive guard); (3) the whole thing is fire-and-forget with
      // its own error path so a share failure can never touch L0/L1 recording.
      //
      // The gate lives in the pure, @visibleForTesting
      // shouldStartBroadcastOnRunStart helper (unit-tested in
      // run_screen_broadcast_test.dart). Pin its exact formula so the opt-in +
      // duplicate-safe semantics can't silently drift.
      expect(
        source.contains(
            '(autoLiveShareEnabled || liveShareRequested) && !broadcasterActive'),
        isTrue,
        reason: 'the run-start gate must fire only on the pref OR an explicit '
            'share request, and must skip an already-attached broadcaster',
      );
      // _attachRecordingSideEffects routes the run-start hook through that gate
      // and starts the broadcast fire-and-forget in its own catch path.
      final sideEffects = _extractMethodBody(
        source,
        r'void _attachRecordingSideEffects\(\)\s*\{',
      );
      final gateIdx = sideEffects.indexOf('shouldStartBroadcastOnRunStart(');
      expect(
        gateIdx,
        greaterThan(-1),
        reason: 'the _begin() hook must gate through '
            'shouldStartBroadcastOnRunStart',
      );
      final hookWindow = sideEffects.substring(gateIdx, gateIdx + 500);
      expect(
        hookWindow.contains('unawaited(_startLiveBroadcast()'),
        isTrue,
        reason: 'the auto share is fire-and-forget — _begin() must not '
            'await the network before starting the clock',
      );
      expect(
        hookWindow.contains('catchError'),
        isTrue,
        reason: 'the auto share needs its own error path (L4) so a '
            'failure cannot surface as an unhandled zone error mid-start',
      );
      // The manual share path reuses the same broadcast starter, so the
      // stub/broadcaster semantics cannot drift between the two.
      final shareBody = _extractMethodBody(
        source,
        r'Future<void> _shareLiveLink\(\) async\s*\{',
      );
      expect(
        shareBody.contains('_startLiveBroadcast()'),
        isTrue,
        reason: '_shareLiveLink must route through _startLiveBroadcast',
      );
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
      // Reason: the layering rule (docs/architecture/conventions.md § Layered
      // resilience, docs/features/run_recording.md § Layering) says L0 (clock)
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

    test('every L4 catch in _onSnapshot absorbs and reports the failure', () {
      // Reason: the sibling guard above counts try/catch PAIRS, which is
      // blind to what the catch does. A `catch (e) { rethrow; }` or an empty
      // `catch (e) {}` keeps the count intact while defeating the layering
      // rule outright — the first swallows nothing and kills every later
      // effect in the snapshot pipeline, the second hides an auxiliary that
      // has stopped working with no trace in the log. Both are exactly the
      // shape a "clean up the noisy debugPrints" edit produces.
      //
      // The contract is stated in CLAUDE.md and
      // docs/architecture/conventions.md § Layered resilience: wrap each
      // auxiliary effect in its own try/catch plus a debugPrint, never
      // swallow silently.
      final body = _extractMethodBody(
        source,
        r'void _onSnapshot\(RunSnapshot snapshot\)\s*\{',
      );
      final blocks = _catchBlocks(body);
      expect(
        blocks.length,
        greaterThanOrEqualTo(7),
        reason: 'expected one catch per L4 effect in _onSnapshot; found '
            '${blocks.length}. If the effects were collapsed under a shared '
            'catch, re-split them.',
      );
      for (var i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        expect(
          block.trim(),
          isNotEmpty,
          reason: 'catch #$i in _onSnapshot is empty — an auxiliary that '
              'has silently stopped working leaves no trace at all.',
        );
        expect(
          block.contains('debugPrint'),
          isTrue,
          reason: 'catch #$i in _onSnapshot does not report the failure. '
              'Every L4 catch must debugPrint what it absorbed:\n$block',
        );
        expect(
          block.contains('rethrow'),
          isFalse,
          reason: 'catch #$i in _onSnapshot rethrows, so the throw escapes '
              'into the snapshot pipeline and every LATER effect stops '
              'running. The layering rule is that an L4 failure is '
              'absorbed where it happens:\n$block',
        );
      }
    });

    test('nothing runs unguarded between the L0/L1 publish and the end', () {
      // Reason: the ordering guard proves the publish comes before the first
      // try, and the catch guards prove each effect is isolated. Neither
      // sees a BARE statement dropped between two try-blocks — a new
      // `_someService.notify(...)` added without a wrapper, say — which
      // throws straight out of _onSnapshot and skips every effect below it.
      // The only two things allowed out here are the publish itself and the
      // debug-only mirror assert.
      final body = _extractMethodBody(
        source,
        r'void _onSnapshot\(RunSnapshot snapshot\)\s*\{',
      );
      final publishAt = body.indexOf('_statsNotifier.value = _LiveStats(');
      expect(publishAt, greaterThan(-1));
      final tail = _withoutTryCatchBlocks(body.substring(publishAt));
      final stray = tail
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('//'))
          .toList();
      // Everything left has to belong to the publish expression or the
      // assert; both end before the first effect and neither can throw in
      // release (the assert is stripped).
      final allowed = RegExp(
        r'^(_statsNotifier\.value = _LiveStats\(|[a-zA-Z_]+: [^;]+,|\);|'
        r'assert\(\(\) \{|final v = _statsNotifier\.value;|'
        r'return v\.|v\.|identical\(|\}\(\),)',
      );
      final unexpected =
          stray.where((l) => !allowed.hasMatch(l)).toList();
      expect(
        unexpected,
        isEmpty,
        reason: 'these statements sit between the L0/L1 publish and the end '
            'of _onSnapshot without a try/catch, so a throw in one skips '
            'every L4 effect below it: $unexpected',
      );
    });

    test('_formattedElevation reads the accumulator, not a loop', () {
      // Reason: was O(n) over the full track on every build. For a 60-min
      // run (~3600 waypoints) that's millions of iterator steps per
      // minute. Now maintained incrementally in _onSnapshot.
      final match = RegExp(
        r"String get _formattedElevation =>\s*'\$\{_elevationGain\.gainMetres\.round\(\)\}';",
      ).firstMatch(source);
      expect(
        match,
        isNotNull,
        reason: '_formattedElevation must read the incrementally-updated '
            'ElevationGainAccumulator. Do not iterate _track here.',
      );
    });

    test('live elevation gain goes through the shared gated contract', () {
      // Reason: the live counter used to sum every positive altitude delta
      // with no noise band and no dropout carry, so a flat 10K read ~1,200 m
      // on the run screen and ~38 m on the run-detail screen minutes later.
      // computeElevationGain / ElevationGainAccumulator in route_simplify.dart
      // are the ONE elevation-gain contract (3 m gate + dropout carry); the
      // screen must feed the accumulator, not re-derive the arithmetic.
      final body = _extractMethodBody(
        source,
        r'void _onSnapshot\(RunSnapshot snapshot\)\s*\{',
      );
      expect(
        body,
        contains('_elevationGain.add('),
        reason: '_onSnapshot must append new waypoints to the shared '
            'ElevationGainAccumulator.',
      );
      expect(
        body.contains('_elevationGainMetres +='),
        isFalse,
        reason: 'No hand-rolled elevation sum in _onSnapshot — an ungated '
            'copy re-introduces phantom vert on a flat run.',
      );
      expect(
        source,
        contains("import '../route_simplify.dart';"),
        reason: 'The gate constant and the accumulator live in '
            'route_simplify.dart; do not fork a second 3 m threshold here.',
      );
    });

    test('split ticks and race phases read the resolved display distance', () {
      // Reason: an indoor / treadmill run never gets a GPS fix, so the
      // recorder's own distance stays 0 for the entire session while
      // _displayDistanceMetres climbs off the pedometer. Reading the raw
      // mirror field at these two sites meant no split banner, no split
      // voice cue and no race-phase transition for the whole run, while the
      // screen, the lock screen and the saved run all showed ~10 km.
      final body = _extractMethodBody(
        source,
        r'void _onSnapshot\(RunSnapshot snapshot\)\s*\{',
      );
      expect(
        body.contains('UnitFormat.activityTicks(_distanceMetres'),
        isFalse,
        reason: 'Split ticks must be counted off _displayDistanceMetres.',
      );
      expect(
        body.contains('phaseAt(_phasePlan, _distanceMetres)'),
        isFalse,
        reason: 'Race-phase membership must use _displayDistanceMetres.',
      );
      expect(
        body.contains('averagePaceSecPerKm(_distanceMetres'),
        isFalse,
        reason: 'The split cue average pace must use the same distance the '
            'split itself was counted from.',
      );
      expect(
        RegExp(r'phaseAt\(_phasePlan, phaseDistance\)').hasMatch(body),
        isTrue,
        reason: 'The phase block should resolve its distance once through '
            '_displayDistanceMetres.',
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

    test('_stop saves the run BEFORE clearing the in-progress recovery file',
        () {
      // Reason: the in_progress.json recovery file is the safety net for
      // the window between "user tapped stop" and "run is on disk in
      // its final form". The previous order was clearInProgress() →
      // setState(finished) → await audio cue → save(run); if the OS
      // killed the process during the audio cue (Samsung Freecess,
      // OOM, force-stop, user backgrounded the app), BOTH the
      // in_progress.json AND the saved run file were gone — the run
      // was lost forever. Pinned the new order so a future refactor
      // can't quietly reintroduce the data-loss window.
      final body = _extractMethodBody(
        source,
        r'Future<void> _stop\(\)\s*async\s*\{',
      );
      final saveIdx = body.indexOf('widget.runStore.save(');
      final clearIdx = body.indexOf('widget.runStore.clearInProgress(');
      expect(saveIdx, greaterThan(-1),
          reason: '_stop must call runStore.save(run)');
      expect(clearIdx, greaterThan(-1),
          reason: '_stop must call runStore.clearInProgress()');
      expect(
        saveIdx,
        lessThan(clearIdx),
        reason: 'runStore.save MUST appear before runStore.clearInProgress '
            'in _stop. The reverse order opens a data-loss window: if '
            'the process is killed between clearInProgress and save, '
            'both the in_progress.json recovery file AND the saved run '
            'file are gone — that lost a real user\'s run in May 2026.',
      );
    });

    test('_stop does not gate the local save on `mounted`', () {
      // Reason: paired guarantee with the save-before-clear ordering.
      // The recorder is already stopped and the data lives in memory
      // — if the user navigates away or the framework unmounts the
      // widget during stop (multi-window mode, push notification
      // takeover, configuration change), the save still needs to run.
      // The previous code did `if (!mounted) return;` between
      // clearInProgress() and save(); with the in-progress file
      // already deleted, the early bail evaporated the run. The new
      // order has save() FIRST (no mounted check), so a navigation
      // can't lose the run.
      final body = _extractMethodBody(
        source,
        r'Future<void> _stop\(\)\s*async\s*\{',
      );
      final saveIdx = body.indexOf('widget.runStore.save(');
      // Find every `if (!mounted) return` (or `if (!mounted)`) that
      // appears BEFORE the save call. There must be zero — the save
      // must be unconditional on widget mount state.
      final beforeSave = body.substring(0, saveIdx);
      expect(
        RegExp(r'if\s*\(\s*!\s*mounted\s*\)\s*return').hasMatch(beforeSave),
        isFalse,
        reason: 'No `if (!mounted) return;` may appear before the '
            'runStore.save call in _stop. The recorder is stopped and '
            'the data is in memory — an unmount must not evaporate the '
            'run before it lands on disk.',
      );
    });

    test('_stop is guarded against re-entry before it awaits the recorder',
        () {
      // Reason: _stop() awaits the recorder, the local save, and the cloud
      // push, and never nulls _recorder. A second trigger — the lock-screen
      // Stop action racing the on-screen hold-to-stop, or a cold-start Stop
      // intent flushed after the run already finished — would otherwise
      // re-run the whole path: a duplicate runStore.save / clearInProgress,
      // and worst of all a duplicate cloud saveRun + race-result submission.
      // The guard (an early return on a _stopRequested flag) must sit BEFORE
      // the `await ... .stop()` so the second caller bails before any await
      // yields the event loop to it.
      final body = _extractMethodBody(
        source,
        r'Future<void> _stop\(\)\s*async\s*\{',
      );
      final guardIdx = body.indexOf('_stopRequested');
      final stopAwaitIdx = body.indexOf('.stop()');
      expect(guardIdx, greaterThan(-1),
          reason: '_stop must consult a _stopRequested re-entrancy guard');
      expect(stopAwaitIdx, greaterThan(-1),
          reason: '_stop must await the recorder stop()');
      expect(
        guardIdx,
        lessThan(stopAwaitIdx),
        reason: 'The _stopRequested guard MUST appear before the awaited '
            'recorder .stop() in _stop. A guard placed after the first '
            'await lets a racing Stop (lock-screen vs hold-to-stop, or a '
            'flushed cold-start intent) double-save + double-push the run.',
      );
      // The guard must also be reset on discard so the NEXT run can stop.
      final discardBody = _extractMethodBody(source, r'void _discard\(\)\s*\{');
      expect(
        discardBody,
        contains('_stopRequested = false'),
        reason: '_discard must clear _stopRequested so a subsequent run is '
            'stoppable; otherwise the second run can never be stopped.',
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
        r'class _HoldToStopButtonState extends State<HoldToStopButton>',
      );
      // _extractMethodBody slices to the next top-level `}`, but
      // class bodies span more than the build method we care about.
      // Just regex the build() body for the Listener and its
      // behavior arg in one go.
      final m = RegExp(
        r'Listener\(\s*behavior:\s*HitTestBehavior\.opaque',
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

  group('store write serialisation (§ 828)', () {
    late String runStore;
    late String routeStore;
    setUpAll(() {
      runStore = File('lib/local_run_store.dart').readAsStringSync();
      routeStore = File('lib/local_route_store.dart').readAsStringSync();
    });

    // Every entry point that mutates a store DIRECTORY runs on the shared
    // per-directory chain. A new one that forgets reopens the delete-vs-save
    // race: the delete removes `<id>.json`, the in-flight save's rename puts
    // it straight back, and memory agrees with the resurrected file.
    const runEntryPoints = [
      r'Future<Run> save\(Run run\)',
      r'Future<void> saveFromRemote\(Run run\)',
      r'Future<void> saveManyFromRemote\(Iterable<Run> runs\)',
      r'Future<void> update\(Run updated\)',
      r'Future<void> delete\(String runId\)',
      r'Future<void> deleteMany\(Iterable<String> runIds\)',
      r'Future<void> markSynced\(String runId\)',
      r'Future<void> markManySynced\(Iterable<Run> pushed\)',
      r'Future<void> clearPendingRemoteDelete\(String runId\)',
    ];
    for (final signature in runEntryPoints) {
      test('LocalRunStore.$signature is serialised', () {
        final match = RegExp('$signature\\s*=>[^;]*;').firstMatch(runStore);
        expect(match, isNotNull,
            reason: 'entry point moved — update this guard, and keep it on '
                'the chain');
        expect(match!.group(0), contains('_serialised'));
      });
    }

    const routeEntryPoints = [
      r'Future<void> markRouteSynced\(String routeId\)',
      r'Future<void> markManyRoutesSynced\(Iterable<String> routeIds\)',
      r'Future<void> tagRoutesOwner\(Iterable<String> routeIds, String owner\)',
      r'Future<void> delete\(String routeId\)',
      r'Future<void> deleteMany\(Iterable<String> routeIds\)',
      r'Future<void> pinOffline\(String routeId\)',
      r'Future<void> unpinOffline\(String routeId\)',
      r'Future<void> clearPendingRemoteDelete\(String routeId\)',
    ];
    for (final signature in routeEntryPoints) {
      test('LocalRouteStore.$signature is serialised', () {
        final match = RegExp('$signature\\s*=>[^;]*;').firstMatch(routeStore);
        expect(match, isNotNull,
            reason: 'entry point moved — update this guard, and keep it on '
                'the chain');
        expect(match!.group(0), contains('_serialised'));
      });
    }

    // The other half of the contract, and the one that matters more: the L1
    // recording path must NEVER join the chain. It owns `in_progress.json`,
    // which nothing chained touches, and a tick queued behind a directory
    // walk is a durability gap during a live run — a queued write that never
    // lands is worse than the race the chain closes.
    test('the in-progress recording path stays off the chain', () {
      for (final signature in [
        r'Future<void> saveInProgress\(Run run\)\s*async\s*\{',
        // The public `clearInProgress` is now a thin wrapper that publishes
        // its own future for `debugInProgressSettled` (decisions § 1012); the
        // body that could reach the chain is the private one.
        r'Future<void> _clearInProgress\(\)\s*async\s*\{',
        r'Future<Run\?> loadInProgress\(\)\s*async\s*\{',
      ]) {
        expect(_extractMethodBody(runStore, signature), isNot(contains('_serialised')),
            reason: 'an L1 recording write must not queue behind a directory '
                'operation');
      }
    });

    // Two locking schemes in one file is how the next race gets written. The
    // FileLock these stores held over their sidecar merges excluded nothing:
    // POSIX record locks are owned by the process, so a second handle in the
    // same process — the WorkManager isolate it named included — acquires it
    // too (§ 829).
    test('no store re-introduces a second locking scheme', () {
      for (final source in [runStore, routeStore]) {
        final code = source
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('///'))
            .join('\n');
        expect(code, isNot(contains('FileLock')));
      }
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
        r'Future<void> _markSynced\(String runId\)\s*async\s*\{',
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

    test('save offloads the terminal full-track encode to compute()', () {
      // Reason: the terminal save() serialises the ENTIRE Run.toJson()
      // (full multi-day track) — for a 150k-300k-point ultra a synchronous
      // jsonEncode on the UI isolate froze the app at the exact moment the
      // runner (or their pacer) finished. Unlike saveInProgress this path
      // never got the compute() offload the other heavy encode/decode paths
      // have. Must encode off-isolate; a bare writeJsonAtomic(...) here
      // encodes on the UI thread and reintroduces the freeze.
      final body = _extractMethodBody(
        source,
        r'Future<Run> _save\(Run run\)\s*async\s*\{',
      );
      expect(
        body,
        contains('compute('),
        reason: 'save must offload the full-Run jsonEncode to an isolate '
            'so finishing a huge track does not freeze the UI.',
      );
      expect(
        body.contains('writeJsonAtomic('),
        isFalse,
        reason: 'save must not call writeJsonAtomic (which jsonEncodes on '
            'the UI isolate) — encode via compute() then writeStringAtomic.',
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

    test('_loadAll takes the index-first windowed fast path', () {
      // Reason: the durable summary-index redesign exists so cold-load reads
      // ONE index file and hydrates only the resident window — not N per-run
      // files. The full directory walk (`Future.wait` above) is the
      // self-heal / migration FALLBACK, taken only when the index is missing
      // or drifted. A change that drops `_readIndex` from `_loadAll` reverts
      // the windowing and silently reintroduces the O(n) cold-load.
      final body = _extractMethodBody(
        source,
        r'Future<void> _loadAll\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('_readIndex'),
        reason: '_loadAll must read index.json first (the windowed fast path) '
            'and fall back to the full walk only on a missing/drifted index.',
      );
      expect(
        body,
        contains('residentWindow'),
        reason: '_loadAll must hydrate only the resident window on the fast '
            'path (newest residentWindow ∪ all unsynced).',
      );
    });

    test('save() stamps metadata.last_modified_at', () {
      // Reason: sync uses `metadata.last_modified_at` for newer-wins
      // conflict resolution (see saveFromRemote). A local save that
      // doesn't stamp can be silently clobbered by the next remote pull
      // if the remote carries a later timestamp from a different device.
      final body = _extractMethodBody(
        source,
        r'Future<Run> _save\(Run run\)\s*async\s*\{',
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
        r'Future<void> _update\(Run updated\)\s*async\s*\{',
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
        r'Future<void> _saveFromRemote\(Run run\)\s*async\s*\{',
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

  group('local stores use crash-atomic writes (writeJsonAtomic)', () {
    // Reason: a bare `file.writeAsString(...)` truncates the target to
    // zero bytes before streaming the new content, so a process death
    // mid-write leaves a partial / empty file that jsonDecode rejects on
    // the next cold-start — the record silently vanishes. Every record +
    // sidecar write must go through writeJsonAtomic (temp + flush +
    // atomic rename) from core_models. The in-progress NDJSON append path
    // (_appendInProgressLine, FileMode.writeOnlyAppend) is separately
    // crash-safe and intentionally exempt.
    // No store file may use a bare truncate-then-write writeAsString. The
    // gear / gym / food stores now share the OfflineSyncStore base for the
    // actual persist + rewrite, so writeJsonAtomic lives there (decisions
    // §122); run / route + the base itself still call it directly.
    const noBareWriteStores = [
      'lib/local_run_store.dart',
      'lib/watch_ingest_queue.dart',
      'lib/local_route_store.dart',
      'lib/local_gear_store.dart',
      'lib/local_gym_store.dart',
      'lib/local_food_store.dart',
      'lib/local_routine_store.dart',
      'lib/offline_sync_store.dart',
    ];
    for (final path in noBareWriteStores) {
      test('$path has no bare writeAsString', () {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('writeAsString('),
          isFalse,
          reason: '$path must persist via writeJsonAtomic / '
              'writeStringAtomic, not a truncate-then-write writeAsString.',
        );
      });
    }

    // The per-row stores persist via the crash-atomic helper, directly
    // (run / route) or through the shared OfflineSyncStore base.
    for (final path in [
      'lib/local_run_store.dart',
      'lib/local_route_store.dart',
      'lib/offline_sync_store.dart',
    ]) {
      test('$path uses the crash-atomic helper writeJsonAtomic', () {
        final source = File(path).readAsStringSync();
        expect(source.contains('writeJsonAtomic('), isTrue,
            reason: '$path should use the crash-atomic helper.');
      });
    }

    test('OfflineSyncStore.rewriteAll writes new files before deleting orphans',
        () {
      // Reason: the old per-store _rewriteAll deleted every file then
      // rewrote — a crash in the gap emptied the directory and lost
      // unsynced pendingCreate rows. The fixed order is write-all-then-
      // prune. The gear / gym / food stores share this single base impl
      // now (decisions §122).
      // The public `rewriteAll` is a thin wrapper that puts the transition on
      // the store's serial write chain; `_rewriteAll` holds the ordering this
      // guard is about. Both are named, so a rename can't quietly vacate it.
      final source = File('lib/offline_sync_store.dart').readAsStringSync();
      expect(
        RegExp(r'Future<void> rewriteAll\(\)[^}]*_serialised\(_rewriteAll\)')
            .hasMatch(source),
        isTrue,
        reason: 'rewriteAll must delegate to _rewriteAll on the write chain — '
            'the body this guard reads lives there.',
      );
      final body = _extractMethodBody(
        source,
        r'Future<void> _rewriteAll\(\)\s*async\s*\{',
      );
      final firstWrite = body.indexOf('writeJsonAtomic(');
      final firstDelete = body.indexOf('.delete()');
      expect(firstWrite, greaterThanOrEqualTo(0),
          reason: 'rewriteAll must write via writeJsonAtomic');
      expect(firstDelete, greaterThanOrEqualTo(0),
          reason: 'rewriteAll must prune orphaned files');
      expect(firstWrite, lessThan(firstDelete),
          reason: 'rewriteAll must write the new state BEFORE deleting '
              'any file — never empty the directory first.');
      expect(
        body.contains('deleteSync()'),
        isFalse,
        reason: 'rewriteAll should not use a catch-free synchronous '
            'delete for the prune phase.',
      );
    });
  });

  group('share-button consent before flipping is_public', () {
    test('run_detail_screen._shareRun gates makeRunPublic on a confirm dialog',
        () {
      // Reason: a casual user tapping Share on a freshly-recorded run
      // used to silently flip is_public — no warning, no copy
      // explaining that the share link exposes the full track
      // (incl. home / work coords) to anyone with the URL. Privacy-
      // zone default is OFF (decisions §33). The fix requires the
      // share path to call a `_confirmMakePublic` dialog before
      // reaching makeRunPublic. Catches a regression that removes
      // the gate.
      final source =
          File('lib/screens/run_detail_screen.dart').readAsStringSync();
      expect(
        source,
        contains('_confirmMakePublic'),
        reason: '_shareRun must route through a _confirmMakePublic '
            'dialog before calling api.makeRunPublic. See decisions §33.',
      );
      expect(
        source,
        contains('runDetailMakePublicTitle'),
        reason: 'The consent dialog title is the canonical surface a '
            'regression would mangle; pin the localized key (the English '
            'copy now lives in the ARB catalogues).',
      );
      // makeRunPublic must NOT appear ahead of the dialog gate. The
      // gate-then-call ordering: _confirmMakePublic completes first,
      // then makeRunPublic. Both names must appear; ordering checked
      // by line index — if makeRunPublic appears at any line BEFORE
      // _confirmMakePublic, the regression is back.
      final confirmIdx = source.indexOf('_confirmMakePublic');
      final makePublicIdx = source.indexOf('api.makeRunPublic');
      expect(makePublicIdx > confirmIdx, isTrue,
          reason: 'api.makeRunPublic must NOT precede _confirmMakePublic '
              'in source order — that would mean the call site is back '
              'to flipping is_public ahead of the consent dialog.');
    });

    test('run_screen keeps makeRunPublic behind the post-live-share dialog',
        () {
      // Reason (issue #664): the live-broadcast stop path used to call
      // makeRunPublic unconditionally, so a runner who shared a live
      // link FOR SAFETY (incl. the Settings → Safety auto-live-share
      // pref) had every such run left permanently public with no
      // consent step — bypassing exactly the dialog the guard above
      // pins on run_detail. The fix confines makeRunPublic to
      // _resolvePostLiveVisibility, downstream of the keep-public
      // AlertDialog whose affirmative action is the ONLY path to it.
      final source =
          File('lib/screens/run_screen.dart').readAsStringSync();
      expect(source, contains('_resolvePostLiveVisibility'),
          reason: 'the stop path must resolve post-live visibility '
              'explicitly rather than re-asserting is_public.');
      expect(source, contains('runLiveShareEndedTitle'),
          reason: 'the keep-public dialog is the consent surface; pin '
              'its localized title key.');
      final dialogIdx = source.indexOf('runLiveShareEndedTitle');
      final makePublicIdx = source.indexOf('api!.makeRunPublic');
      expect(makePublicIdx, greaterThanOrEqualTo(0),
          reason: 'the explicit keep-public choice still calls '
              'makeRunPublic (inside _resolvePostLiveVisibility).');
      expect(makePublicIdx > dialogIdx, isTrue,
          reason: 'api.makeRunPublic must sit AFTER the keep-public '
              'dialog in _resolvePostLiveVisibility — earlier means the '
              'unconditional stop-path flip is back.');
      expect(source.contains('api2.makeRunPublic'), isFalse,
          reason: 'the wind-down block must not re-grow its own '
              'makeRunPublic call outside the dialog gate.');
    });
  });

  group('run-detail map survives ListView scroll', () {
    test('the map card is wrapped in a keep-alive so scroll does not rebuild it',
        () {
      // Reason: the run-detail map is a live FlutterMap rendered as an
      // ordinary ListView child. A bare list child is disposed once it
      // scrolls past the cache extent, tearing down the FlutterMap +
      // MapController; scrolling back rebuilt it from scratch — a visible
      // tile reload plus a jank spike (GitHub #274). The fix wraps the map
      // card in a keep-alive (AutomaticKeepAliveClientMixin, wantKeepAlive
      // => true), which both preserves its State and pauses its pulse ticker
      // while off-screen. Catches a regression that unwraps the map.
      final source =
          File('lib/screens/run_detail_screen.dart').readAsStringSync();
      expect(
        source,
        contains('class _KeepAliveMap'),
        reason: 'The run-detail map must keep a _KeepAliveMap wrapper so the '
            'ListView does not dispose + rebuild the FlutterMap on scroll.',
      );
      expect(
        source,
        contains('AutomaticKeepAliveClientMixin'),
        reason: '_KeepAliveMap must mix in AutomaticKeepAliveClientMixin — '
            'that is what keeps the map State alive past the cache extent.',
      );
      // The map (LiveRunMap, inside the SizedBox card) must sit UNDER the
      // wrapper: _KeepAliveMap( must appear before the map's LiveRunMap in
      // source order. If LiveRunMap moves ahead of the wrapper, the card is
      // a bare list child again and the reload regression is back.
      final wrapIdx = source.indexOf('_KeepAliveMap(');
      final mapIdx = source.indexOf('LiveRunMap(');
      expect(wrapIdx >= 0 && wrapIdx < mapIdx, isTrue,
          reason: '_KeepAliveMap( must wrap the map card (appear before '
              'LiveRunMap in source order).');
    });
  });

  group('privacy-zone removal confirms before erasing', () {
    test('privacy_zones_screen gates remove + clear-all behind a confirm', () {
      // Reason: a privacy zone hides the user's tracks near a sensitive
      // place (home/work) on public shares. The remove-marker tap and the
      // Clear-all button used to drop zones with no confirmation; web
      // confirms the equivalent removeZone. The fix requires both to route
      // through a showDialog<bool> confirm, and the marker to carry a
      // Semantics label (it was a bare GestureDetector under 48dp).
      final source =
          File('lib/screens/privacy_zones_screen.dart').readAsStringSync();
      expect(source, contains('_confirmRemoveZone'),
          reason: 'the zone marker tap must go through _confirmRemoveZone');
      expect(source, contains('_confirmClearAll'),
          reason: 'Clear-all must go through _confirmClearAll');
      expect(source, contains('showDialog<bool>'),
          reason: 'both confirms present an AlertDialog');
      expect(source, contains('privacyZonesRemoveSemantics'),
          reason: 'the remove marker must carry a Semantics label');
      // The Clear-all button must not wipe zones directly from onPressed.
      expect(
        source.contains('onPressed: () => setState(() => _zones = [])'),
        isFalse,
        reason: 'Clear-all must confirm first, not setState(_zones=[]) inline',
      );
    });
  });

  group('race End / Cancel confirm before mutating', () {
    test('event_detail End/Cancel route through _confirmRaceAction', () {
      // Reason: ending or cancelling a live race is irreversible and
      // affects every participant. Web gates both behind a ConfirmDialog;
      // the mobile race-control card used to fire _raceMutation(end) /
      // _raceMutation(cancel) on a single tap. The fix requires both
      // destructive arms to route through a _confirmRaceAction dialog;
      // Arm / Fire Go stay one-tap. Catches a regression that drops the
      // confirm or wires a button straight to _raceMutation.
      final source =
          File('lib/screens/event_detail_screen.dart').readAsStringSync();
      expect(
        source,
        contains('_confirmRaceAction'),
        reason: 'The End/Cancel race buttons must route through a '
            '_confirmRaceAction dialog before calling _raceMutation.',
      );
      expect(
        source,
        contains('showDialog<bool>'),
        reason: '_confirmRaceAction must present an AlertDialog confirm '
            '(showDialog<bool>) before the mutation.',
      );
      // Neither destructive arm may be invoked directly from an onPressed.
      expect(
        source,
        isNot(contains('_raceMutation(_RaceAction.end)')),
        reason: 'End must go through _confirmRaceAction, not call '
            '_raceMutation(_RaceAction.end) directly from a button.',
      );
      expect(
        source,
        isNot(contains('_raceMutation(_RaceAction.cancel)')),
        reason: 'Cancel must go through _confirmRaceAction, not call '
            '_raceMutation(_RaceAction.cancel) directly from a button.',
      );
      // Arm / Fire Go remain one-tap (non-destructive) — guard that the
      // confirm wrapper is reserved for the destructive arms by pinning
      // the localized confirm-body keys.
      expect(source, contains('eventRaceEndConfirmBody'));
      expect(source, contains('eventRaceCancelConfirmBody'));
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
            'See decisions / docs/backend/settings.md.',
      );
      // Permissive regex to tolerate either the one-line form OR the
      // wrapped-method-chain form `await api\n  .saveRun(\n run,\n
      // isPublic: ...)\n  .timeout(...)`. Both encode the same
      // semantic — the isPublic kwarg must reach the API call.
      expect(
        RegExp(r'\.saveRun\s*\(\s*run\s*,\s*\n?\s*isPublic\s*:')
            .hasMatch(source),
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

    test('background_sync applies the owner-tag filter before push', () {
      // Reason: WorkManager spawns a fresh isolate / process; without
      // the filter, on a shared device where User A records and User
      // B signs in, the next periodic fire pushes A's runs under B's
      // session. RLS silently accepts the rows (they embed the
      // caller's user_id), so the failure is invisible until A
      // notices their runs missing — same shared-device contamination
      // pattern the foreground SyncService filter was added to prevent.
      // See `docs/architecture/decisions.md § 67` for the owner-tag design.
      final source = File('lib/background_sync.dart').readAsStringSync();
      expect(
        source,
        contains('filterRunsForCurrentUser'),
        reason: 'background_sync.dart MUST route the unsynced list '
            'through filterRunsForCurrentUser (from sync_service.dart) '
            'before passing it to saveRunsBatch — without this, the '
            'WorkManager path bypasses the shared-device owner-tag '
            'guard the foreground SyncService applies.',
      );
    });

    test('main.dart drives SyncService.triggerSync on signedIn', () {
      // Reason: SyncService only fires automatically on startup,
      // foreground-resume, and connectivity-change. A user who records
      // offline, then signs in (no app backgrounding, no network
      // blip) had no automatic trigger — the offline run sat unsynced
      // until they manually tapped "Sync all" or restarted the app.
      // The signedIn trigger also bypasses backoff (see the
      // _backoffBypassReasons set in sync_service.dart) so a fresh
      // session doesn't inherit a dead one's rate-limit window.
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains('AuthChangeEvent.signedIn'),
        reason: 'main.dart must subscribe to the auth-state stream '
            'so it can react to signedIn.',
      );
      expect(
        source,
        contains("syncService.triggerSync('signin')"),
        reason: 'main.dart\'s signedIn handler MUST call '
            'syncService.triggerSync(\'signin\') — without it, runs '
            'recorded offline sit unsynced until the next foreground '
            'transition or manual tap.',
      );
    });

    test('_drainPendingDeletes uses the per-user filter', () {
      // Reason: the parallel of the run owner-tag filter. A pending
      // delete queued by user-a must NOT be attempted under user-b's
      // session on a shared device — RLS would reject and the queue
      // would loop forever. Without this guard, a future refactor
      // could silently switch back to the unfiltered
      // `pendingRemoteDeleteIds` getter and the foreign-owner
      // contamination returns.
      final source = File('lib/sync_service.dart').readAsStringSync();
      expect(
        source,
        contains('pendingRemoteDeletesForUser'),
        reason: '_drainPendingDeletes must call '
            'runStore.pendingRemoteDeletesForUser(api.userId), not '
            'the unfiltered pendingRemoteDeleteIds, so foreign-owned '
            'deletes stay queued for their rightful owner.',
      );
    });

    test('background_sync WorkManager frequency is hourly + keep-existing',
        () {
      // Reason: WorkManager fires periodic tasks on the device. A
      // tighter frequency (every 5 min, every 15 min) multiplied
      // across the install base produces N× more Supabase requests
      // per hour — a silent cost-of-Supabase amplifier with no
      // user-visible benefit. The hourly cadence is the documented
      // minimum acceptable interval (Android's WorkManager has a
      // hard floor at 15 min anyway, but 60 min is the conservative
      // baseline). ExistingPeriodicWorkPolicy.keep means re-running
      // registerBackgroundSync (e.g. on every app launch) doesn't
      // cancel-and-restart the existing task — without keep, the
      // first-run window is reset every launch, which never lets the
      // task fire at all on a frequently-relaunched device. /audit/
      // cost-controls May 2026 closeout.
      final source = File('lib/background_sync.dart').readAsStringSync();
      // Frequency must be ≥ 1 hour expressed as Duration(hours: N)
      // — Duration(minutes: <60>) or Duration(seconds: ...) would
      // be a regression. Match the hours-form and assert the
      // numeric is ≥ 1.
      final freqRe = RegExp(r'frequency:\s*const\s+Duration\(\s*hours:\s*(\d+)\s*\)');
      final m = freqRe.firstMatch(source);
      expect(m, isNotNull,
          reason: 'background_sync.dart must declare frequency as '
              'Duration(hours: N). Sub-hour intervals are an N× '
              'multiplier on Supabase request volume across the '
              'install base.');
      final hours = int.parse(m!.group(1)!);
      expect(hours, greaterThanOrEqualTo(1),
          reason: 'WorkManager frequency must be ≥ 1 hour, was '
              '$hours. /audit/cost-controls baseline.');
      expect(
        source,
        contains('ExistingPeriodicWorkPolicy.keep'),
        reason: 'WorkManager registration must use '
            'ExistingPeriodicWorkPolicy.keep so re-registration '
            'on app launch doesn\'t cancel-and-restart the existing '
            'task (which would reset the first-run window every '
            'launch and prevent the task from ever firing on a '
            'frequently-relaunched device).',
      );
    });

    test('coach_screen 429 branch does NOT auto-resend', () {
      // Reason: a 429 from the coach endpoint means the user's daily
      // quota is exhausted. Auto-retrying produces another 429 — but
      // a buggy retry loop would (a) pin one device's CPU on a
      // request that can't succeed for hours, and (b) on the off-
      // chance the cap was upped server-side, would spike spend the
      // moment the new quota landed. The 429 branch MUST surface a
      // toast / banner only, never re-enter _send. Pin the property
      // at the source level — the existing test coverage is
      // behavioural in a manual review only. /audit/cost-controls
      // May 2026.
      final source = File('lib/screens/coach_screen.dart').readAsStringSync();
      // Extract the 429 branch body — `if (res.statusCode == 429) {
      // ... }` — and assert it contains NO `_send(` call.
      final branchRe = RegExp(
        r'if\s*\(\s*res\.statusCode\s*==\s*429\s*\)\s*\{([\s\S]*?)\n\s{0,12}\}',
      );
      final m = branchRe.firstMatch(source);
      expect(m, isNotNull,
          reason: 'Could not locate the 429 branch in coach_screen.dart '
              '— has the comparison shape moved?');
      final branchBody = m!.group(1)!;
      expect(
        branchBody.contains('_send('),
        isFalse,
        reason: 'coach_screen 429 branch MUST NOT call _send() — a '
            'retry-on-429 loop is a denial-of-wallet vector (one '
            'device pinned on requests that can\'t succeed until '
            'the daily cap resets at UTC midnight, and a server-'
            'side cap bump would instantly drain the new quota). '
            'Surface a banner/toast and return.',
      );
    });

    test('main.dart clears SettingsSyncService on signedOut', () {
      // Reason: the cached SettingsService instance holds the
      // previously-signed-in user's universal + device bags
      // (privacy_zones, preferred_unit, voice_feedback, etc.). On a
      // shared device where A signs out and B signs in, B's
      // LiveBroadcaster.privacyZonesProvider would read A's cached
      // zones until B's onSignedIn re-fetch completes — leaking A's
      // home/work coordinates to B's live spectator broadcast in the
      // intervening window. The signedOut handler MUST call
      // settingsSync?.onSignedOut() to drop the cache before any
      // record can use it. See decisions §33.
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains('AuthChangeEvent.signedOut'),
        reason: 'main.dart must subscribe to signedOut events.',
      );
      expect(
        source,
        contains('?.onSignedOut(priorUserId:'),
        reason: 'main.dart\'s signedOut handler MUST call '
            'settingsSync?.onSignedOut(priorUserId: …) — without it, the '
            'previous user\'s privacy_zones stay cached (and their bag-'
            'mirrored Preferences carry over) into the next account.',
      );
    });

    test('main.dart stamps the watch-ingest queue before draining on signin',
        () {
      // Reason: WatchIngestQueue files queued while signed-out carry
      // an `intended_owner_user_id` stamp set from the
      // setLastKnownOwner cache. drain() skips files whose stamp
      // names a different user from the one currently signed in. For
      // that filter to work on signin, main.dart must update the
      // last-known-owner stamp to the FRESHLY-SIGNED-IN user BEFORE
      // calling drain — otherwise the drain still sees the previous
      // user's stamp and skips every file (or, worse, if a previous
      // user never signed in, drains everything to the new user).
      // Pinned because a refactor that reordered the listener body
      // (e.g. hoisting drain ahead of the stamp call) would silently
      // re-open the shared-device contamination window the stamp was
      // added to close.
      final mainSource = File('lib/main.dart').readAsStringSync();
      final stampIdx = mainSource.indexOf(
        'watchQueue.setLastKnownOwner(apiNonNull.userId)',
      );
      final drainIdx = mainSource.indexOf(
        'watchQueue.drain(apiNonNull)',
      );
      expect(stampIdx, greaterThan(-1),
          reason: 'main.dart must call watchQueue.setLastKnownOwner '
              'in the signedIn listener — without the update, the '
              'queue\'s stamp stays at the previous user and drain '
              'misclassifies new files.');
      expect(drainIdx, greaterThan(-1),
          reason: 'main.dart must call watchQueue.drain on signedIn.');
      expect(
        stampIdx,
        lessThan(drainIdx),
        reason: 'watchQueue.setLastKnownOwner MUST appear before '
            'watchQueue.drain in the signedIn handler. The reverse '
            'order leaves drain running with the PREVIOUS user\'s '
            'stamp — a fresh user-b sign-in would skip every file '
            '(because the stamp is still user-a), and the queue '
            'would never drain for either user.',
      );
      // Also pin the bootstrap call so a process restart with a
      // cached session writes the stamp before any payloads can
      // arrive.
      expect(
        mainSource,
        contains('watchQueue.setLastKnownOwner(api.userId)'),
        reason: 'main.dart bootstrap must call '
            'watchQueue.setLastKnownOwner(api.userId) when restoring '
            'a cached session — without it, payloads arriving during '
            'a signed-out window after the restart carry no stamp '
            'and adopt to whichever user signs in next.',
      );
    });

    test('LiveBroadcaster drops in-zone pings client-side', () {
      // Reason: the `live_run_pings_drop_in_zone` BEFORE INSERT
      // trigger (migration 20260618_001) only protects the legacy
      // Supabase transport. The Go hub bypasses Postgres entirely —
      // it POSTs straight to the hub service which fans out via
      // WebSocket to anonymous spectators, with no server-side
      // privacy gate. Without a client-side drop, a runner with a
      // privacy zone around their home leaks every in-zone fix to
      // anonymous spectators when the hub transport is wired. The
      // guard pins both ends of the contract: the broadcaster must
      // accept a privacy-zones provider, and the run_screen must
      // wire it from settingsSync.
      final lbSource =
          File('lib/live_broadcaster.dart').readAsStringSync();
      expect(
        lbSource,
        contains('privacyZonesProvider'),
        reason: 'LiveBroadcaster must accept a privacy-zones provider '
            '— the Go-hub transport has no server-side privacy gate, '
            'so client-side dropping is the only enforcement.',
      );
      expect(
        lbSource,
        contains('isInAnyZone'),
        reason: 'LiveBroadcaster.pushPing must call isInAnyZone on '
            'the current ping coordinates and short-circuit when '
            'true — the in-zone drop must happen before the request '
            'leaves the device.',
      );

      final rsSource =
          File('lib/screens/run_screen.dart').readAsStringSync();
      expect(
        rsSource,
        contains('privacyZonesProvider:'),
        reason: 'run_screen must wire privacyZonesProvider when '
            'constructing LiveBroadcaster — without the wire the '
            'broadcaster has no zones to filter against and the '
            'Go-hub leak returns.',
      );
      expect(
        rsSource,
        contains('_currentPrivacyZones'),
        reason: 'the provider must read the zones live from '
            '_currentPrivacyZones (which reads from settingsSync), '
            'not a constant — mid-run zone additions in Settings '
            'must take effect on the next ping, not the next run.',
      );
    });

    test('runs_screen passes the current user id when queuing pending '
        'deletes', () {
      // Reason: pairs with the drain guard above. Tagging at queue
      // time is what makes the filter useful — without the tag,
      // every entry is "untagged" and the filter degrades to "drain
      // by any user", which is exactly the bug the tag was added to
      // prevent.
      final source =
          File('lib/screens/runs_screen.dart').readAsStringSync();
      expect(
        source,
        contains('markManyPendingRemoteDelete('),
        reason: 'runs_screen must queue failed deletes through '
            'markManyPendingRemoteDelete.',
      );
      expect(
        source,
        contains('ownerUserId: api?.userId'),
        reason: 'runs_screen MUST pass api?.userId as ownerUserId so '
            'the queued delete carries the current user\'s tag — '
            'without it, the entry is untagged and a different '
            'user\'s drain would attempt it (and fail under RLS).',
      );
    });

    test('SyncService accepts signin as a backoff-bypass reason', () {
      // Reason: pairs with the main.dart guard above. The signin
      // trigger only matters if SyncService treats it as a bypass —
      // otherwise the fresh sign-in is silently gated by a 30-min
      // backoff inherited from a stale (now-replaced) session.
      final source = File('lib/sync_service.dart').readAsStringSync();
      expect(
        source,
        contains("'signin'"),
        reason: 'sync_service.dart must list \'signin\' in the '
            '_backoffBypassReasons set.',
      );
      // Also pin that the gating predicate is the set, not the old
      // literal `reason != 'manual'` check — that one would silently
      // ignore the signin tag.
      expect(
        source,
        contains('_backoffBypassReasons.contains(reason)'),
        reason: '_trySync must consult the _backoffBypassReasons set '
            'instead of a literal "manual" check — the set is what '
            'lets new bypass reasons (signin, future: post-recovery) '
            'work without revisiting the gate.',
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
      // The enum moved to `core_models` so a pure parser could reach the
      // vocabulary without a widget toolkit (decisions § 1013); the getter
      // travelled with it, being physics rather than presentation.
      final source =
          File('../../packages/core_models/lib/src/activity_type.dart')
              .readAsStringSync();
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
        r'Future<void> _pickAndImport\(\)\s*async\s*\{',
      );
      expect(
        body,
        contains('compute('),
        reason: '_pickAndImport must run RouteParser.fromGpx / fromKml inside '
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

    test('release-mode debugPrint no-op override is present', () {
      // Reason: Flutter's default debugPrint forwards to print() in
      // every build mode — only assert() blocks are stripped in
      // release. The layered-resilience contract debugPrints caught
      // exceptions across ~76 files, and a PostgrestException's
      // details/hint can echo row content (safety-contact emails,
      // health free text) into logcat/os_log on a release build.
      // /audit/pii-in-logs.
      final source = File('lib/main.dart').readAsStringSync();
      final releaseBlock = source.substring(source.indexOf('if (kReleaseMode)'));
      expect(
        releaseBlock,
        contains('debugPrint = (String? message, {int? wrapWidth}) {};'),
        reason: 'main.dart must no-op debugPrint inside the kReleaseMode '
            'block so exception dumps never reach device logs on a '
            'release build.',
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

    test('split notification reuses one fixed transient id, cleared with the run (#303)', () {
      // Reason: the per-km split row used to stack — a new notification
      // per kilometre, persisting across runs, burying the shade. The
      // fix pins a single fixed SPLIT_NOTIFICATION_ID (distinct from the
      // geolocator ongoing id) so each split replaces in place, makes the
      // row transient (auto-cancel + timeout, never ongoing), and cancels
      // it on run stop ("clear") as well as run start (clear_split from
      // Dart). Shared host file — skip on the iOS twin.
      final file = File(
        'android/app/src/main/kotlin/com/threkir/app/RunNotificationBridge.kt',
      );
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();

      final idDecl = RegExp(
        r'SPLIT_NOTIFICATION_ID\s*=\s*(\d+)',
      ).firstMatch(source);
      expect(idDecl, isNotNull,
          reason: 'the split row must post on a named fixed id constant');
      expect(idDecl!.group(1), isNot('75415'),
          reason: 'the split id must be distinct from the geolocator '
              'ongoing-run id or splits would clobber the live stats row');

      final postSplit = source.substring(source.indexOf('fun postSplit'));
      final postSplitBody =
          postSplit.substring(0, postSplit.indexOf('fun post('));
      expect(postSplitBody, contains('.notify(SPLIT_NOTIFICATION_ID'),
          reason: 'every split reposts on the SAME id — replace in '
              'place, never one row per kilometre');
      expect(postSplitBody, contains('.setAutoCancel(true)'),
          reason: 'the split row must dismiss on tap');
      expect(postSplitBody, contains('.setTimeoutAfter('),
          reason: 'the split row must time itself out — it never '
              'demands a manual swipe');
      expect(postSplitBody, contains('.setOngoing(false)'),
          reason: 'a split is transient, not an ongoing row');

      final clearBranch = source.substring(source.indexOf('"clear" ->'));
      final clearBody =
          clearBranch.substring(0, clearBranch.indexOf('"clear_split"'));
      expect(clearBody, contains('cancel(SPLIT_NOTIFICATION_ID)'),
          reason: 'run stop must clear the split row too, so it cannot '
              'outlive its run');
      expect(source, contains('"clear_split"'),
          reason: 'run start clears a previous run\'s leftover split row');
    });

    test('RunNotificationBridge sources its user-facing strings from resources', () {
      // audit/i18n-readiness W-OS-3: the channel name (shown in system
      // notification settings), the title fallback, and the lock-screen
      // action labels are user-facing, so they must come from string
      // resources (localisable) rather than hard-coded English. Reverting
      // any of them to a literal drops the matching R.string reference and
      // trips this guard. Shared host file — skip on the iOS twin.
      final file = File(
        'android/app/src/main/kotlin/com/threkir/app/RunNotificationBridge.kt',
      );
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      for (final res in [
        'R.string.run_notif_channel_name',
        'R.string.run_notif_title_fallback',
        'R.string.run_notif_action_resume',
        'R.string.run_notif_action_pause',
        'R.string.run_notif_action_stop',
      ]) {
        expect(
          source,
          contains(res),
          reason: '$res must back a user-facing notification string '
              '(W-OS-3): do not hard-code the English literal.',
        );
      }
    });

    test('lock-screen action buttons broadcast, never launch an activity (#270)',
        () {
      // Reason: a getActivity PendingIntent on the Pause/Stop buttons
      // launches MainActivity, which trips the keyguard unlock prompt on
      // a locked phone — the user must unlock before the action fires.
      // A true lock-screen control must work locked, so the buttons must
      // route through a BroadcastReceiver (getBroadcast → RunActionReceiver
      // → dispatchAction). Reverting actionIntent to getActivity /
      // MainActivity re-introduces the bug. Shared host files — skip on the
      // iOS twin.
      final bridge = File(
        'android/app/src/main/kotlin/com/threkir/app/RunNotificationBridge.kt',
      );
      if (!bridge.existsSync()) return;
      final bridgeSrc = bridge.readAsStringSync();

      final actionIntent =
          bridgeSrc.substring(bridgeSrc.indexOf('fun actionIntent'));
      final actionIntentBody =
          actionIntent.substring(0, actionIntent.indexOf('\n    }'));
      expect(actionIntentBody, contains('PendingIntent.getBroadcast'),
          reason: 'the action buttons must fire a broadcast so they work '
              'on a locked phone without a keyguard unlock (#270)');
      expect(actionIntentBody, contains('RunActionReceiver::class.java'),
          reason: 'the action broadcast must target RunActionReceiver');
      expect(actionIntentBody, isNot(contains('getActivity')),
          reason: 'an action button that launches an activity trips the '
              'keyguard unlock prompt — the bug this guards against');

      final receiver = File(
        'android/app/src/main/kotlin/com/threkir/app/RunActionReceiver.kt',
      );
      expect(receiver.existsSync(), isTrue,
          reason: 'RunActionReceiver must exist to receive the broadcast');
      expect(receiver.readAsStringSync(),
          contains('RunNotificationBridge.instance?.dispatchAction'),
          reason: 'the receiver must forward the action into the bridge');

      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:name=".RunActionReceiver"'),
          reason: 'the receiver must be declared in the manifest or the '
              'broadcast is dropped');
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

    test('the shared run row passes runId + ownerUserId to RunTrackPreview',
        () {
      // Reason: /u/[id] (the public profile) renders OTHER users' runs.
      // Pre-fix the runs-tab thumbnail mounted RunTrackPreview without
      // ownerUserId, which makes _shouldClip return false and serves
      // the unclipped polyline. audit/privacy-zones, May 2026. The mount moved
      // into the shared row when #666 C8 consolidated the two forks of it;
      // the clip requirement moved with it.
      final row = File('lib/widgets/run_list_tile.dart').readAsStringSync();
      expect(
        row,
        matches(RegExp(r'RunTrackPreview\([^)]*runId:', dotAll: true)),
        reason: 'the run row must thread the run id into RunTrackPreview so '
            'the clip-public-track EF can resolve it.',
      );
      expect(
        row,
        matches(RegExp(r'RunTrackPreview\([^)]*ownerUserId:', dotAll: true)),
        reason: 'the run row must thread the run owner id into '
            'RunTrackPreview so the privacy-zone clip kicks in.',
      );
      expect(
        File('lib/screens/profile_screen.dart').readAsStringSync(),
        contains('ownerUserId: widget.userId'),
        reason: 'and the profile must supply it — this list is the one that '
            'shows other runners\' runs.',
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
      // RPC `clipRouteForViewer`, NOT the run-bound
      // `fetchClippedTrackForRun` (which resolves a RUN id through the
      // clip-public-track Edge Function and knows nothing about route
      // visibility).
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
        isNot(matches(RegExp(r'\.fetchClippedTrackForRun\s*\('))),
        reason: 'public_route_screen must not clip through the run path — '
            'it takes a run id and skips route visibility / club-member '
            'checks. Use clipRouteForViewer.',
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
      // Reason: the same fail-closed contract fetchClippedTrackForRun
      // keeps for runs. Returning the unclipped row column on RPC error
      // would defeat the helper.
      final source =
          File('../../packages/api_client/lib/src/api_client.dart')
              .readAsStringSync();
      final body = _extractMethodBody(
        source,
        r'Future<List<Waypoint>> clipRouteForViewer\([^)]*\)\s*async\s*\{',
      );
      final tail = body.substring(body.indexOf('try'));
      expect(RegExp(r'catch \([^)]*\) \{').hasMatch(tail), isTrue,
          reason: 'clipRouteForViewer must have an explicit catch branch.');
      final catchBody = _extractMethodBody(tail, r'catch \([^)]*\) \{');
      expect(
        catchBody.contains('return const []'),
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

    test('public-lift readers go through the public_gym_workouts view', () {
      // Reason: migration 20270313_001 dropped the "owner or public read"
      // branch on gym_workouts (it wire-leaked external_id /
      // last_modified_at / notes / metadata) and moved non-owner reads to
      // the redacted public_gym_workouts view. A base-table query as a
      // non-owner now returns [] rather than erroring, so the cross-modal
      // following feed silently lost every followee's public lift
      // (issue #527). The view is the only non-owner lift read path.
      final source =
          File('../../packages/api_client/lib/src/api_client.dart')
              .readAsStringSync();
      const fn = '_fetchFollowingLifts';
      // Anchored on the declaration, not a bare ` $fn(` — the call site in
      // fetchFollowingActivityFeed comes first in the file and would scope
      // the assertion to the wrong body.
      final start =
          source.indexOf('Future<List<LiftFeedEntry>> $fn(');
      expect(start >= 0, isTrue, reason: 'Could not locate $fn — rename?');
      final end = source.indexOf('\n  }\n', start);
      expect(end > start, isTrue, reason: 'Could not locate end of $fn body');
      final body = source.substring(start, end);
      expect(
        body.contains("from('public_gym_workouts')"),
        isTrue,
        reason:
            '$fn must read from the public_gym_workouts view rather than the '
            'gym_workouts table — the base table is owner-only since '
            'migration 20270313_001, so a non-owner read returns nothing.',
      );
      expect(
        RegExp(r"from\(\s*GymWorkoutRow\.table\s*\)").hasMatch(body),
        isFalse,
        reason:
            '$fn must NOT read from the bare GymWorkoutRow.table — that path '
            'is owner-only and silently yields an empty lift feed.',
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

  group('live spectator cutoff card reads route geometry via fetchRouteById',
      () {
    // Reason: audit/privacy-zones Medium (2026-07-02) — the next-cutoff
    // ETA card on the live spectator surface projects the runner's live
    // position against the linked route's waypoints, and the viewer is
    // usually NOT the route owner (a club member or an anon visitor with
    // the public share link). ApiClient.fetchRouteById is the owner-aware
    // reader: it returns the raw polyline only to the owner and routes
    // every other viewer through clip_route_for_viewer, failing closed to
    // an empty polyline on RPC error. The screen must source the roadbook
    // waypoints from that helper only — a direct routes-table read here
    // would resurrect the unclipped wire-leak that was closed at the
    // data-fetch root (decisions §33).

    test('_loadCutoffLegs sources waypoints from api.fetchRouteById only', () {
      final src =
          File('lib/screens/live_spectator_screen.dart').readAsStringSync();
      final body = _extractMethodBody(
        src,
        r'Future<void> _loadCutoffLegs\([^)]*\)\s*async\s*\{',
      );
      expect(
        body.contains('fetchRouteById'),
        isTrue,
        reason: '_loadCutoffLegs must fetch the route via '
            'ApiClient.fetchRouteById — the owner-aware reader that clips '
            'waypoints for non-owner viewers.',
      );
      expect(
        src.contains("from('routes')"),
        isFalse,
        reason: 'live_spectator_screen.dart must not read the routes table '
            'directly — RLS surfaces unclipped club-owned rows to club '
            'members, and only fetchRouteById applies the non-owner clip.',
      );
      expect(
        src.contains('RouteRow.table'),
        isFalse,
        reason: 'live_spectator_screen.dart must not query RouteRow.table — '
            'route reads go through ApiClient.fetchRouteById.',
      );
    });
  });

  group('release builds never load .env.development', () {
    // Reason: pubspec.yaml ships .env.development as a Flutter asset for
    // local development convenience (decisions §137 — on mobile, dev
    // defaults load from the bundled asset, not a .env.local file). A
    // developer building a release APK locally without first overwriting
    // their .env.development would bake real SUPABASE_ANON_KEY,
    // MAPTILER_KEY, dev creds, and any BYPASS_PAYWALL=true into the APK
    // assets. The runtime guard is the kDebugMode gate around the
    // dotenv.load call in main.dart — release builds skip the load
    // entirely so the asset bytes, even if extractable from the APK, are
    // never read by the app. /audit/all High (secrets agent, 2026-05-07).
    test('main.dart only calls dotenv.load(\'.env.development\') under kDebugMode',
        () {
      final source = File('lib/main.dart').readAsStringSync();
      // Locate the `.env.development` filename argument. The call may be
      // formatted across several lines (dart format splits it once the
      // argument list grows), so don't assume `dotenv.load(` and the
      // `fileName:` argument share a line.
      final fileArgIdx = source.indexOf("fileName: '.env.development'");
      expect(
        fileArgIdx,
        greaterThan(0),
        reason:
            'Expected dotenv.load(fileName: \'.env.development\', ...) in main.dart. '
            'If the call has been replaced or removed, update this guard.',
      );
      // That argument must belong to a dotenv.load(...) call.
      final loadIdx = source.lastIndexOf('dotenv.load(', fileArgIdx);
      expect(
        loadIdx,
        greaterThan(0),
        reason:
            'fileName: \'.env.development\' must be an argument to dotenv.load(...).',
      );
      // Walk backwards to find the nearest `if (` opening — the load
      // must sit inside an `if (kDebugMode) { ... }` block.
      final preceding = source.substring(0, loadIdx);
      final guardIdx = preceding.lastIndexOf('if (kDebugMode)');
      expect(
        guardIdx,
        greaterThan(0),
        reason:
            'dotenv.load(\'.env.development\', ...) must sit inside an '
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

    // Reason: the startup seed auto-login (DEV_USER_EMAIL/PASSWORD) must
    // never sign a user into production. The gate lives in
    // dev_auto_login.dart#shouldAutoLogin, which only returns true for a
    // loopback SUPABASE_URL. Pin that main.dart routes the auto sign-in
    // through it so the loopback rail can't be silently reverted to the
    // old ungated inline credential check. See dev_prod_isolation.md.
    test('main.dart gates the dev auto-login on shouldAutoLogin', () {
      final source = File('lib/main.dart').readAsStringSync();
      final gateIdx = source.indexOf('shouldAutoLogin(');
      final signInIdx = source.indexOf('api!.signIn(');
      expect(gateIdx, greaterThan(0),
          reason: 'main.dart must call shouldAutoLogin(...) — the loopback '
              'guard that stops seed creds reaching a production backend.');
      expect(signInIdx, greaterThan(gateIdx),
          reason: 'the auto api!.signIn(...) must sit inside the '
              'shouldAutoLogin(...) gate, not before it.');
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

  group('one club-insert path', () {
    // `clubs.slug` is `text unique not null`, so an insert that does not
    // handle 23505 fails outright the moment two people name a club the same
    // thing — and the slug is derived from the NAME, so that is not a rare
    // race. `SocialService.createClub` retries up to four times with a random
    // suffix; `ApiClient.createClub` was a second, caller-less insert that did
    // not, and also never minted the `invite_token` an invite-only club needs
    // to be shareable. It was deleted rather than repaired, because two write
    // paths to one unique column is the defect (decisions § 1339).
    //
    // Pinned as a COUNT over the whole mobile + api_client tree rather than as
    // the absence of one deleted symbol: a guard keyed on the name
    // `ApiClient.createClub` would pass the moment the next one is called
    // something else, which is precisely how this one survived unnoticed.
    test('exactly one place in the tree inserts into clubs', () {
      final roots = <String>[
        'lib',
        '../../packages/api_client/lib',
        '../../packages/core_models/lib',
      ];
      final insert = RegExp(
        r"""\.from\((?:['"]clubs['"]|ClubRow\.table)\)\s*\.insert\(""",
      );
      final sites = <String>[];
      for (final root in roots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart')) continue;
          final stripped = f
              .readAsStringSync()
              .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
              .replaceAll(RegExp(r'//.*'), '');
          if (insert.hasMatch(stripped)) sites.add(f.path);
        }
      }
      expect(
        sites.length,
        1,
        reason: 'Expected exactly one club-insert site (the one in '
            'social_service.dart that retries on 23505 and mints the '
            'invite token). Found: $sites. A second insert path to a '
            'unique column is a trap for whoever calls it next — route '
            'it through SocialService.createClub instead.',
      );
      expect(sites.single, endsWith('social_service.dart'));
    });
  });

  group('Android phone manifest', () {
    // These tests guard the Play-policy + SDK-34/35 manifest plumbing
    // that the audit pass identified as submission blockers. The
    // checks short-circuit on the iOS twin (no android/ directory).
    test('READ_MEDIA_IMAGES is stripped, never actively declared', () {
      final file =
          File('android/app/src/main/AndroidManifest.xml');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      // image_picker (image_picker_android) transitively injects
      // READ_MEDIA_IMAGES into the MERGED manifest for its legacy
      // gallery-pick fallback — even though the app only ever uses the
      // Android Photo Picker (no permission on any API level that has
      // the permission). Left un-stripped it forces a broad-media-access
      // justification plus a Photos & videos Data Safety entry, and Play
      // rejects the release for a photo/video permission the app never
      // needed. So the manifest strips it with tools:node="remove".
      // Guard that the strip stays in place AND that the permission is
      // never actively declared (a bare <uses-permission .../> without
      // the remove directive).
      final hasStrip = RegExp(
        r'READ_MEDIA_IMAGES"\s+tools:node="remove"',
      ).hasMatch(body);
      expect(hasStrip, isTrue,
          reason:
              'AndroidManifest.xml must strip the transitively-injected '
              'READ_MEDIA_IMAGES via tools:node="remove" so it never '
              'reaches the merged manifest.');
      final hasActiveDeclaration = RegExp(
        r'READ_MEDIA_IMAGES"\s*/>',
      ).hasMatch(body);
      expect(hasActiveDeclaration, isFalse,
          reason:
              'READ_MEDIA_IMAGES may appear ONLY as a tools:node="remove" '
              'strip, never as an active <uses-permission> — the app uses '
              'the Android Photo Picker and needs no media permission.');
    });

    test('allowBackup is disabled so GPS/HR + auth tokens stay out of cloud backup', () {
      final file = File('android/app/src/main/AndroidManifest.xml');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      // The local run/route/gym/food JSON caches (under app_flutter via
      // path_provider) hold GPS traces + per-point HR, and the Supabase
      // session (access + refresh JWT) lives in SharedPreferences. Android
      // Auto-Backup would otherwise sweep all of it into Google's cloud.
      // It's all server-re-derivable cache + tokens, so we opt the whole
      // app out rather than surgically exclude. See decisions.md (at-rest
      // / backup posture) + remediation plan 3c-b.
      expect(
        body,
        contains('android:allowBackup="false"'),
        reason: 'AndroidManifest.xml must set android:allowBackup="false" '
            'so the GPS/HR run cache and the SharedPreferences-stored '
            'Supabase session are never extracted via Android Auto-Backup.',
      );
    });

    test('AndroidManifest explicitly overrides geolocator service with foregroundServiceType="location"', () {
      // Reason: the plugin's manifest declares the type via manifest
      // merge — but the Play Data Safety reviewer reads the AS-
      // COMPILED manifest, and Android 14's runtime check throws
      // SecurityException if the merged result silently loses the
      // type attribute (a plugin version bump or merge conflict can
      // strip it without a build warning). The app's own manifest
      // declares the service with tools:node="merge" so the type is
      // visible in OUR file AND the plugin's other attributes
      // (enabled, exported) survive merge. /audit/app-store-
      // privacy May 2026 High closeout.
      final file = File('android/app/src/main/AndroidManifest.xml');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      expect(
        body,
        contains(
            'android:name="com.baseflow.geolocator.GeolocatorLocationService"'),
        reason: 'AndroidManifest.xml must explicitly declare the '
            'geolocator service with our own <service> block so the '
            'compiled manifest has foregroundServiceType="location" '
            'visible without depending on the plugin\'s manifest merge.',
      );
      // The same <service> block must carry the type attribute. We
      // grep for both literal forms (single-line + multi-line) by
      // matching the substring after the service name.
      expect(
        RegExp(
          r'GeolocatorLocationService"[\s\S]{0,200}foregroundServiceType="location"',
        ).hasMatch(body),
        isTrue,
        reason: 'The explicit <service> block for '
            'GeolocatorLocationService must carry '
            'android:foregroundServiceType="location". Without it, a '
            'future plugin bump that drops the attribute from the '
            'merged manifest silently breaks Android 14 + the Play '
            'reviewer\'s Data Safety cross-check.',
      );
    });

    test('geolocator service pins stopWithTask=false so recording survives a Recents swipe', () {
      // Reason: geolocator's GeolocatorLocationService declares neither
      // android:stopWithTask nor an onTaskRemoved() override, so nothing
      // keeps the foreground GPS service alive when the user swipes the
      // app card off Recents mid-run — the service (and its hosting
      // process) is torn down and recording dies silently (issue #250).
      // Our <service> override pins stopWithTask="false" so the run
      // survives. A regression that drops the attribute re-opens the bug.
      final file = File('android/app/src/main/AndroidManifest.xml');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      expect(
        RegExp(
          r'GeolocatorLocationService"[\s\S]{0,200}stopWithTask="false"',
        ).hasMatch(body),
        isTrue,
        reason: 'The explicit <service> block for '
            'GeolocatorLocationService must carry '
            'android:stopWithTask="false" so swiping the app off Recents '
            'mid-run does not silently tear down the recording foreground '
            'service (issue #250).',
      );
    });

    test('foreground services that we actually promote declare a type', () {
      final file =
          File('android/app/src/main/AndroidManifest.xml');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      // Android 14+ (SDK 34+) crashes a foreground service that
      // doesn't declare a type. We only promote ONE foreground
      // service today — geolocator's GeolocatorLocationService,
      // and the geolocator plugin's manifest declares
      // foregroundServiceType="location" via its own merge.
      // FOREGROUND_SERVICE_LOCATION is the matching permission.
      //
      // Workmanager is NOT a foreground-service consumer in this app:
      // its tasks run via JobScheduler (SystemJobService), not via
      // SystemForegroundService. Don't add a dataSync override on
      // SystemForegroundService — the manifest merger silently drops
      // it at packaging stage (the audit pass briefly added one;
      // the override was dead code).
      expect(
        body,
        contains(
            '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"'),
        reason:
            'AndroidManifest.xml must declare FOREGROUND_SERVICE_LOCATION '
            'so geolocator can promote its location service on SDK 34+.',
      );
      // Look for the actual <uses-permission> declaration shape, not
      // the bare token — the manifest legitimately mentions the
      // permission name in an explanatory comment about why we don't
      // declare it.
      expect(
        body.contains(
            '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"'),
        isFalse,
        reason:
            'Do not declare FOREGROUND_SERVICE_DATA_SYNC — it backs a '
            'service type Workmanager does not use in this app. Adding '
            'it without a real consumer is a Play Data Safety oddity '
            'reviewers flag.',
      );
    });

    test('Health Connect permissions XML is wired', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml');
      if (!manifest.existsSync()) return;
      final body = manifest.readAsStringSync();
      final xmlFile = File(
          'android/app/src/main/res/xml/health_permissions.xml');
      expect(
        xmlFile.existsSync(),
        isTrue,
        reason:
            'res/xml/health_permissions.xml must exist so the Play '
            'Console Health Connect form has the permission '
            'inventory to validate.',
      );
      expect(
        body,
        contains('android:name="health_permissions"'),
        reason:
            'MainActivity must carry the health_permissions meta-data '
            'pointing at res/xml/health_permissions.xml.',
      );
      expect(
        body,
        contains(
            'androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'),
        reason:
            'MainActivity needs an intent-filter for the Health '
            'Connect rationale entry-point so the permission sheet '
            'opens our privacy explainer instead of the generic '
            'fallback.',
      );
      if (xmlFile.existsSync()) {
        final xml = xmlFile.readAsStringSync();
        for (final perm in const [
          'android.permission.health.READ_EXERCISE',
          'android.permission.health.READ_DISTANCE',
          'android.permission.health.READ_HEART_RATE',
          // Write-back perms (persona #36) — writeWorkoutData inserts an
          // ExerciseSessionRecord + a DistanceRecord.
          'android.permission.health.WRITE_EXERCISE',
          'android.permission.health.WRITE_DISTANCE',
          // Raw per-point HR is written too: _writeHeartRate fans
          // HeartRateRecord samples onto Health Connect (persona round-5),
          // which needs WRITE_HEART_RATE — not covered by WRITE_EXERCISE.
          'android.permission.health.WRITE_HEART_RATE',
        ]) {
          expect(
            xml,
            contains(perm),
            reason:
                'health_permissions.xml must list every Health '
                'Connect permission the app actually reads or writes '
                '($perm missing).',
          );
        }
        // WRITE_HEART_RATE is runtime-critical, so it must ALSO be a
        // manifest uses-permission (the Play form reads the XML, but the OS
        // grant the exporter needs comes from the manifest). Guarding only
        // the XML would let a manifest-only drop break HR write-back
        // silently (the L4 try/catch swallows the resulting failure).
        expect(
          body,
          contains('android.permission.health.WRITE_HEART_RATE'),
          reason:
              'AndroidManifest.xml must declare the WRITE_HEART_RATE '
              'uses-permission — the exporter writes raw HeartRateRecord '
              'samples (_writeHeartRate); without the grant the HR '
              'write-back silently fails.',
        );
      }
    });

    test('targetSdk is pinned to 35 or higher', () {
      final gradle =
          File('android/app/build.gradle.kts');
      if (!gradle.existsSync()) return;
      final body = gradle.readAsStringSync();
      // Play Console requires targetSdk >= 35 for new + updated apps.
      // The previous `targetSdk = flutter.targetSdkVersion` indirection
      // resolved to whatever the user's Flutter SDK shipped with —
      // brittle and unauditable. Pin the literal here so a Flutter
      // SDK rollback can't silently regress us under the Play floor.
      final pinRe = RegExp(r'targetSdk\s*=\s*(\d+)');
      final match = pinRe.firstMatch(body);
      expect(
        match,
        isNotNull,
        reason:
            'build.gradle.kts must pin targetSdk to a literal int '
            '(currently absent or non-numeric).',
      );
      final pin = int.parse(match!.group(1)!);
      expect(
        pin >= 35,
        isTrue,
        reason:
            'targetSdk must be >= 35 (Play Console floor). Found $pin.',
      );
    });

    test('unused biometric permissions are stripped at merge time', () {
      // audit/app-store-privacy (2026-05-30) Critical: androidx.biometric
      // (transitive) injects USE_BIOMETRIC + USE_FINGERPRINT into the
      // merged manifest, but the app has no biometric auth surface. They
      // must be removed with tools:node="remove" so the binary's
      // permission set matches the Play Data Safety form. A regression
      // that drops the remove directive silently reintroduces an
      // undisclosed sensitive permission.
      final file = File('android/app/src/main/AndroidManifest.xml');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      for (final perm in ['USE_BIOMETRIC', 'USE_FINGERPRINT']) {
        expect(
          RegExp(
            'android.permission.$perm"[\\s\\S]{0,80}tools:node="remove"',
          ).hasMatch(body),
          isTrue,
          reason: '$perm must be declared with tools:node="remove" — it '
              'is injected transitively and the app uses no biometric '
              'auth, so it must not reach the binary undisclosed.',
        );
      }
    });

    test('RECEIVE_BOOT_COMPLETED is declared explicitly for disclosure', () {
      // audit/app-store-privacy (2026-05-30) Critical: workmanager
      // injects RECEIVE_BOOT_COMPLETED. It is a real (boot-resume of
      // background sync) capability we keep, so it must be visible in
      // the source manifest — otherwise the operator filling the Play
      // Data Safety form can't see it. Pin its explicit declaration.
      final file = File('android/app/src/main/AndroidManifest.xml');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      expect(
        body,
        contains(
            '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />'),
        reason: 'RECEIVE_BOOT_COMPLETED must be declared explicitly so it '
            'is visible to the Play Data Safety form rather than only '
            'appearing in the merged binary via workmanager.',
      );
    });
  });

  group('Restore purchases (Apple/Play subscription policy)', () {
    test('Pro screen exposes a Restore-purchases ListTile', () {
      // Reason: audit/app-store-privacy (May 2026) flagged the absence
      // of a Restore-purchases entry point. Apple Review Guideline
      // 3.1.1 + Play subscription policy require it on every
      // subscription app. Source-grep guard so a future refactor
      // can't quietly drop it.
      final source =
          File('lib/screens/settings_pro_screen.dart').readAsStringSync();
      final arb = File('lib/l10n/app_en.arb').readAsStringSync();
      // The tile title is localized via gen-l10n (proRestorePurchases);
      // the English copy lives in the ARB. Pin both so a refactor can't
      // drop the tile or empty the disclosure copy.
      expect(
        source,
        contains('l10n.proRestorePurchases'),
        reason:
            'settings_pro_screen.dart must surface a "Restore purchases" tile '
            '(localized via l10n.proRestorePurchases).',
      );
      expect(
        arb,
        contains('"proRestorePurchases": "Restore purchases"'),
        reason: 'app_en.arb must carry the "Restore purchases" tile copy.',
      );
      expect(
        source,
        contains('_restorePurchases(context)'),
        reason:
            'settings_pro_screen.dart must wire the tile to _restorePurchases().',
      );
    });

    test('Pro screen exposes a Manage-subscription ListTile', () {
      // Reason: Apple Guideline 3.1.1 + Play subscription policy
      // require an in-app cancel / change-plan path (not just an
      // OS-Settings deep link). RevenueCat's CustomerInfo
      // .managementURL routes to the store-specific page; settings
      // wires the tile to _openManageSubscription which prefers RC's
      // URL and falls back to the web upgrade page. /audit/app-store-
      // privacy May 2026 High closeout.
      final source =
          File('lib/screens/settings_pro_screen.dart').readAsStringSync();
      final arb = File('lib/l10n/app_en.arb').readAsStringSync();
      expect(
        source,
        contains('l10n.proManageSubscription'),
        reason: 'settings_pro_screen.dart must surface a "Manage '
            'subscription" tile (localized via l10n.proManageSubscription) so '
            'the user can reach the cancel / change-plan path from inside the '
            'app.',
      );
      expect(
        arb,
        contains('"proManageSubscription": "Manage subscription"'),
        reason: 'app_en.arb must carry the "Manage subscription" tile copy.',
      );
      expect(
        source,
        contains('_openManageSubscription(context)'),
        reason: 'settings_pro_screen.dart must wire the tile to '
            '_openManageSubscription() — a missing wire produces a '
            'visible-but-dead button.',
      );
      expect(
        source,
        contains('await managementUrl('),
        reason: '_openManageSubscription must call managementUrl(...) '
            'to route to RC\'s hosted manage page. A hard-coded URL '
            'would bypass the store-specific cancel paths Apple + Play '
            'require.',
      );
    });

    test('Subscribe-to-Pro tile discloses price + renewal terms', () {
      // Reason: Apple Guideline 3.1.1 + Play subscription policy
      // require price + period + renewal terms + cancellation
      // mechanism to be visible in the app's own UI BEFORE the
      // native purchase sheet. The native sheet repeats it but
      // reviewers expect the in-app prompt to match. The current
      // subtitle includes "$9.99/month" + "Auto-renews monthly until
      // cancelled" — pin both so a future "simplify the copy"
      // refactor can't strip them. /audit/app-store-privacy May 2026.
      final source =
          File('lib/screens/settings_pro_screen.dart').readAsStringSync();
      final arb = File('lib/l10n/app_en.arb').readAsStringSync();
      // Title copy is localized: the screen passes a price into
      // proSubscribeTitle, whose English template is "Subscribe to Pro —
      // {price}/month". The price is the STORE-localised amount (Apple 3.1.1 /
      // Play policy: price varies by territory and must come from the store),
      // with the $9.99 USD list price as a fallback. Pin all three so neither
      // the store-price wiring nor the disclosure can be stripped.
      expect(
        source,
        contains('l10n.proSubscribeTitle(priceLabel)'),
        reason: 'Subscribe-to-Pro tile title must include the price for '
            'App Store + Play in-app disclosure compliance.',
      );
      expect(
        source,
        contains('proMonthlyPriceString('),
        reason: 'Subscribe-to-Pro tile must source the displayed price from '
            'the store (RevenueCat proMonthlyPriceString) — Apple 3.1.1 / Play '
            'policy forbid a hard-coded price that ignores the territory.',
      );
      expect(
        source,
        contains(r"$9.99"),
        reason: 'settings_pro_screen.dart must keep the \$9.99 USD list price '
            'as the fallback shown when RevenueCat is unconfigured or the '
            'offering has not yet loaded.',
      );
      expect(
        arb,
        contains(r'"proSubscribeTitle": "Subscribe to Pro — {price}/month"'),
        reason: 'app_en.arb proSubscribeTitle must keep the "{price}/month" '
            'shape so the price + period stay visible in-app.',
      );
      expect(
        RegExp(r'Auto-renews|cancelled').hasMatch(arb),
        isTrue,
        reason: 'Subscribe-to-Pro tile subtitle must communicate '
            'auto-renewal AND how to cancel — at minimum the words '
            '"Auto-renews" or "cancelled" appear in the ARB copy.',
      );
    });

    test('revenuecat.dart exports a restorePurchases helper', () {
      final source = File('lib/revenuecat.dart').readAsStringSync();
      expect(
        source,
        contains('Future<PurchaseResult> restorePurchases('),
        reason:
            'revenuecat.dart must export a restorePurchases helper so '
            'the settings tile has a single source of truth for the '
            'RC restore flow.',
      );
      expect(
        source,
        contains('Purchases.restorePurchases()'),
        reason: 'restorePurchases must actually call the RC SDK.',
      );
    });
  });

  group('accessibility: watchOS ContentView accessibility hints', () {
    test('watchOS recording-flow buttons carry .accessibilityHint', () {
      // Reason: audit/accessibility (May 2026) High — EU EAA. The
      // watchOS app's primary recording buttons (Start / Pause / Stop /
      // Resume / Recover / Discard / Sync Run) had no
      // .accessibilityHint, leaving VoiceOver users without usage
      // cues on the main recording surface. watch_ios has no XCTest
      // target today, so this is a source-grep guard run from the
      // mobile_android twin's relative path. Auto-skips when the
      // watch_ios sibling isn't present.
      final file = File('../watch_ios/WatchApp/ContentView.swift');
      if (!file.existsSync()) return;
      final body = file.readAsStringSync();
      for (final cue in const [
        // Each cue is a substring from a hint we wrote — checking
        // for the start of each unique sentence is enough to detect
        // a future refactor that drops the modifier.
        'Begins a new run',
        'Pauses the recording without ending it',
        'Ends the run and opens the summary',
        'Resumes the paused recording',
        'Restores the unsaved run',
        'Sends the completed run to your iPhone',
      ]) {
        expect(
          body,
          contains(cue),
          reason:
              'ContentView.swift must carry .accessibilityHint("$cue...") '
              'on the matching button so VoiceOver announces a usage cue. '
              'audit/accessibility Critical.',
        );
      }
    });
  });

  group('accessibility: recording-screen controls have Semantics', () {
    // Reason: audit/accessibility (May 2026) Critical — the
    // Pause / Discard / Lap controls on the recording screen were
    // bare GestureDetector + Container + Icon. TalkBack announces
    // them as their visual content ("delete", an unlabelled circle,
    // a flag) and a screen-reader user has no way to end / pause
    // the run from voice-only mode. Wrap each in Semantics(
    // button: true, label: ...).
    test('Discard / Pause / Lap GestureDetectors are wrapped in Semantics', () {
      final source = File('lib/screens/run_screen.dart').readAsStringSync();
      // Discard + Mark lap labels are localized (gen-l10n) — pin the
      // l10n key references so a refactor that drops the accessible
      // label still trips this guard. (Migrated to AppLocalizations in
      // the i18n run-recording pass; the English copy now lives in the
      // ARB catalogues.)
      for (final key in const [
        'l10n.runDiscardA11yLabel',
        'l10n.runMarkLapA11yLabel',
      ]) {
        expect(
          source,
          contains(key),
          reason: 'run_screen.dart must wrap the matching control in '
              "Semantics(label: $key) so TalkBack / VoiceOver "
              'announce it correctly. audit/accessibility Critical.',
        );
      }
      // Pause/Resume is a toggle: the label flips on `paused` so the
      // announcement reflects current state. Pin the full localized
      // ternary so a future refactor that collapses to a single static
      // label fires this guard.
      expect(
        source,
        contains('paused ? l10n.runResumeA11yLabel : l10n.runPauseA11yLabel'),
        reason: 'Pause/Resume Semantics label must flip on `paused` '
            'so a screen reader announces the current state. '
            'audit/accessibility Critical.',
      );
      // And every one of those labels lives inside a Semantics(...)
      // — a future refactor that moves the label string into a
      // GestureDetector tooltip would silently drop the
      // button-role announcement.
      final semanticsBlocks = RegExp(
        r'Semantics\(\s*button:\s*true[\s\S]*?label:\s*[^,)]+',
      ).allMatches(source).toList();
      expect(
        semanticsBlocks.length,
        greaterThanOrEqualTo(3),
        reason:
            'Expected at least three Semantics(button: true, label:) '
            'blocks for Discard / Pause / Lap. Found '
            '${semanticsBlocks.length}.',
      );
    });

    test('_HoldToStopButton carries Semantics(button, label, onTap) '
        '(audit/accessibility — the most important recording control)', () {
      // Reason: the hold-to-stop button is the only way to end + save a
      // run, but it was a bare Listener + Container + Icon(stop) — the
      // same anti-pattern the May 2026 a11y pass fixed for Discard /
      // Pause / Lap, missed here. A screen-reader user got no name /
      // role, and the sustained-hold gesture is unperformable via
      // double-tap-to-activate, so the control was unreachable in
      // voice-only mode. The fix wraps it in Semantics(button: true,
      // label:, hint:, onTap: widget.onHoldComplete) so the activate
      // gesture routes straight to _stop. Pin all three so a refactor
      // can't silently drop the accessible name or the onTap escape
      // hatch.
      final source = File('lib/screens/run_screen.dart').readAsStringSync();
      final holdBtn = source.substring(
        source.indexOf('class _HoldToStopButtonState'),
      );
      expect(
        holdBtn,
        contains('label: l10n.runStopA11yLabel'),
        reason: '_HoldToStopButton must wrap its visible button in '
            'Semantics(label: l10n.runStopA11yLabel) so TalkBack / '
            'VoiceOver announce it.',
      );
      expect(
        holdBtn,
        contains('onTap: widget.onHoldComplete'),
        reason: '_HoldToStopButton must give the Semantics node an '
            'onTap that fires onHoldComplete — a screen-reader user '
            'cannot perform the sustained hold gesture, so without '
            'this the run can never be stopped in voice-only mode.',
      );
    });

    test('START button on the idle surface carries Semantics(button, label) '
        '(audit/accessibility 2026-05-25 High)', () {
      final source = File('lib/screens/run_screen.dart').readAsStringSync();
      // Reason: pre-fix the START button was a bare GestureDetector →
      // Container → Text('START'). TalkBack announced it as a generic
      // tappable region with no role. Pin the Semantics wrap in place.
      expect(
        source,
        contains('label: l10n.runStartA11yLabel'),
        reason: 'run_screen.dart must wrap the idle-surface START '
            'button in Semantics(label: l10n.runStartA11yLabel). '
            '(Label localized via gen-l10n in the i18n run-recording pass.)',
      );
    });

    test('run-state transitions announce via SemanticsService.announce '
        '(audit/accessibility 2026-05-25 High, WCAG 4.1.3)', () {
      final source = File('lib/screens/run_screen.dart').readAsStringSync();
      expect(
        source,
        contains('SemanticsService.announce'),
        reason: 'run_screen.dart must call SemanticsService.announce '
            'on start / pause / resume / lap / finish transitions so '
            'screen-reader users hear status changes — the TTS audio '
            'cues are gated on a user pref and cannot satisfy '
            'WCAG 4.1.3.',
      );
      // Status phrases are localized (gen-l10n) — pin the l10n key
      // references that feed _announceA11yState so a refactor dropping
      // a status announcement still trips this guard. (Migrated to
      // AppLocalizations in the i18n run-recording pass.)
      for (final key in const [
        '_l10n.runA11yStarted',
        '_l10n.runA11yPaused',
        '_l10n.runA11yResumed',
        '_l10n.runLapMarked(n)',
        '_l10n.runA11yFinished',
      ]) {
        expect(
          source,
          contains(key),
          reason: 'run_screen.dart must announce $key via '
              'SemanticsService.announce — see audit/accessibility '
              '(2026-05-25).',
        );
      }
    });
  });

  group('layered resilience', () {
    test('no silent catch (_) {} sites in lib/', () {
      // Reason: audit/layered-resilience (May 2026) flagged 10
      // `catch (_) {}` sites in lib/. The layered-resilience contract
      // in docs/architecture/conventions.md says every auxiliary catch must do
      // `catch (e) { debugPrint(...) }` so failures stay observable.
      // Silent swallows mask real regressions — a TTS init failure,
      // an integrations refresh that quietly returns nothing, a
      // remote-delete that fails while the local store succeeds.
      //
      // Allowed pattern: `catch (e) { debugPrint(...); ... }` OR
      // `catch (e2) { ... }` (nested), but NEVER `catch (_) {}`.
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;
      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        final body = entity.readAsStringSync();
        final lines = body.split('\n');
        for (var i = 0; i < lines.length; i++) {
          // Match exactly `catch (_) {}` with optional whitespace.
          if (RegExp(r'catch\s*\(\s*_\s*\)\s*\{\s*\}').hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Silent catch (_) {} sites violate the layered-resilience '
            'contract (docs/architecture/conventions.md). Replace with '
            'catch (e) { debugPrint(\'...\'); } so failures stay '
            'observable. Found:\n  ${offenders.join('\n  ')}',
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
      // The viewer-holds-crown banner copy was migrated to the i18n
      // catalogue; pin the localized key wiring instead of the raw
      // English string.
      expect(source.contains('segmentsPanelCrownBanner'), isTrue,
          reason: 'viewer-holds-crown banner copy not wired through l10n');
      final arb =
          File('lib/l10n/app_en.arb').readAsStringSync();
      expect(arb.contains('"segmentsPanelCrownBanner": "You hold this crown'),
          isTrue,
          reason: 'viewer-holds-crown banner copy missing from app_en.arb');
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

    // Since decisions § 744 the wording lives in the ARBs, so each catch
    // path must reach the render-layer helper AND hand it a localizer —
    // a call that resolved the sentence without one would put English in
    // front of every reader, which is the defect that ADR closed.
    test('club_form_sheet imports + calls rateLimitErrorMessage with a '
        'localizer', () {
      final source =
          File('lib/widgets/club_form_sheet.dart').readAsStringSync();
      expect(
        source.contains("import '../rate_limit_message.dart'"),
        isTrue,
        reason: 'club_form_sheet must import rate_limit_message.dart so the '
            'create-club catch path runs through the helper.',
      );
      expect(
        source.contains('rateLimitErrorMessage(l10n,'),
        isTrue,
        reason: 'club_form_sheet catch block must call '
            'rateLimitErrorMessage(l10n, …).',
      );
    });

    test('route_builder_screen imports + renders through rateLimitMessage',
        () {
      final source =
          File('lib/screens/route_builder_screen.dart').readAsStringSync();
      expect(
        source.contains("import '../rate_limit_message.dart'"),
        isTrue,
        reason: 'route_builder_screen must import rate_limit_message.dart '
            'so the saveRoute catch path runs through the helper.',
      );
      expect(
        source.contains('parseRateLimitError('),
        isTrue,
        reason: 'route_builder_screen save catch block must call '
            'parseRateLimitError.',
      );
      expect(
        RegExp(r'rateLimitMessage\(\s*\n?\s*context != null').hasMatch(source),
        isTrue,
        reason: 'formatSaveRouteError must render the refusal through '
            'rateLimitMessage with the caller\'s AppLocalizations when it '
            'has a context.',
      );
    });

    test('report_sheet calls rateLimitErrorMessage with a localizer', () {
      final source = File('lib/widgets/report_sheet.dart').readAsStringSync();
      expect(
        source.contains("import '../rate_limit_message.dart'"),
        isTrue,
        reason: 'report_sheet must import rate_limit_message.dart so the '
            'create_report catch path runs through the helper.',
      );
      expect(
        RegExp(r'rateLimitErrorMessage\(\s*\n?\s*AppLocalizations\.of\(context\)')
            .hasMatch(source),
        isTrue,
        reason: 'report_sheet catch block must call rateLimitErrorMessage '
            'with the sheet\'s AppLocalizations.',
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

    test(
      'run_screen.dart bounds every Supabase / training / social await '
      'with kBackendLoadTimeout',
      () {
        // Reason: the run screen is the most-used surface AND the one
        // where a hung backend has the biggest UX cost — every
        // initState fetch and every finish-flow Supabase call must
        // resolve or fail within a fixed window, or the user can\'t
        // start a run (initState hang blocks idle-card paint) and
        // can\'t leave the finish summary (saveRun hang strands them).
        // Local recording is already isolated from network; this
        // guard pins the timeouts on the small set of backend
        // surfaces that bleed in around the edges.
        //
        // The architecture is: every `await api.X(...)` /
        // `await widget.training.X(...)` / `await widget.social.X(...)`
        // in run_screen.dart must be followed by .timeout(...).
        // Greps for the bare-await pattern to catch any new call
        // that lands without one.
        final source =
            File('lib/screens/run_screen.dart').readAsStringSync();
        // Each pattern is the call name; the asserter checks that
        // every `await api.X(` / `await widget.{training,social}.X(`
        // line has a `.timeout(` somewhere in the next ~5 lines.
        // Method-name only (not `api.X` or `widget.training.X`) so
        // the regex tolerates the wrapped-method-chain style
        // `await api\n  .saveRun(...)\n  .timeout(...)` that dartfmt
        // produces for long arg lists. The semantic the guard cares
        // about — every remote await must be bounded by a timeout —
        // doesn\'t depend on the receiver chain anyway.
        const methodNames = [
          'beginLiveBroadcast',
          'fetchRoutesIntersectingTrack',
          'saveRun',
          'makeRunPublic',
          'makeRunPrivate',
          'concludeLiveBroadcast',
          'fetchPlanForWorkout',
          'fetchActiveOverview',
          'fetchNextRsvpedEvent',
          'fetchMyClubs',
        ];
        for (final name in methodNames) {
          final pattern = RegExp(
            r'\.' + RegExp.escape(name) + r'\s*\([\s\S]{0,400}?\)'
            r'[\s\S]{0,40}?\.timeout\(',
          );
          expect(
            pattern.hasMatch(source),
            isTrue,
            reason: '.$name(...) must be followed by .timeout(...) — '
                'the wrapped-method-chain shape (newline + dot before '
                'timeout) is OK. Backend hangs on this call would '
                'freeze the run-start or finish-summary UI.',
          );
        }
        // Also pin the import + the constant reference so a future
        // refactor that drops backend_timeout.dart triggers this
        // guard, not a runtime regression.
        expect(
          source.contains("import '../backend_timeout.dart';"),
          isTrue,
          reason: 'run_screen.dart must import backend_timeout.dart '
              'for the kBackendLoadTimeout ceiling.',
        );
        expect(
          source.contains('kBackendLoadTimeout'),
          isTrue,
          reason: 'run_screen.dart must reference kBackendLoadTimeout '
              'on its remote awaits.',
        );
      },
    );
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
        tail.contains('title: Text(l10n.routeBuilderMakePublic)'),
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
          reason: 'the push cap is load-bearing and must equal the watch '
              'store\'s LocalRouteStore.MAX_ROUTES, which '
              'scripts/check_shared_constants.mjs reads on both rails; do '
              'not remove the constant');
    });

    test('Phone-side WearRoutesBridge.kt mirrors the Dart channel + path',
        () {
      final file = File(
          'android/app/src/main/kotlin/com/threkir/app/WearRoutesBridge.kt');
      // The Dart `lib/` + `test/` directories are byte-identical
      // between mobile_android and mobile_ios per the twin
      // invariant, but each app has its own native sub-tree.
      // Skip on the iOS twin where there's no `android/` folder.
      if (!file.existsSync()) return;
      final src = file.readAsStringSync();
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
      final file = File(
          'android/app/src/main/kotlin/com/threkir/app/MainActivity.kt');
      if (!file.existsSync()) return;
      final src = file.readAsStringSync();
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

      // Web (TypeScript): routes/map-style-url.ts uses `.trim()` +
      // length check.
      final webSrc =
          File('../web/src/lib/routes/map-style-url.ts').readAsStringSync();
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
              'entry point in docs/ops/protomaps_local_setup.md');

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
      for (final cmd in const ['fetch', 'start', 'restart', 'stop', 'status',
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

    test('Protomaps bootstrap script — bash syntax is clean (bash -n)', () {
      // Run `bash -n` against the script as a CI-friendly syntax
      // check. Catches typos that the existing arch_guards can't
      // (e.g. mismatched quotes, malformed heredocs, unclosed `if`).
      final result = Process.runSync(
        'bash',
        ['-n', 'bin/protomaps-dev.sh'],
        workingDirectory: '../..',
      );
      expect(result.exitCode, 0,
          reason: 'bash -n must pass — stderr was:\n${result.stderr}');
    });

    test('Protomaps bootstrap script — meaningful Docker daemon errors '
        '+ wait-loop log auto-tail', () {
      // The previous version had `docker info >/dev/null 2>&1` which
      // collapsed "daemon down" + "permission denied" + "docker
      // missing" into one "daemon is not running" message. The May
      // 2026 audit round extracted `check_docker_daemon` that
      // distinguishes the cases — pin that helper stays in place.
      //
      // The wait-loop must also call `tail_container_logs` on
      // timeout — otherwise the user gets a useless "check the logs"
      // hint and has to dig through the container manually.
      final body = File('../../bin/protomaps-dev.sh').readAsStringSync();
      expect(body, contains('check_docker_daemon'),
          reason: 'extracted helper must exist + be called from cmd_start');
      expect(body, contains('tail_container_logs'),
          reason: 'auto-tail helper must exist');
      // Specifically, it must fire on wait-loop timeout (i == 30).
      expect(
        body,
        contains(RegExp(
          r'i == 30[\s\S]{0,300}?tail_container_logs',
        )),
        reason: 'wait-loop timeout path must call tail_container_logs '
            'so the user sees real container output, not a generic '
            '"check the logs" hint',
      );
    });

    test('Protomaps bootstrap script — guards against PMTILES_FILE '
        'outside PROTOMAPS_HOME (mount-mismatch footgun)', () {
      // If PMTILES_FILE lives outside PROTOMAPS_HOME, the container
      // can't see the file (only PROTOMAPS_HOME is mounted), and
      // tileserver-gl fails with a confusing "data source not
      // found" error. The May 2026 audit round added a pre-flight
      // check; pin that it stays in place.
      final body = File('../../bin/protomaps-dev.sh').readAsStringSync();
      expect(body, contains('PMTILES_FILE lives outside PROTOMAPS_HOME'),
          reason: 'the mount-mismatch guard must exist — without it, '
              'users with a custom PMTiles path hit an opaque '
              "container-side error");
      // Confirm the guard ACTUALLY compares the two paths.
      expect(
        body,
        contains(RegExp(
          r'pmtiles_dir.*=.*dirname.*PMTILES_FILE',
          dotAll: true,
        )),
        reason: 'guard must compute dirname(PMTILES_FILE) to compare '
            'against PROTOMAPS_HOME',
      );
    });

    test('Web — no map style URL bypasses the override path', () {
      // Reason: a contributor adding a new map surface (style picker,
      // route builder, share-card preview, etc.) might be tempted to
      // construct the MapTiler URL inline rather than threading
      // through `mapStyleUrlFromEnv`. That breaks the
      // PUBLIC_TILE_STYLE_URL override silently — the new surface
      // hits MapTiler with whatever key happens to be set (or 403s
      // with an empty one). Caught on the heatmap/RouteBuilder
      // session: RouteBuilder.svelte had a hardcoded MAP_STYLES dict
      // that bypassed the helper entirely.
      //
      // Pin that every hardcoded `api.maptiler.com/maps/...` URL in
      // a .svelte file goes through the override gate (TILE_STYLE_OVERRIDE
      // ternary). Tests + the canonical builder in `map-style-url.ts`
      // are excluded — those are the override-aware definitions.
      final dir = Directory('../web/src/lib/components');
      if (!dir.existsSync()) return;
      final allowedFiles = <String>{
        // The canonical builder itself.
        'map-style-url.ts',
        // The static-PNG preview helper (returns null when no key).
        'static_map.ts',
        // The geocoding fetch URL is a different MapTiler endpoint;
        // already gated on key presence.
        'geocoding.ts',
        'geocoding_math.ts',
      };
      final offenders = <String>[];
      for (final f in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.svelte'))) {
        final body = f.readAsStringSync();
        if (!body.contains('api.maptiler.com/maps/')) continue;
        // This file has a hardcoded URL. Confirm it ALSO contains
        // either `TILE_STYLE_OVERRIDE` (the in-file ternary) OR
        // `mapStyleUrlFromEnv` (the canonical helper).
        final gated = body.contains('TILE_STYLE_OVERRIDE') ||
            body.contains('mapStyleUrlFromEnv') ||
            body.contains('mapStyleUrl(');
        if (!gated &&
            !allowedFiles.contains(f.path.split('/').last)) {
          offenders.add(f.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'these web map surfaces hardcode the MapTiler URL '
            'without an override gate — they will bypass '
            'PUBLIC_TILE_STYLE_URL silently:\n  '
            "${offenders.join('\n  ')}\n"
            'either use `mapStyleUrlFromEnv` (preferred) or branch '
            'on a `TILE_STYLE_OVERRIDE` env-read like RouteBuilder.svelte.',
      );
    });

    test('Protomaps lifecycle is exposed via root npm scripts', () {
      // Reason: every other dev-time Docker sidecar (Supabase via
      // `dev:db:up` / `down` / `status` / `logs`) is wrapped in
      // root package.json scripts. Protomaps follows the same
      // pattern so developers reach for `npm run dev:tiles:*`
      // by muscle memory.
      final pkg = File('../../package.json').readAsStringSync();
      for (final cmd in const [
        'dev:tiles:fetch',
        'dev:tiles:up',
        'dev:tiles:restart',
        'dev:tiles:down',
        'dev:tiles:status',
        'dev:tiles:logs',
        'dev:tiles:env',
      ]) {
        expect(pkg, contains('"$cmd"'),
            reason: 'root package.json must export `$cmd` so the '
                'lifecycle matches the rest of the dev tooling');
      }
      // Every wrapper must call the bash script directly — no
      // duplicated logic that could drift from the source of
      // truth.
      expect(
        pkg,
        contains(RegExp(r'"dev:tiles:up":\s*"bin/protomaps-dev\.sh start"')),
        reason: 'dev:tiles:up must wrap bin/protomaps-dev.sh start; '
            'duplicating the docker run command in package.json '
            'would drift the moment the bash script gets a new flag',
      );
    });

    test('Protomaps bootstrap script — readiness probe uses /health', () {
      // Reason: tileserver-gl v5 exposes /health (returns "OK" +
      // 200). The May 2026 audit-2 round had a fallback chain
      // (/styles.json OR /) because the upstream docs didn't
      // confirm /health. Live-boot proved it works — Docker's
      // own healthcheck inside the image hits it. Pin the
      // simpler single-curl probe so a future refactor doesn't
      // restore the noisier fallback.
      final body = File('../../bin/protomaps-dev.sh').readAsStringSync();
      expect(
        body,
        contains(RegExp(r'curl\s+-fs\s+"http://localhost:\$\{PROTOMAPS_PORT\}/health"')),
        reason: 'wait-loop must use /health as the probe — the live boot '
            'confirmed it exists despite the earlier audit doubting it',
      );
      // The previous fallback path (`||` of /styles.json + /) must
      // not coexist with the /health probe — we picked the simpler
      // path on purpose.
      expect(
        body,
        isNot(contains(RegExp(r'/styles\.json[^"]*"\s*>/dev/null[\s\S]{0,40}\\\s*$', multiLine: true))),
        reason: 'the /styles.json fallback was redundant after /health '
            'was confirmed — keep the probe to one curl per iteration',
      );
    });

    test('Protomaps bootstrap script — container has --restart '
        'unless-stopped policy', () {
      // Without this flag, a docker daemon reload mid-dev-session
      // silently kills the local tile server. The user keeps
      // hitting the dev URL and gets connection-refused with no
      // visible cause. unless-stopped is the right policy for a
      // dev sidecar — bring it up on demand, keep it up through
      // daemon restarts, but obey explicit `stop`.
      final body = File('../../bin/protomaps-dev.sh').readAsStringSync();
      expect(body, contains('--restart unless-stopped'),
          reason: 'docker run must carry --restart unless-stopped so the '
              'container survives docker daemon reloads');
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
      // See `docs/architecture/decisions.md § 67`.
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

  group('OSRM mobile prod guard', () {
    // Reason: audit/third-party-data-flows (2026-05-25) flagged the
    // mobile route builder for sending production GPS waypoints to
    // the OSRM public demo with no env override or prod guard. The
    // web side has assertOsrmConfiguredForProd() that throws on
    // misconfig; mobile now mirrors that. Without the guards below
    // a refactor could silently re-introduce the leak.
    test('routing.dart wires assertOsrmConfiguredForProd into snapToRoad '
        '+ fetchRouteThrough', () {
      final source = File('lib/routing.dart').readAsStringSync();
      expect(
        source,
        contains('void assertOsrmConfiguredForProd('),
        reason: 'routing.dart must declare assertOsrmConfiguredForProd '
            'so callers can be gated by it.',
      );
      final assertCalls = RegExp(r'\bassertOsrmConfiguredForProd\(\);')
          .allMatches(source)
          .length;
      expect(
        assertCalls,
        greaterThanOrEqualTo(2),
        reason: 'snapToRoad and fetchRouteThrough must both call '
            'assertOsrmConfiguredForProd() before issuing an outbound '
            'HTTP request — see audit/third-party-data-flows.',
      );
    });

    test('routing.dart reads OSRM_URL from dotenv (no hard-coded base)', () {
      final source = File('lib/routing.dart').readAsStringSync();
      expect(
        source,
        contains("dotenv.env['OSRM_URL']"),
        reason: 'routing.dart must read the OSRM endpoint from dotenv '
            'so deployments can point at the self-hosted Fly.io '
            'instance documented in apps/job_worker/osrm/.',
      );
      // The demo URL still appears as the fallback constant; it must
      // NOT appear as a `_kOsrmBase = '...'` const that callers
      // interpolate directly (that was the pre-fix shape).
      expect(
        source.contains("'\$_kOsrmBase/"),
        isFalse,
        reason: 'routing.dart must not interpolate a static '
            '_kOsrmBase — use the dotenv-aware _osrmBaseUrl() helper.',
      );
    });

    test('no source file under lib/ retains the placeholder Nominatim '
        'contact email', () {
      // Reason: audit/third-party-data-flows (2026-05-25) flagged the
      // Nominatim email as a placeholder from a different project.
      // OSM's usage policy requires a reachable contact address;
      // hard-pin the regression here so it never reappears. The
      // placeholder string is reconstructed at runtime so this
      // assertion source doesn't trigger itself.
      final placeholder =
          'protomaps' + '-dev' + '@' + 'localhost';
      final hits = <String>[];
      final entries = Directory('lib').listSync(recursive: true);
      for (final entry in entries) {
        if (entry is! File) continue;
        if (!entry.path.endsWith('.dart')) continue;
        final body = entry.readAsStringSync();
        if (body.contains(placeholder)) {
          hits.add(entry.path);
        }
      }
      expect(
        hits,
        isEmpty,
        reason: 'OSM Foundation usage policy requires a reachable '
            'contact email on Nominatim requests. Use '
            'privacy@threkir.com instead of the placeholder shipped '
            'from a different project.',
      );
    });
  });

  group('Sentry opt-out gate (audit/gdpr May 2026 High)', () {
    // The Sentry init in main.dart MUST consult prefs.sentryOptOut
    // before SentryFlutter.init runs, or the Settings toggle is a
    // lie. Pin the call shape so a future refactor that splits the
    // init into a helper file is still caught.

    test('main.dart gates SentryFlutter.init on prefs.sentryOptOut', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(
        src.contains('!prefs.sentryOptOut'),
        isTrue,
        reason: 'main.dart must compute `shouldUseSentry` against '
            'prefs.sentryOptOut — otherwise the Settings → Privacy '
            'toggle does not stop Sentry from initialising.',
      );
      // Pin the order: the boolean composition must happen BEFORE
      // the `if (shouldUseSentry) SentryFlutter.init(...)` call.
      final gateIdx = src.indexOf('!prefs.sentryOptOut');
      final initIdx = src.indexOf('SentryFlutter.init');
      expect(
        gateIdx >= 0 && initIdx > gateIdx,
        isTrue,
        reason: 'The opt-out check must precede SentryFlutter.init.',
      );
    });
  });

  group('live cut-off wiring', () {
    test('_loadCutoffLegs anchors cutoff clocks to the run start', () {
      // `cutoff_clock` is the ONLY cut-off field either editor can author,
      // and buildRoadbook resolves a clock into an elapsed limit only when it
      // is given the start's minute-of-day (roadbook_test pins that
      // contract). Without startClockMin every cut-off leg came back null, so
      // _cutoffLegs stayed empty and the live CutoffCard + the cut-off
      // catch-up voice cue never fired for any real course.
      final source = File('lib/screens/run_screen.dart').readAsStringSync();
      final start = source.indexOf('Future<void> _loadCutoffLegs() async {');
      expect(start, isNonNegative);
      final body = source.substring(start, source.indexOf('.legs;', start));
      expect(
        body,
        contains('startClockMin: _startClockMin()'),
        reason: 'buildRoadbook must be given the start clock or no '
            'cutoff_clock marker ever produces a cutoff.',
      );
      // The legs are built while staging, before the real start exists, so
      // both entry points into a running state must rebuild them.
      expect(
        RegExp(r'_runStartedAtWall = DateTime\.now\(\);\s*\n(\s*//[^\n]*\n)*\s*_loadCutoffLegs\(\);')
            .hasMatch(source),
        isTrue,
        reason: 'starting a run must re-run _loadCutoffLegs against the real '
            'start clock.',
      );
      expect(
        RegExp(r'_runStartedAtWall = partial\.startedAt;\s*\n(\s*//[^\n]*\n)*\s*_loadCutoffLegs\(\);')
            .hasMatch(source),
        isTrue,
        reason: 'resuming a partial run must re-anchor the cutoff clocks to '
            'when that run actually began.',
      );
    });
  });

  group('club event-creation gate matches the server role', () {
    test('the events tab gates on isEventOrganiser, not isAdmin', () {
      // is_event_organiser (20260428_001) admits owner / admin /
      // event_organiser, and web's canManageEvents matches. Gating the mobile
      // create affordance on isAdmin locked the one role that exists to run
      // events out of creating them — on mobile only.
      final src = File('lib/screens/club_detail_screen.dart').readAsStringSync();
      expect(src, contains('final showCreate = c.isEventOrganiser;'));
      expect(
        src.contains('final showCreate = c.isAdmin;'),
        isFalse,
        reason: 'isAdmin excludes event_organiser',
      );
    });
  });

  group('pedometer baseline on resume', () {
    test('an explicit flag marks the baseline, not a zero sentinel', () {
      // `_startSteps == 0` doubled as "not baselined yet". On resume the
      // computed baseline is legitimately 0 whenever no sensor event has
      // landed — the counter only ticks on a real step, and the runner is
      // usually still reading the Resume dialog — so the next event
      // re-baselined to the raw cumulative reading and the steps carried over
      // from the crashed run were lost. For an indoor run that is the whole
      // reported distance, since it is derived as steps x stride.
      final src = File('lib/screens/run_screen.dart').readAsStringSync();
      expect(
        src.contains('if (_startSteps == 0) _startSteps = event.steps;'),
        isFalse,
        reason: 'the zero sentinel must be gone',
      );
      expect(src, contains('if (!_stepBaselineSet) {'));
      expect(
        src,
        contains('_startSteps = event.steps - _stepsCarriedIn;'),
        reason: 'the deferred baseline must subtract the carried-in steps so a '
            'resumed run continues from them',
      );
      // Resume seeds the carry-in; a fresh start clears it.
      expect(src, contains('_stepsCarriedIn = restoredSteps;'));
      expect(src, contains('_stepsCarriedIn = 0;'));
    });
  });

  group('sign-out clears the watch route list', () {
    test('signedOut re-pushes the routes bridge', () {
      // LocalRouteStore hides another account's tagged routes once the
      // provider reports signed-out, but WearRoutesBridge only pushes on a
      // store mutation — signing out isn't one. Without an explicit nudge the
      // paired watch keeps a previous account's starred route names and
      // waypoints until some unrelated future edit fires the listener.
      final src = File('lib/main.dart').readAsStringSync();
      final signedOut = src.indexOf('event.event == AuthChangeEvent.signedOut');
      expect(signedOut, isNonNegative,
          reason: 'signedOut handler not found — update this guard');
      // The handler is long (comments); take everything up to the bootstrap
      // attach that follows the auth listener.
      final block = src.substring(
          signedOut, src.indexOf('WearAuthBridge().attach(', signedOut));
      expect(
        block,
        contains('WearRoutesBridge().attach(routeStore);'),
        reason: 'sign-out must re-push the (now owner-filtered) route list',
      );
    });
  });

  group('crash recovery is owner-tagged', () {
    test('the owner-tag providers are wired before the recovery save', () {
      // LocalRunStore.save only stamps created_by_user_id when
      // currentUserIdProvider is set, and the in-progress file is never
      // tagged while recording. Recovering before the provider was wired left
      // the run untagged, and filterRunsForCurrentUser reads an untagged run
      // as adoptable — so on a shared device the next account to sign in
      // pushed a previous user's crashed run as its own (§67).
      final src = File('lib/main.dart').readAsStringSync();
      final provider = src.indexOf('store.currentUserIdProvider = () => api?.userId;');
      final recover = src.indexOf('await store.save(evaluation.recovered!);');
      expect(provider, isNonNegative);
      expect(recover, isNonNegative);
      expect(
        provider < recover,
        isTrue,
        reason: 'in-progress recovery must run after the owner tag is wired, '
            'or the recovered run is adoptable by the next account.',
      );
    });
  });

  group('every OfflineSyncStore subclass is wiped on sign-out', () {
    // Reason (issue #228): sign-out used to clear only the three
    // app-singleton stores, so the screen-owned routine / meal-template /
    // recipe / crossings stores survived — a different user signing in on
    // the same device both SAW the prior user's rows and ADOPTED them
    // (replaceFromServer preserves pendingCreate rows; syncWithServer
    // pushes them into the new account). The crossings store carries bibs
    // and, behind WEIGH_IN_GATE, medical weigh-in fields. A NEW
    // OfflineSyncStore subclass must land in one of the two wipe lists:
    // main.dart's app-singleton clear, or buildScreenOwnedOfflineStores()
    // in offline_store_wipe.dart.
    test('each subclass appears in a sign-out wipe list', () {
      final subclassNames = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        for (final m in RegExp(r'class\s+(\w+)\s+extends\s+OfflineSyncStore<')
            .allMatches(src)) {
          subclassNames.add(m.group(1)!);
        }
      }
      expect(subclassNames, isNotEmpty,
          reason: 'the subclass scan itself must find the stores');

      final mainSrc = File('lib/main.dart').readAsStringSync();
      final wipeSrc = File('lib/offline_store_wipe.dart').readAsStringSync();
      // main.dart holds singletons as `final xStore = LocalXStore()`;
      // the registry constructs `LocalXStore(),`. Either counts as wired.
      for (final name in subclassNames) {
        final constructed = RegExp('$name\\(\\)');
        expect(
          constructed.hasMatch(mainSrc) || constructed.hasMatch(wipeSrc),
          isTrue,
          reason: '$name is an OfflineSyncStore subclass but is neither an '
              'app-singleton cleared in main.dart nor listed in '
              'buildScreenOwnedOfflineStores() — its rows would survive '
              'sign-out and leak to (and be adopted by) the next account.',
        );
      }
    });
  });

  group('a screen-owned OfflineSyncStore is init()ed, never only loadAll()ed',
      () {
    // Reason (followups 2026-08-18): `nutrition_screen.dart` constructed its
    // meal-template + recipe stores and called `loadAll()` on them. `loadAll`
    // tolerates a null `dir` and returns, so the store read as alive while
    // every write refused — a saved meal or recipe lived in memory for the
    // session and reached neither disk nor the server. Only `init()` resolves
    // the directory, so a screen that owns one of these stores must call it.
    test('every field holding one calls init() on it', () {
      final sources = <String, String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        sources[entity.path] = entity.readAsStringSync();
      }
      final storeTypes = <String>{};
      for (final src in sources.values) {
        for (final m
            in RegExp(r'class\s+(\w+)\s+extends\s+OfflineSyncStore<')
                .allMatches(src)) {
          storeTypes.add(m.group(1)!);
        }
      }
      expect(storeTypes, isNotEmpty,
          reason: 'the subclass scan itself must find the stores');

      final offenders = <String>[];
      sources.forEach((path, src) {
        for (final m in RegExp(r'(\w+)\s*=\s*(\w+)\(\)').allMatches(src)) {
          final field = m.group(1)!;
          if (!storeTypes.contains(m.group(2)!)) continue;
          if (RegExp('${RegExp.escape(field)}\\.init\\(').hasMatch(src)) {
            continue;
          }
          offenders.add('$path: $field');
        }
      });
      expect(offenders, isEmpty,
          reason: 'these fields hold an OfflineSyncStore that is never '
              'init()ed, so every write to them refuses and the rows never '
              'reach disk or the server: ${offenders.join(', ')}');
    });
  });

  group('every replaceFromServer refuses before it touches rowsById', () {
    // Reason (followups 2026-08-18): `rewriteAll` used to return silently on a
    // null `dir`, so a cache fill on a never-init()ed store replaced the
    // resident rows and wrote nothing. Gating `rewriteAll` alone is too late —
    // each `replaceFromServer` has already rebuilt `rowsById` from the fetch by
    // the time it calls down, so the refusal has to be the method's first
    // statement or a failed fill leaves a half-replaced store behind.
    // The scan finds a DECLARATION by its name and its parameter list, not by
    // its return type or an `async` keyword, and it walks the parameter list's
    // own parentheses to reach the body. Anchoring on `Future<void> ` and then
    // on the next `async` left three measured holes, each of which passes an
    // ungated override: a non-async override skipped forward to the next
    // `async` method in the file and read THAT body's first statement; an
    // override returning anything but `Future<void>` was not found at all,
    // with the count floor still met by its seven siblings; and the gate's
    // argument was never read, so one naming another method refused under a
    // name its caller never called.
    test('requireInitialised is the first statement of each override', () {
      final offenders = <String>[];
      final found = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        var from = 0;
        while (true) {
          final at = src.indexOf('replaceFromServer(', from);
          if (at < 0) break;
          from = at + 1;
          final before = src.substring(0, at).trimRight();
          if (before.endsWith('.') || before.endsWith('`')) continue;
          var depth = 0;
          var i = src.indexOf('(', at);
          for (; i < src.length; i++) {
            if (src[i] == '(') depth++;
            if (src[i] == ')') {
              depth--;
              if (depth == 0) break;
            }
          }
          final open = src.indexOf('{', i);
          if (i >= src.length || open < 0) {
            offenders.add('${entity.path}: unparseable signature');
            continue;
          }
          found.add(entity.path);
          final firstStatement = src.substring(open + 1).trimLeft();
          if (!firstStatement
              .startsWith("requireInitialised('replaceFromServer');")) {
            offenders.add(entity.path);
          }
        }
      }
      expect(found.length, greaterThanOrEqualTo(7),
          reason: 'the scan itself must find the replaceFromServer overrides, '
              'found: ${found.join(', ')}');
      expect(offenders, isEmpty,
          reason: 'these replaceFromServer overrides rebuild rowsById before '
              'anything checks the store was init()ed, so a fill that can '
              'never reach disk still replaces what the screen is showing: '
              '${offenders.join(', ')}');
    });
  });

  group('local-day arithmetic is DST-safe', () {
    // A calendar week spanning a DST transition is 167 or 169 hours, so
    // stepping days with a fixed Duration walks the boundary off local
    // midnight: a run in the seam is then counted in both adjacent weeks
    // (spring forward) or in neither (fall back), and disappears from the
    // weekly goal, the dashboard "This week" card, the runs-screen week filter
    // and both weekly period-summary pages. The web twin
    // (apps/web/src/lib/training/goals.ts) uses setDate(), which is calendar
    // arithmetic — Dart's equivalent is the year/month/day constructor, as
    // streaks.dart's _previousLocalDay already documents.
    //
    // The behavioural proof lives in goals_test.dart's "DST safety" group, but
    // it can only fail in a DST timezone and CI runs UTC — so these source
    // guards are what actually catch a regression.
    const weekBoundaryFns = <String, String>{
      'lib/goals.dart': r'DateTime weekStartLocal\(DateTime now, '
          r'\{String weekStartDay = .monday.\}\) \{',
      'lib/screens/period_summary_screen.dart':
          r'DateTime periodEnd\(PeriodType period, DateTime anchor,\s*'
          r'\{String weekStartDay = .monday.\}\) \{',
      // The trend chart buckets weekly the same way; a skewed Monday mislabels
      // the bars and drops the transition week out of the chart entirely.
      'lib/mileage_trend.dart': r'DateTime _mondayOf\(DateTime d\) \{',
    };

    weekBoundaryFns.forEach((path, signature) {
      test('$path steps week boundaries with the Y/M/D constructor', () {
        final source = File(path).readAsStringSync();
        final body = _extractMethodBody(source, signature);
        expect(
          body.contains('Duration(days:'),
          isFalse,
          reason: 'a fixed 24-hour day skews on a DST transition — use '
              'DateTime(y, m, d ± n), see streaks.dart _previousLocalDay',
        );
      });
    });

    test('goalPeriodEnd steps a week with the Y/M/D constructor', () {
      final source = File('lib/goals.dart').readAsStringSync();
      final body = _extractMethodBody(
        source,
        r'DateTime goalPeriodEnd\(GoalPeriod period, DateTime now,\s*'
        r'\{String weekStartDay = .monday.\}\) \{',
      );
      expect(
        body.contains('start.day + 7'),
        isTrue,
        reason: 'the exclusive week end must be constructed from the start',
      );
      expect(
        body.contains('Duration(days:'),
        isFalse,
        reason: 'a fixed 7×24 h week skews on a DST transition',
      );
    });

    test('weekStartLocal itself uses the Y/M/D constructor', () {
      final source = File('lib/goals.dart').readAsStringSync();
      final body = _extractMethodBody(
        source,
        r'DateTime weekStartLocal\(DateTime now, '
        r'\{String weekStartDay = .monday.\}\) \{',
      );
      expect(
        body.contains('DateTime(now.year, now.month, now.day - daysFromStart)'),
        isTrue,
        reason: 'the week start must be constructed, not offset by a Duration',
      );
    });

    test('the trend chart steps back a week with the Y/M/D constructor', () {
      final body = _extractMethodBody(
        File('lib/mileage_trend.dart').readAsStringSync(),
        r'DateTime _previousBucketStart\(DateTime d, MileageView view\) \{',
      );
      expect(
        body.contains('DateTime(d.year, d.month, d.day - 7)'),
        isTrue,
        reason: 'the previous week bucket must be constructed from the start',
      );
      expect(
        body.contains('Duration(days:'),
        isFalse,
        reason: 'a fixed 7×24 h week labels the back-filled bars a week early',
      );
    });
  });

  group('remote images always carry a failure path', () {
    // Every avatar in the app used to be hand-rolled, and four of the six
    // painted the picture through a `DecorationImage` — which has no error
    // hook at all — while gating the initial-letter child on the URL being
    // absent. A failed load therefore suppressed the fallback and rendered
    // a solid coloured circle with nothing in it. The same trap exists on
    // `CircleAvatar.backgroundImage`, which paints over its child rather
    // than under it. ui_kit's IdentityAvatar layers the picture over the
    // initial instead, so a decode or network failure degrades to the
    // letter (decisions.md § 492).
    late List<File> sources;
    setUpAll(() {
      sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    });

    test('no surface paints a remote image through DecorationImage', () {
      final offenders = <String>[
        for (final f in sources)
          if (f.readAsStringSync().contains('DecorationImage(')) f.path,
      ];
      expect(offenders, isEmpty,
          reason: 'DecorationImage cannot report a load failure — layer an '
              'Image with an errorBuilder over the fallback instead');
    });

    test('no CircleAvatar hides its fallback behind a backgroundImage', () {
      final offenders = <String>[
        for (final f in sources)
          if (f.readAsStringSync().contains('backgroundImage:')) f.path,
      ];
      expect(offenders, isEmpty,
          reason: 'CircleAvatar paints backgroundImage over its child, so a '
              'failed load shows an empty disc — use IdentityAvatar');
    });

    test('every avatar routes through ui_kit IdentityAvatar', () {
      final offenders = <String>[
        for (final f in sources)
          if (f.readAsStringSync().contains('NetworkImage(')) f.path,
      ];
      expect(offenders, isEmpty,
          reason: 'a bare NetworkImage has no errorBuilder of its own — use '
              'IdentityAvatar for identities, Image.network elsewhere');
    });
  });

  group('a loading surface names what is coming', () {
    // A bare `Center(child: CircularProgressIndicator())` tells the user only
    // that something is happening: it occupies none of the space the content
    // will, so the arriving frame lands as a re-layout rather than a fill.
    // Round 7 shipped the two named treatments (`ListSkeleton` for a row-
    // shaped surface, `FullBodyLoader` for a mixed one) and converted 16 of
    // the 30 sites; round 10 closed the remaining 14 (decisions.md § 492).
    // The trap is not a bug in one file — it is the shape every screen
    // reached for because there was nothing named to reach for.
    late List<File> sources;
    setUpAll(() {
      sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    });

    test('no surface loads behind a bare centred spinner', () {
      final offenders = <String>[
        for (final f in sources)
          if (f.readAsStringSync().contains(
              'Center(child: CircularProgressIndicator())'))
            f.path,
      ];
      expect(offenders, isEmpty,
          reason: 'use ListSkeleton where the surface is rows, '
              'ListSkeleton.section where it is one section of a scrollable, '
              'FullBodyLoader where the layout is mixed');
    });

    test('no screen hand-rolls its own empty state', () {
      final offenders = <String>[
        for (final f in sources)
          if (RegExp(r'class \w*EmptyState\b')
              .hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(offenders, isEmpty,
          reason: 'ui_kit EmptyState owns the icon/title/body proportions and '
              'the bounded-vs-unbounded host contract (decisions.md § 485)');
    });
  });

  group('destructive confirms carry error emphasis', () {
    // Rounds 4-7 fixed emphasis dialog by dialog, which left the decision
    // living at 88 call sites: 21 marked the confirm with colorScheme.error
    // and a comparable number of equally irreversible ones did not, because
    // nothing forced the question to be asked. `confirmDestructive` now owns
    // the shape; this guard owns the classification, so a new destructive
    // dialog cannot ship unmarked by accident. A dialog is exempt only by
    // being named here with a reason (issue #666 C11).
    //
    // The line: destructive means it destroys data, or a relationship the
    // user cannot restore on their own — delete, remove, clear, erase,
    // discard, revoke, unlink, deny, leave. Merely consequential is not
    // destructive: reconnecting an integration, un-archiving a conversation,
    // replacing an active plan, an upsert-only restore.

    /// Index just past the bracket matching the one opening at [start],
    /// skipping string literals and line comments.
    int matchBlock(String src, int start) {
      var depth = 0;
      var i = start;
      while (i < src.length) {
        final c = src[i];
        if (c == "'" || c == '"') {
          final q = c;
          i++;
          while (i < src.length) {
            if (src[i] == r'\') {
              i += 2;
              continue;
            }
            if (src[i] == q) break;
            i++;
          }
          i++;
          continue;
        }
        if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
          while (i < src.length && src[i] != '\n') {
            i++;
          }
          continue;
        }
        if (c == '(' || c == '[' || c == '{') {
          depth++;
        } else if (c == ')' || c == ']' || c == '}') {
          depth--;
          if (depth == 0) return i + 1;
        }
        i++;
      }
      return src.length;
    }

    /// A nested AlertDialog is its own entry; strip it so a nested confirm's
    /// emphasis is never credited to the dialog that contains it.
    String stripNested(String block) {
      var out = block;
      while (true) {
        final m = RegExp('AlertDialog[(]').firstMatch(out.substring(1));
        if (m == null) return out;
        final open = m.start + 1 + 'AlertDialog'.length;
        out = out.substring(0, m.start + 1) + out.substring(matchBlock(out, open));
      }
    }

    /// "<lib-relative path>::<title expression>" for every AlertDialog in
    /// `lib/` whose actions block carries no error emphasis.
    Map<String, int> unemphasised() {
      final counts = <String, int>{};
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final src = f.readAsStringSync();
        for (final m in RegExp('AlertDialog[(]').allMatches(src)) {
          final open = m.start + 'AlertDialog'.length;
          final block = stripNested(src.substring(open, matchBlock(src, open)));
          final am = RegExp(r'\bactions:\s*[<\w>\s]*\[').firstMatch(block);
          var actions = '';
          if (am != null) {
            final lb = block.indexOf('[', am.start);
            actions = block.substring(lb, matchBlock(block, lb));
          }
          if (RegExp(r'colorScheme\.error|AppSemanticColors|\.danger')
              .hasMatch(actions)) {
            continue;
          }
          final tm =
              RegExp(r'title:\s*(?:const\s*)?Text\(([^\n]*)').firstMatch(block);
          var title = (tm?.group(1) ?? '').trim();
          if (title.endsWith('),')) {
            title = title.substring(0, title.length - 2);
          } else if (title.endsWith(',')) {
            title = title.substring(0, title.length - 1);
          }
          final rel = f.path.startsWith('lib/') ? f.path.substring(4) : f.path;
          final key = '$rel::${title.isEmpty ? '(no title)' : title}';
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
      return counts;
    }

    // Reviewed 2026-08-05 and found non-destructive: each is a form, a
    // reversible toggle, a prompt, or an action the same user can undo from
    // the same surface. Adding a row here is a claim that the dialog does not
    // destroy anything — make it deliberately.
    const exempt = <String, int>{
      // Recoverable: the archive drawer un-archives it.
      'screens/coach_screen.dart::l10n.coachArchiveTitle': 1,
      // Rename / create / edit prompts and forms.
      'screens/devices_screen.dart::l10n.devicesRenameTitle': 1,
      'screens/gear_rotations_screen.dart::title': 1,
      'screens/races_screen.dart::l.racesEditorTitle': 1,
      'screens/races_screen.dart::widget.race.name': 1,
      'screens/roadbook_screen.dart::l10n.roadbookPlanTitle': 1,
      'screens/route_builder_screen.dart::l10n.routeBuilderGenerateLoop': 1,
      'screens/route_builder_screen.dart::l10n.routeBuilderSaveDialogTitle': 1,
      'screens/route_detail_screen.dart::l10n.routeDetailRateDialogTitle': 1,
      'screens/run_detail_screen.dart::l10n.runDetailEditTitle': 1,
      'screens/settings_account_screen.dart::l10n.settingsAccountDisplayName': 1,
      'screens/settings_preferences_screen.dart::l10n.prefsTargetPace': 1,
      'screens/settings_preferences_screen.dart::l10n.prefsHrZonesDialogTitle': 1,
      'screens/settings_preferences_screen.dart::title': 3,
      'screens/settings_safety_screen.dart::l10n.safetyTitle': 1,
      'screens/workout_detail_screen.dart::l10n.workoutRelinkTitle': 1,
      'widgets/fitness_card.dart::label': 1,
      // Grants AI-processing consent: accepting writes a consent record and
      // nothing else, cancelling leaves the runner exactly where they were,
      // and the account screen's withdrawal control reverses either way.
      'widgets/ai_disclosure_notice.dart::l10n.coachConsentHeadline': 1,
      'widgets/nutrition_log_sheet.dart::widget.result.name': 1,
      'screens/nutrition_screen.dart::l10n.nutritionSaveAsMealTitle': 1,
      'screens/nutrition_screen.dart::l10n.nutritionSaveAsRecipeTitle': 1,
      // Copies rather than replaces; the source plan is untouched.
      'screens/plan_detail_screen.dart::dl10n.planDetailDuplicateConfirmTitle': 1,
      // The displaced plan keeps every workout and stays readable.
      'screens/plan_new_screen.dart::l10n.planNewReplaceActiveTitle': 1,
      // Abandon: a status change, not a deletion.
      'screens/plans_screen.dart::title': 1,
      // Visibility toggles and a share that only widens visibility.
      'screens/route_detail_screen.dart::l10n.routeDetailShareConfirmTitle': 1,
      'screens/run_detail_screen.dart::l10n.runDetailMakePrivateTitle': 1,
      'screens/run_detail_screen.dart::l10n.runDetailMakePublicTitle': 1,
      'screens/run_detail_screen.dart::l10n.runDetailSaveAsRouteTitle': 1,
      // Recording nudges and prompts; none of them discards a run.
      'screens/run_screen.dart::_l10n.runBackgroundLocationNudgeTitle': 1,
      'screens/run_screen.dart::_l10n.runBatteryOptHintTitle': 1,
      'screens/run_screen.dart::_l10n.runLiveShareEndedTitle': 1,
      'screens/run_screen.dart::_l10n.runResumeDialogTitle': 1,
      // Credential changes the user is performing on purpose.
      'screens/settings_account_screen.dart::l10n.settingsAccountChangeEmail': 1,
      'screens/settings_account_screen.dart::l10n.settingsAccountChangePassword': 1,
      // Restore is an upsert — it never deletes a run or route absent from
      // the backup, and the copy says so.
      'screens/settings_account_screen.dart::l10n.settingsAccountRestoreTitle': 1,
      // Every integration here reconnects in one tap.
      'screens/settings_integrations_screen.dart::(no title)': 1,
      'screens/settings_integrations_screen.dart::l10n.integrationsHrTitle': 1,
      'screens/settings_integrations_screen.dart::l10n.integrationsParkrunTitle': 1,
      'screens/settings_integrations_screen.dart::l10n.integrationsStravaDisconnectTitle': 1,
      'screens/settings_integrations_screen.dart::l10n.integrationsTreadmillTitle': 1,
      // Chooses how far back a Strava sync reaches. Imports are additive and
      // deduped against what is already there, so a wider window can only add
      // runs — there is nothing here to lose.
      'screens/settings_integrations_screen.dart::l10n.integrationsStravaLookbackTitle': 1,
    };

    test('no AlertDialog outside the reviewed set omits error emphasis', () {
      final found = unemphasised();
      final unreviewed = {
        for (final e in found.entries)
          if (!exempt.containsKey(e.key)) e.key: e.value,
      };
      expect(unreviewed, isEmpty,
          reason: 'a new AlertDialog has an unemphasised confirm. If it is '
              'destructive, route it through confirmDestructive; if it is '
              'not, add it to `exempt` with the reason it cannot lose data');
    });

    test('the reviewed set has not silently grown or shrunk', () {
      final found = unemphasised();
      for (final e in exempt.entries) {
        expect(found[e.key], e.value,
            reason: '${e.key} changed shape — re-check whether it is still a '
                'non-destructive dialog before adjusting the count');
      }
    });

    test('no list row hides a destructive action behind a swipe', () {
      // Swipe-to-delete existed on exactly one surface (the coach archive
      // drawer), which taught a gesture that worked nowhere else and hid
      // deletion from anyone who never tried it — and its confirmDismiss ran
      // the delete rather than asking. Rows use the overflow menu instead;
      // top_banner's Dismissible dismisses a banner, which destroys nothing
      // (issue #666 U7).
      final offenders = <String>[
        for (final f in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          if (f.path != 'lib/widgets/top_banner.dart' &&
              f.readAsStringSync().contains('Dismissible('))
            f.path,
      ];
      expect(offenders, isEmpty,
          reason: 'a swipe is undiscoverable and unlabelled — put the '
              'destructive action in a PopupMenuButton and confirm it');
    });

    test('confirmDestructive is the only destructive-dialog builder', () {
      final src =
          File('lib/widgets/confirm_destructive.dart').readAsStringSync();
      // Cancel first, unstyled; the confirm second, carrying the error colour.
      expect(
        src.indexOf('cancelLabel ?? l10n.commonCancel'),
        lessThan(src.indexOf('colorScheme.error')),
        reason: 'cancel must stay the first action so a reflex tap is safe',
      );
      expect(
        File('lib/widgets/confirm_discard.dart').readAsStringSync(),
        contains('confirmDestructive('),
        reason: 'confirmDiscard must not grow a second AlertDialog of its own',
      );
    });
  });

  group('a FAB never covers the last row of the list it floats over', () {
    // A `FloatingActionButton` is painted over the body, so a scroll view
    // beneath one has to reserve room for it or its last row is unreachable.
    // Round 9 of the issue #666 audit found four screens reserving none and
    // six reserving four different guessed values, none of which matched what
    // Scaffold actually does. `fabScrollClearance` is the measured answer.
    test('every screen with a scrolling FAB body uses fabScrollClearance', () {
      // Screens whose FAB floats over something that does not scroll — a map
      // — have no last row to cover.
      const nonScrolling = {
        'lib/screens/privacy_zones_screen.dart',
        'lib/screens/route_builder_screen.dart',
      };
      // Hosts that hoist a sub-screen's FAB into their own Scaffold. The
      // clearance belongs to the list, which lives in the sub-screen.
      const hoists = {
        'lib/screens/home_screen.dart',
        'lib/screens/social_screen.dart',
      };
      final offenders = [
        for (final f in Directory('lib/screens')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          if (!nonScrolling.contains(f.path) && !hoists.contains(f.path))
            if (f.readAsStringSync().contains('floatingActionButton:') &&
                !f.readAsStringSync().contains('fabScrollClearance('))
              f.path,
      ];
      expect(offenders, isEmpty,
          reason: 'reserve fabScrollClearance(context) at the end of the '
              'scroll view, or add the screen to one of the lists above');
    });

    test('no screen hard-codes its own FAB clearance', () {
      final offenders = <String>[];
      for (final f in Directory('lib/screens')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (!src.contains('fabScrollClearance(')) continue;
        if (RegExp(r'viewPaddingOf\(context\)\.bottom').hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'fabScrollClearance already folds in the system inset — a '
              'second viewPadding read double-counts it');
    });
  });
  group('deferred-commit undo outlives its surface', () {
    // Reason: the undo queue is a top-level singleton whose timer belongs to
    // it, not to any State, so a `commit` scheduled from a screen keeps running
    // after that screen is popped (decisions § 514 + the mobile host note in
    // lib/widgets/undo_bar.dart). Two consequences have to hold at every call
    // site or a route pop turns into either a lost row or a crash:
    //
    //   * `commit` may not touch a BuildContext — it runs when the surface may
    //     already be gone, so anything localized has to be resolved at defer
    //     time and handed in as `message`.
    //   * `restore` may not setState unguarded — it runs on undo AND on a
    //     commit failure, either of which can land after a pop.
    //
    // The guard reads the arguments positionally, which is also why the
    // convention is message / commit / restore / onCommitError in that order.

    /// The body of `DeferredDestruction( ... )` for every call, by paren match.
    List<String> _destructions(String src) {
      final blocks = <String>[];
      for (final m in RegExp(r'DeferredDestruction\(').allMatches(src)) {
        var depth = 1;
        var i = m.end;
        while (i < src.length && depth > 0) {
          if (src[i] == '(') depth++;
          if (src[i] == ')') depth--;
          i++;
        }
        blocks.add(src.substring(m.end, i - 1));
      }
      return blocks;
    }

    Iterable<File> _adopters() => [
          ...Directory('lib/screens').listSync(recursive: true),
          ...Directory('lib/widgets').listSync(recursive: true),
        ].whereType<File>().where((f) =>
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('deferDestructive('));

    test('every adopting surface exists and is found by the guard', () {
      expect(_adopters(), isNotEmpty,
          reason: 'the guard silently passes if the call-site search breaks — '
              'rename deferDestructive and this fails first');
    });

    test('no commit closure reads a BuildContext', () {
      final offenders = <String>[];
      for (final f in _adopters()) {
        for (final block in _destructions(f.readAsStringSync())) {
          final start = block.indexOf('commit:');
          final end = block.indexOf('restore:');
          if (start < 0 || end < start) {
            offenders.add('${f.path} (commit:/restore: not in order)');
            continue;
          }
          if (block.substring(start, end).contains('context')) {
            offenders.add('${f.path} (commit reads context)');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a deferred commit runs after the surface may have been '
              'popped; resolve strings at defer time. Offenders: $offenders');
    });

    test('every restore closure is mount-guarded', () {
      final offenders = <String>[];
      for (final f in _adopters()) {
        for (final block in _destructions(f.readAsStringSync())) {
          final start = block.indexOf('restore:');
          if (start < 0) {
            offenders.add('${f.path} (no restore)');
            continue;
          }
          final onError = block.indexOf('onCommitError:');
          final body =
              block.substring(start, onError > start ? onError : block.length);
          if (!body.contains('mounted')) {
            offenders.add('${f.path} (unguarded restore)');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'restore runs on undo and on a commit failure, either of '
              'which can land after a pop. Offenders: $offenders');
    });

    test('the host is a root overlay entry, never a SnackBar', () {
      final src = File('lib/widgets/undo_bar.dart').readAsStringSync();
      expect(src.contains('rootOverlay: true'), isTrue);
      expect(src.contains('ScaffoldMessenger'), isFalse,
          reason: 'a snack bar lives inside the route Scaffold, which a modal '
              'barrier drops from the semantics tree entirely — measured in '
              'undo_bar_test.dart. An undo a screen reader cannot reach is '
              'not an undo (WCAG 2.1.1)');
    });

    test('the recording surface and account deletion keep their confirms', () {
      // The run screen's bottom controls and an account deletion are the two
      // places where an undo offer would be either dangerous or a lie: the
      // account delete cascades everything the user owns, and nothing on the
      // recording screen may be obscured or made cancellable-by-timer.
      for (final path in const [
        'lib/screens/run_screen.dart',
        'lib/screens/settings_account_screen.dart',
      ]) {
        expect(File(path).readAsStringSync().contains('deferDestructive('),
            isFalse,
            reason: '$path must keep confirm-then-gone');
      }
    });
  });

  // Issue #666, the round-17 index's carryover: the expanded lock-screen
  // notification body hardcoded its labels ("Time:", "Distance:", "Speed:")
  // while the title and collapsed text beside them were localized. It is the
  // one surface a runner reads mid-run through a pocket, and in six of the
  // seven shipped locales half of it was English.
  //
  // Pinned as a source rule rather than a widget test because the body is
  // built inside `_refreshLockScreenNotification`, which needs a live recorder
  // to reach. The rule is narrow: whatever the body interpolates, it may not
  // be a bare English label.
  test('the lock-screen notification body carries no English literal', () {
    final src = File('lib/screens/run_screen.dart').readAsStringSync();
    final match = RegExp(r'bigText:([\s\S]{0,400}?),\n\s*paused:').firstMatch(src);
    expect(match, isNotNull,
        reason: 'could not find the bigText argument in run_screen.dart — if '
            'the lock-screen body moved, move this guard with it');
    final body = match!.group(1)!;
    for (final label in ['Time:', 'Distance:', 'Speed:', 'Pace:']) {
      expect(
        body.contains(label),
        isFalse,
        reason: 'the lock-screen body spells "$label" as an English literal. '
            'Resolve it through l10n — runStatTime / runStatDistance / '
            'runStatSpeed / runStatPace already carry these exact strings in '
            'all seven catalogues.',
      );
    }
    expect(body.contains(r'$'), isTrue,
        reason: 'the body interpolates nothing — the match is probably wrong');
  });

  // A number the user typed reaches the app through a TextEditingController,
  // and five of the seven shipped locales (de, es, fr, pt, pt_BR) put a comma
  // on the decimal key. `double.tryParse` only understands a dot, so a raw
  // parse either drops the value to null or — behind a `[0-9.]` input filter
  // that deletes the comma first — reads "5,2" as 52 and saves a 5.2 km run
  // as 52 km. Both failures are silent. parseTypedDecimal is the one reader
  // that accepts either separator; these guards keep new fields on it.
  group('typed decimals are read locale-tolerantly', () {
    List<File> libSources() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    test('no controller text is parsed with a bare double.tryParse', () {
      final offenders = <String>[];
      for (final f in libSources()) {
        for (final m
            in RegExp(r'double\.tryParse\([^)]*\.text').allMatches(
          f.readAsStringSync(),
        )) {
          offenders.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'read typed text with parseTypedDecimal (lib/typed_decimal.dart) '
            'so a comma decimal survives:\n${offenders.join('\n')}',
      );
    });

    test('no decimal field filters the comma out of its own input', () {
      final offenders = <String>[];
      for (final f in libSources()) {
        if (f.path.endsWith('typed_decimal.dart')) continue;
        final src = f.readAsStringSync();
        for (final m in RegExp(r"allow\(RegExp\(r'\[[^\]]*\]'\)\)").allMatches(src)) {
          final pattern = m.group(0)!;
          if (pattern.contains('.') && !pattern.contains(',')) {
            offenders.add('${f.path}: $pattern');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'a filter that admits "." but not "," deletes the comma a de/'
            'es/fr/pt keyboard produces, turning 5,2 into 52 before any parse. '
            'Use typedDecimalInputFormatters:\n${offenders.join('\n')}',
      );
    });
  });

  // iPadOS presents `UIActivityViewController` as a popover and will not
  // present one without a non-empty anchor inside the host view. share_plus's
  // iOS plugin turns a missing or empty anchor into a `PlatformException`, so
  // the sheet never appears at all — and the app ships to iPad
  // (`TARGETED_DEVICE_FAMILY = "1,2"`). Every share call site in the tree once
  // omitted it. `share_sheet.dart` is the single place that derives and passes
  // one, so nothing else may reach the plugin.
  group('every share goes through share_sheet.dart', () {
    const helper = 'lib/share_sheet.dart';

    List<File> libSources() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    test('share_plus is imported by the helper and nothing else', () {
      var helperImports = false;
      final offenders = <String>[];
      for (final f in libSources()) {
        if (!f.readAsStringSync().contains('package:share_plus/')) continue;
        if (f.path == helper) {
          helperImports = true;
        } else {
          offenders.add(f.path);
        }
      }
      expect(helperImports, isTrue,
          reason: '$helper must import share_plus — it is the only wrapper, '
              'and the scan below is meaningless if it stops doing so');
      expect(offenders, isEmpty,
          reason: 'these reach share_plus directly and can therefore share '
              'without a popover anchor, which is broken on iPad. Call '
              'shareFilesFrom / shareTextFrom from $helper instead: '
              '${offenders.join(', ')}');
    });

    test('no raw share call exists outside the helper', () {
      final calls = RegExp(r'\bShare\.share|\bSharePlus\.instance');
      final offenders = <String>[];
      for (final f in libSources()) {
        if (f.path == helper) continue;
        for (final m in calls.allMatches(f.readAsStringSync())) {
          offenders.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'a raw share call cannot carry the sharePositionOrigin iPad '
              'requires. Route it through $helper: ${offenders.join(', ')}');
    });

    test('every share the helper makes carries a position origin', () {
      final src = File(helper).readAsStringSync();
      var found = 0;
      var from = 0;
      while (true) {
        final at = src.indexOf('ShareParams(', from);
        if (at < 0) break;
        found++;
        var i = at + 'ShareParams('.length;
        var depth = 1;
        while (depth > 0 && i < src.length) {
          if (src[i] == '(') depth++;
          if (src[i] == ')') depth--;
          i++;
        }
        final args = src.substring(at, i);
        expect(args.contains('sharePositionOrigin:'), isTrue,
            reason: 'a ShareParams in $helper omits sharePositionOrigin, which '
                'is the whole reason the helper exists:\n$args');
        from = i;
      }
      expect(found, greaterThanOrEqualTo(2),
          reason: 'expected the file + text share paths — did they move?');
    });

    test('every share entry point takes the context it anchors on', () {
      final src = File(helper).readAsStringSync();
      final entries =
          RegExp(r'^Future<[^>]*> (share\w+)\(\s*\n?\s*([^,)]*)', multiLine: true)
              .allMatches(src)
              .toList();
      expect(entries, isNotEmpty,
          reason: 'no share entry point found in $helper — renamed?');
      for (final m in entries) {
        expect(m.group(2)!.trim(), 'BuildContext context',
            reason: '${m.group(1)} must take the BuildContext it derives the '
                'anchor from as its first parameter. An optional Rect lets a '
                'caller omit the anchor, which is the bug this replaced.');
      }
    });
  });
  group('locale reach', () {
    // A catalogue that ships in the binary but that no runtime path resolves
    // to is translation work going nowhere: it costs bytes in every build and
    // no reader can ever see it. Nothing else in the tree connects "the ARB
    // file exists" to "a reader can get to it" — `app_pt.arb` shipped dark
    // twice for exactly that reason (decisions.md § 740). These read the
    // catalogue directory as the source of truth and hold every declaration
    // site to it.

    /// Catalogues that no BARE base-language tag resolves to, each with the
    /// reason it is reachable anyway. `_baseToLocale` can name one variant per
    /// language, so a language shipping two catalogues necessarily leaves one
    /// off it. Every entry is asserted to still be unreachable that way, so
    /// the list cannot rot into a blanket exemption.
    const baseFallbackExempt = <String, String>{
      'pt-BR': 'Portuguese ships two catalogues and the bare `pt` base is the '
          'European one (Portugal and Angola share that orthography), so '
          'pt-BR is reached by its exact tag — a pt-BR device, or the picker.',
    };

    /// ARB filename tag -> the CANONICAL tag every other declaration spells it
    /// with. gen-l10n refuses to generate when a country-coded catalogue exists
    /// without a bare base of the same language ("Arb file for a fallback, pt,
    /// does not exist, even though the following locale(s) exist: [pt_BR,
    /// pt_PT]"), so European Portuguese has to be the `pt` base FILE while
    /// every tag a reader, the OS or the runtime sees is `pt-PT` — the
    /// spelling web, the wrist and Info.plist all use. The filename is the
    /// tool's; the tag is ours. Each entry is asserted below to still be a real
    /// override, so the table cannot outlive the constraint that forced it.
    const arbTagOverride = <String, String>{'pt': 'pt-PT'};

    /// `app_pt_BR.arb` -> `pt-BR`; `app_en.arb` -> `en`.
    String tagOfArb(String filename) {
      final stem = filename.substring('app_'.length, filename.length - 4);
      final parts = stem.split('_');
      return parts.length == 1
          ? parts[0]
          : '${parts[0]}-${parts[1].toUpperCase()}';
    }

    /// The text between the bracket [marker] ends on and its match.
    String literalAfter(String source, String marker) {
      final at = source.indexOf(marker);
      if (at < 0) {
        fail('Could not find "$marker" — renamed? Update this guard.');
      }
      final open = marker[marker.length - 1];
      final close = open == '[' ? ']' : '}';
      var depth = 1;
      var i = at + marker.length;
      while (depth > 0 && i < source.length) {
        if (source[i] == open) depth++;
        if (source[i] == close) depth--;
        i++;
      }
      return source.substring(at + marker.length, i - 1);
    }

    Set<String> localeTags(String literal) => RegExp(
          r"Locale\('(\w+)'(?:,\s*'(\w+)')?\)",
        ).allMatches(literal).map((m) {
          final country = m.group(2);
          return country == null ? m.group(1)! : '${m.group(1)}-$country';
        }).toSet();

    Set<String> mapKeys(String literal) =>
        RegExp(r"'([\w-]+)'\s*:").allMatches(literal).map((m) => m.group(1)!).toSet();

    String withoutComments(String source) => source
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'//.*$'), ''))
        .join('\n');

    late Set<String> catalogues;
    late Set<String> declared;
    late String support;
    late String generated;

    setUpAll(() {
      catalogues = Directory('lib/l10n')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('app_') && n.endsWith('.arb'))
          .map(tagOfArb)
          .toSet();
      declared = catalogues.map((t) => arbTagOverride[t] ?? t).toSet();
      support = File('lib/l10n/locale_support.dart').readAsStringSync();
      generated =
          File('lib/l10n/gen/app_localizations.dart').readAsStringSync();
    });

    test('a catalogue exists for exactly the locales we say we support', () {
      expect(catalogues, isNotEmpty, reason: 'no app_*.arb found — moved?');
      expect(
        localeTags(literalAfter(support, 'supportedLocales = <Locale>[')),
        declared,
        reason: 'supportedLocales is what MaterialApp negotiates against. A '
            'catalogue missing from it is dead weight in the binary; an entry '
            'with no catalogue resolves to a locale gen-l10n cannot load.',
      );
    });

    test('the generated delegate carries exactly the catalogue set', () {
      expect(
        localeTags(literalAfter(generated, 'supportedLocales = <Locale>[')),
        catalogues,
        reason: 'gen/app_localizations.dart is regenerated from the ARB '
            'directory — a mismatch means the checked-in output is stale.',
      );
    });

    test('every catalogue has a picker endonym', () {
      expect(
        mapKeys(literalAfter(support, 'localeLabels = <String, String>{')),
        declared,
        reason: 'the picker names each locale in its own language; a locale '
            'the table cannot name renders a blank row.',
      );
    });

    test('every catalogue is reachable by its exact tag', () {
      expect(
        localeTags(literalAfter(support, '_exact = <String, Locale>{')),
        declared,
        reason: '_exact is the only path a stored preference or an exactly '
            'matching device tag takes; a catalogue absent from its VALUES '
            'can be selected by nobody.',
      );
    });

    test('the language picker is derived from the supported set, not listed',
        () {
      final body = withoutComments(_extractMethodBody(
        File('lib/screens/settings_preferences_screen.dart').readAsStringSync(),
        r'Future<void> _editLanguage\(\) async \{',
      ));
      expect(body.contains('supportedLocales'), isTrue,
          reason: 'the picker must build its options from supportedLocales.');
      for (final tag in catalogues) {
        expect(body.contains("'$tag'"), isFalse,
            reason: 'the picker spells $tag out. A hand-written list is how '
                'European Portuguese came to be unpickable while shipping.');
      }
    });

    test('the ARB parity suite covers every catalogue', () {
      final listed = RegExp(r"'([\w_]+)'")
          .allMatches(literalAfter(
              File('test/l10n_parity_test.dart').readAsStringSync(),
              'localeTags = ['))
          .map((m) => m.group(1)!.replaceFirst('_', '-'))
          .toSet();
      expect(listed, catalogues,
          reason: 'l10n_parity_test.dart names its locales by hand, so a new '
              'catalogue is silently unchecked for missing keys until it is '
              'added there too.');
    });

    // A locale absent from CFBundleLocalizations is one the App Store and the
    // iOS language picker will not offer the app in, however complete its ARB.
    // Reachable from either twin's directory: `..` is `apps/`.
    String bundleLocalizations() {
      final plist =
          File('../mobile_ios/ios/Runner/Info.plist').readAsStringSync();
      final at = plist.indexOf('<key>CFBundleLocalizations</key>');
      if (at < 0) fail('CFBundleLocalizations is gone from Info.plist.');
      final open = plist.indexOf('<array>', at);
      return plist.substring(open, plist.indexOf('</array>', open));
    }

    test('the iOS bundle advertises exactly the catalogue set', () {
      final advertised = RegExp(r'<string>([\w-]+)</string>')
          .allMatches(bundleLocalizations())
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        advertised,
        declared,
        reason: 'Info.plist and lib/l10n disagree about which locales ship. '
            'Apple names a locale by its region, which is the spelling the '
            'canonical tag set now uses everywhere — the plist needs no '
            'override of its own any more.',
      );
    });

    test('every ARB filename override is still an override', () {
      for (final entry in arbTagOverride.entries) {
        expect(catalogues, contains(entry.key),
            reason: '${entry.key} is renamed by arbTagOverride but ships no '
                'catalogue file — drop the entry.');
        expect(catalogues, isNot(contains(entry.value)),
            reason: 'lib/l10n now holds app_${entry.value.replaceAll('-', '_')}'
                '.arb, so the filename and the tag agree — drop '
                '${entry.key} from arbTagOverride.');
      }
    });

    test('the Android manifest advertises exactly the catalogue set', () {
      // Android 13+ reads locales_config.xml to populate Settings -> Apps ->
      // Threkir -> Language, a path to a catalogue the in-app picker does not
      // own alone. Android spells tags the way we do, so this reads the
      // canonical set directly.
      final config = File(
        '../mobile_android/android/app/src/main/res/xml/locales_config.xml',
      ).readAsStringSync();
      expect(
        RegExp(r'android:name="([\w-]+)"')
            .allMatches(config)
            .map((m) => m.group(1)!)
            .toSet(),
        declared,
        reason: 'locales_config.xml and lib/l10n disagree about which locales '
            'ship, so the OS language picker offers the wrong set.',
      );
    });

    test('a catalogue no base-language tag reaches carries a reason', () {
      final reachedByBase =
          localeTags(literalAfter(support, '_baseToLocale = <String, Locale>{'));
      final unreached = declared
          .difference(reachedByBase)
          .where((t) => !baseFallbackExempt.containsKey(t))
          .toList()
        ..sort();
      expect(unreached, isEmpty,
          reason: 'a device reporting only a base language (`pt`, `de`) lands '
              'on _baseToLocale. These catalogues are off it with no recorded '
              'reason — either map the base to one of them, or add the entry '
              'to baseFallbackExempt saying how a reader reaches it.');
    });

    /// Words that only one of the two Portuguese variants uses. A catalogue
    /// tagged for one variant containing the other's word is the failure this
    /// whole locale has kept producing: `app_pt.arb` shipped 3434 byte-identical
    /// Brazilian strings under a European tag for three weeks, and nothing in
    /// the tree could see it, because every existing guard asks whether a
    /// catalogue is REACHABLE, never whether it says what its tag claims.
    ///
    /// Deliberately narrow. Each entry is a word the other variant does not use
    /// at all, not merely one it uses less — a frequency judgement would need a
    /// threshold, and a threshold is a number nobody can defend.
    const brazilianOnly = <String>[
      'você', 'senha', 'tela', 'arquivo', 'celular', 'esteira', 'excluir',
      'registrar', 'compartilhar', 'baixar', 'ônibus', 'geladeira', 'xícara',
      'aplicativo', 'cadastrar', 'planejar', 'gerenciar', 'tênis',
      'quilômetro', 'gênero', 'acessar', 'câmera', 'escanear',
      // `quilômetro` and `gênero` were one class caught one word at a time:
      // every Brazilian proparoxytone taking ô/ê where Portugal takes ó/é.
      'cronômetro', 'oxigênio', 'autônomo', 'autônoma',
      'planilha', 'usuário', 'deletar', 'esporte',
    ];
    const europeanOnly = <String>[
      'palavra-passe', 'ecrã', 'ficheiro', 'telemóvel', 'passadeira',
      'partilhar', 'quilómetro', 'género', 'autocarro', 'frigorífico',
      'chávena', 'utilizador', 'ginásio',
    ];

    /// Which variant a catalogue's tag CLAIMS, for the tags that make a claim.
    const portugueseVariant = <String, List<String>>{
      'pt-PT': brazilianOnly,
      'pt-BR': europeanOnly,
    };

    test('a Portuguese catalogue does not read as the variant it is not', () {
      // `excluir`/`arquivo`/`acessar` carry a second sense in Portugal
      // (exclude / archive / accessible) that is not a Brazilianism at all, so
      // the scan runs on whole words and these keys are named rather than the
      // words being dropped from the list — dropping them would blind the
      // guard to the delete and file senses everywhere else.
      const senseExempt = <String>{
        'runDetailMarkDnfSubtitle', 'coachArchiveBanner',
        'coachArchiveDeleteFailed', 'coachArchiveDeleteBody',
        'prefsExcludeGymFromReadiness',
        'settingsAccountRestoreIncompleteArchive',
        'settingsAccountBackupTracksPartialNotice',
      };
      for (final entry in portugueseVariant.entries) {
        final file = arbTagOverride.entries
            .where((e) => e.value == entry.key)
            .map((e) => e.key)
            .followedBy([entry.key]).first;
        final arb = File('lib/l10n/app_${file.replaceAll('-', '_')}.arb');
        expect(arb.existsSync(), isTrue,
            reason: '${entry.key} claims a catalogue at ${arb.path}.');
        final messages =
            (jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>)
              ..removeWhere((k, v) => k.startsWith('@') || v is! String);
        final offenders = <String>[];
        for (final message in messages.entries) {
          if (senseExempt.contains(message.key)) continue;
          for (final word in entry.value) {
            if (RegExp('(?<![a-zà-ÿ])$word(s|es)?(?![a-zà-ÿ])',
                    caseSensitive: false, unicode: true)
                .hasMatch(message.value as String)) {
              offenders.add('${message.key}: "$word"');
            }
          }
        }
        expect(offenders, isEmpty,
            reason: '${arb.path} is tagged ${entry.key} but reads as the other '
                'variant. A tag that disagrees with its content is worse than '
                'a missing catalogue: the reader is told this is their '
                'Portuguese and it is not.');
      }
    });

    /// Words European Portuguese really does use, but for a DIFFERENT sense
    /// than the one Brazilian spends them on. `brazilianOnly` above cannot
    /// hold these: its entries are words Portugal does not use at all, and a
    /// deny-list entry for a word with a legitimate sense can only be answered
    /// by dropping the word, which blinds the scan everywhere else. So the
    /// direction is inverted — the word is banned outright and the sites that
    /// mean the other thing are named.
    ///
    /// `padrão` is *standard* and *pattern* in Portugal; the pre-set value is a
    /// `predefinição`. Brazilian spends one word on all three, so a catalogue
    /// derived from it reads as Brazilian at every default. Naming the
    /// survivors is what makes this hold: a NEW string saying `padrão` fails
    /// here and forces the per-site decision rather than inheriting the
    /// ambiguity again. The web twin is `locale_reach.test.ts`.
    const senseSplit = <String, (String, List<String>)>{
      'pt-PT': (
        r'padr(ão|ões)',
        // loadRampMeaningHigh is "the pattern most associated with injury".
        ['loadRampMeaningHigh'],
      ),
    };

    test('a sense-split word survives only where the other sense was recorded',
        () {
      for (final entry in senseSplit.entries) {
        final (pattern, onlyAt) = entry.value;
        final word = RegExp('(?<![a-zà-ÿ])$pattern(?![a-zà-ÿ])',
            caseSensitive: false, unicode: true);
        final file = arbTagOverride.entries
            .where((e) => e.value == entry.key)
            .map((e) => e.key)
            .followedBy([entry.key]).first;
        final arb = File('lib/l10n/app_${file.replaceAll('-', '_')}.arb');
        final messages =
            (jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>)
              ..removeWhere((k, v) => k.startsWith('@') || v is! String);
        expect(
            messages.entries
                .where((m) =>
                    !onlyAt.contains(m.key) && word.hasMatch(m.value as String))
                .map((m) => m.key)
                .toList(),
            isEmpty,
            reason: '${arb.path} spends $pattern on a sense Portugal does not '
                'use it for. A default is a `predefinição`; `padrão` is a '
                'standard or a pattern. If one of these really is the other '
                'sense, add it to senseSplit with the English source in a '
                'comment.');
        // A named site that no longer says the word is a dead entry, and a dead
        // entry is how an allowlist stops being a decision and becomes noise.
        for (final key in onlyAt) {
          expect(messages, contains(key),
              reason: '${entry.key}: senseSplit names $key, which the '
                  'catalogue no longer has.');
          expect(word.hasMatch(messages[key] as String), isTrue,
              reason: '${entry.key}: $key no longer says $pattern — drop it '
                  'from senseSplit so the guard covers the key again.');
        }
      }
    });


    /// Which SECOND PERSON a catalogue addresses its reader in. Portuguese has
    /// two and they do not mix inside one catalogue: `tu` takes `teu`/`tua`,
    /// the enclitic `-te` and a second-person-singular verb, while `você` — the
    /// register European Portuguese software uses, and the one § 755 chose for
    /// every Portuguese surface derived since — takes `seu`/`sua`, `-lhe` and a
    /// third-person verb. `app_pt.arb` used both: 39 strings on the tu
    /// possessive against 203 on `seu`/`sua`, plus 7 tu-only finite verbs, 6
    /// enclitics and one `contigo`. Web's `pt-PT.ts` is unanimous on the
    /// possessive axis (335 `seu`/`sua`, zero of these) and `app_pt_BR.arb`
    /// carries none at all, so the phone was the one surface telling one reader
    /// it was two products.
    ///
    /// The markers split into two kinds and only one kind can be listed, so
    /// this is two tests. A [tuOnlyMarker] is a form no other person, tense or
    /// part of speech spells the same way, which makes a token list exact. The
    /// affirmative imperative is the other kind and is unlistable: its tu form
    /// is letter-for-letter the third-person present indicative, so `Adiciona
    /// um peso` (tu, *add a weight*) and `a app adiciona um peso` (*the app
    /// adds a weight*) are the same word, and any token banning it fires on
    /// ordinary prose. That half is derived against the Brazilian catalogue
    /// instead — see the second test.
    ///
    /// `precisas` is deliberately absent: it is `precisar` in the tu form AND
    /// the feminine plural of `preciso`, and `zonas precisas` is a live string
    /// in both catalogues. Bare `tu` is absent for the opposite reason — a
    /// label whose whole value names the reader is not a possessive in running
    /// prose, and web pt-PT ships those same two keys as `(tu)` and `Tu: `
    /// after § 760 put the pronoun back into them.
    const tuOnlyMarkers = <String>[
      'teu', 'tua', 'teus', 'tuas',
      'podes', 'estás', 'tens', 'queres', 'vais', 'deves', 'sabes', 'fazes',
      'és', 'vês', 'dizes', 'escolhes', 'alteras', 'tomas',
      'tiveres', 'estiveres', 'quiseres', 'puderes', 'fizeres',
      'fizeste', 'foste', 'tiveste', 'estiveste',
      'tenhas', 'estejas', 'sejas', 'possas', 'vás', 'faças',
      'contigo',
    ];

    /// The enclitic object pronoun. `você` takes `-lhe` or `-o`/`-a`, never
    /// this, so a hyphen followed by exactly `te` is a tu marker wherever it
    /// lands. Verified to fire on nothing else across all seven catalogues.
    final tuEnclitic =
        RegExp(r'(?<![a-zà-ÿ])[a-zà-ÿ]+-te(?![a-zà-ÿ])',
            caseSensitive: false, unicode: true);

    /// Key prefixes allowed to address the reader as `tu`, with the reason.
    /// **Empty, and that is the finding.** § 760 unified the `tts*` voice cues
    /// on tu — correctly observing that a spoken coach cannot address one
    /// runner two ways mid-run — but measured only inside that block. The
    /// OTHER spoken block, the 44 `guided*` coach scripts, was already `você`
    /// ("Comece leve", "Mantenha o ritmo"), so the two halves of one voice
    /// disagreed: the guided coach said `Comece` and the pace cue said
    /// `Acelera`, in the same run, through the same engine. Applying § 760's
    /// own principle one block wider reverses its choice of variant, because
    /// the catalogue-wide register is § 755's `você`. Both blocks are now that.
    ///
    /// Each prefix added here is asserted below to still cover a key the guard
    /// would otherwise flag, so an exemption cannot outlive the strings it was
    /// written for.
    const registerExemptPrefixes = <String>[];

    /// European/Brazilian word pairs that differ by the same one-letter ending
    /// an imperative does and are not verbs at all, so the derived scan below
    /// cannot tell them apart on shape. `equipa`/`equipe` is *team*;
    /// `este`/`esta` and `deste`/`desta` are demonstratives agreeing with a
    /// noun whose gender the variants disagree on (`o ecrã` against `a tela`,
    /// the § 760 rule). Each is asserted to still be in use.
    const variantWordPairs = <String, String>{
      'equipa': 'equipe',
      'este': 'esta',
      'deste': 'desta',
    };

    Map<String, String> arbMessages(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing.');
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return <String, String>{
        for (final e in raw.entries)
          if (!e.key.startsWith('@') && e.value is String)
            e.key: e.value as String,
      };
    }

    bool registerExempt(String key) =>
        registerExemptPrefixes.any((p) => key.startsWith(p));

    List<String> tuMarkersIn(String value) => [
          for (final marker in tuOnlyMarkers)
            if (RegExp('(?<![a-zà-ÿ])$marker(?![a-zà-ÿ])',
                    caseSensitive: false, unicode: true)
                .hasMatch(value))
              '"$marker"',
          if (tuEnclitic.hasMatch(value)) 'the "-te" enclitic',
        ];

    test('a Portuguese catalogue addresses its reader in one register', () {
      // Both catalogues, not just the European one. `app_pt_BR.arb` is the
      // reference the derived imperative scan below measures against, so a tu
      // marker landing in IT makes that scan blind rather than merely wrong —
      // the two words would cancel and the pair would never be reported.
      for (final tag in ['pt', 'pt_BR']) {
        final offenders = <String>[];
        for (final message in arbMessages('lib/l10n/app_$tag.arb').entries) {
          if (registerExempt(message.key)) continue;
          for (final marker in tuMarkersIn(message.value)) {
            offenders.add('${message.key}: $marker');
          }
        }
        expect(offenders, isEmpty,
            reason: 'app_$tag.arb addresses its reader as `tu` here and as '
                '`você` everywhere else. One catalogue cannot be two products '
                'to one reader: use `seu`/`sua`, `-lhe` and a third-person '
                'verb, per decisions § 755. If a string really must be tu, it '
                'belongs in the spoken-cue block or in registerExemptPrefixes '
                'with the reason written down.');
      }
    });

    test('the pt-PT catalogue uses no tu imperative its Brazilian twin does not',
        () {
      // Derived rather than listed, because the tu affirmative imperative is
      // spelled exactly like the third-person present indicative and no token
      // can separate them. `app_pt_BR.arb` is uniformly `você` (pinned by the
      // test above), so a word this catalogue uses where Brazilian uses the
      // same stem with the imperative's other ending IS the tu form: `Tenta`
      // against `Tente`, `Adiciona` against `Adicione`, `Escolhe` against
      // `Escolha`. No threshold, no vocabulary list, and a new one fails here
      // the day it lands.
      final european = arbMessages('lib/l10n/app_pt.arb');
      final brazilian = arbMessages('lib/l10n/app_pt_BR.arb');
      final word = RegExp(r'[a-zà-ÿ]+', caseSensitive: false, unicode: true);
      Set<String> wordsOf(String v) =>
          word.allMatches(v).map((m) => m.group(0)!.toLowerCase()).toSet();

      final offenders = <String>[];
      for (final message in european.entries) {
        if (registerExempt(message.key)) continue;
        final other = brazilian[message.key];
        if (other == null) continue;
        final ours = wordsOf(message.value);
        final theirs = wordsOf(other);
        for (final a in ours.difference(theirs)) {
          if (a.length < 4) continue;
          for (final b in theirs.difference(ours)) {
            if (b.length < 4) continue;
            if (a.substring(0, a.length - 1) != b.substring(0, b.length - 1)) {
              continue;
            }
            final swap = '${a[a.length - 1]}${b[b.length - 1]}';
            if (swap != 'ae' && swap != 'ea') continue;
            if (variantWordPairs[a] == b) continue;
            offenders.add('${message.key}: "$a" where pt-BR says "$b"');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'app_pt.arb gives an imperative in the tu form. Portugal '
              'says `Tente`, not `Tenta`, in the register this catalogue uses '
              'everywhere else (decisions § 755). If the word is not a verb, '
              'add the pair to variantWordPairs with what it means.');
    });

    test('every register exemption still needs its exemption', () {
      // An exemption that covers nothing has stopped being a decision and
      // become noise — the shape senseSplit above already uses for its named
      // sites. The spoken-cue prefixes must still name a key the guard would
      // otherwise flag, and each variant pair must still be a word both
      // catalogues use.
      final european = arbMessages('lib/l10n/app_pt.arb');
      final brazilian = arbMessages('lib/l10n/app_pt_BR.arb');
      for (final prefix in registerExemptPrefixes) {
        final covered = european.entries.where(
            (e) => e.key.startsWith(prefix) && tuMarkersIn(e.value).isNotEmpty);
        expect(covered, isNotEmpty,
            reason: 'registerExemptPrefixes carries "$prefix", but no key '
                'under it says `tu` any more. Drop the prefix so the guard '
                'covers those keys again.');
      }
      final whole = <String>[
        ...european.values,
        ...brazilian.values,
      ].join('\n');
      for (final pair in variantWordPairs.entries) {
        for (final word in [pair.key, pair.value]) {
          expect(
              RegExp('(?<![a-zà-ÿ])$word(?![a-zà-ÿ])',
                      caseSensitive: false, unicode: true)
                  .hasMatch(whole),
              isTrue,
              reason: 'variantWordPairs names "$word", which neither '
                  'Portuguese catalogue uses any more.');
        }
      }
    });
    test('every base-fallback exemption still needs its exemption', () {
      final reachedByBase =
          localeTags(literalAfter(support, '_baseToLocale = <String, Locale>{'));
      for (final entry in baseFallbackExempt.entries) {
        expect(declared, contains(entry.key),
            reason: '${entry.key} is exempted from the base-fallback rule but '
                'ships no catalogue — drop the entry.');
        expect(reachedByBase, isNot(contains(entry.key)),
            reason: '${entry.key} is now a base-fallback target '
                '(${entry.value}) — drop it from baseFallbackExempt so the '
                'guard covers it.');
        expect(entry.value.trim(), isNotEmpty);
      }
    });
  });

  group('a header that names its web twin names a file that exists', () {
    // A doc comment pointing at a path the counterpart moved out of is a
    // claim the next reader cannot follow, and it is invisible to
    // `check_parity_pair_registry.mjs`, which holds paths of its own rather
    // than reading these. Twenty-six distinct web paths had gone stale under
    // the 2026 `src/lib` re-foldering — including registered pairs such as
    // `privacy`, `segments`, `training` and `training_load` — before anything
    // read them (decisions § 989).
    final ref = RegExp(r'apps/web/src/[A-Za-z0-9_./\-]+\.(?:ts|svelte|mjs)');
    final repoRoot = Directory('../..');

    Iterable<File> dartSources() sync* {
      for (final base in <String>['lib', 'test', '../../packages']) {
        final dir = Directory(base);
        if (!dir.existsSync()) continue;
        for (final e in dir.listSync(recursive: true)) {
          if (e is File && e.path.endsWith('.dart')) yield e;
        }
      }
    }

    test('every referenced web path resolves', () {
      final stale = <String, Set<String>>{};
      var scanned = 0;
      for (final f in dartSources()) {
        for (final m in ref.allMatches(f.readAsStringSync())) {
          scanned++;
          final target = File('${repoRoot.path}/${m.group(0)}');
          if (!target.existsSync()) {
            stale.putIfAbsent(m.group(0)!, () => <String>{}).add(f.path);
          }
        }
      }
      expect(scanned, greaterThan(100),
          reason: 'the scan found almost nothing — the pattern or the walk '
              'is broken, not the tree');
      expect(stale, isEmpty,
          reason: 'a header names a web file that no longer exists at that '
              'path; find where it moved and update the comment');
    });
  });
}
