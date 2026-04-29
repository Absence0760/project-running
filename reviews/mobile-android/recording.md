# Recording pipeline — audit

Files reviewed:
- `apps/mobile_android/lib/screens/run_screen.dart`
- `apps/mobile_android/lib/race_controller.dart`
- `apps/mobile_android/lib/run_stats.dart`
- `apps/mobile_android/lib/run_notification_bridge.dart`
- `apps/mobile_android/lib/route_simplify.dart`
- `apps/mobile_android/lib/audio_cues.dart`
- `apps/mobile_android/lib/ble_heart_rate.dart`
- `apps/mobile_android/lib/widgets/live_run_map.dart`
- `apps/mobile_android/lib/widgets/pace_segments.dart`
- `apps/mobile_android/lib/widgets/run_share_card.dart`
- `apps/mobile_android/test/run_stats_test.dart`
- `apps/mobile_android/test/pace_segments_test.dart`
- `apps/mobile_android/test/ble_heart_rate_test.dart`
- `apps/mobile_android/test/route_simplify_test.dart`

Date: 2026-04-21
Auditor scope: mobile_android recording stack

## Summary

The recording stack is structurally sound: the L0/L1 clock and distance path is correctly isolated from L4 auxiliary effects inside `_onSnapshot`, the state machine has no stuck-state paths under normal use, and the incremental-save and crash-recovery contract is properly wired. Three concrete bugs were found. First, TTS calls at `_begin` and `_stop` are outside try/catch blocks, violating the L4 isolation rule — a TTS engine failure at start/stop time can kill the `_stop` flow before `runStore.save` runs. Second, `_discard()` does not cancel the BLE heart-rate stream subscription, leaving a live callback that calls `setState` after the run ends. Third, the FIT export writes a CRC over all bytes including the 14-byte header, but the FIT spec requires the data CRC to cover only bytes after the header; every exported `.fit` file has a bad CRC and will be rejected by strict parsers. The rest of the code is clean against the contract.

---

## Findings

### P0 — bugs / data loss / security

- [`run_screen.dart:910-915`] **`announceFinish` not wrapped in try/catch — can abort `runStore.save`**

  `_stop()` calls `widget.audioCues.announceFinish(...)` without a try/catch. `announceFinish` calls `_tts.speak()` which can throw if the TTS engine is unavailable (missing engine, audio focus denied, device in DND mode). Because `runStore.save(run)` is called on the line immediately after (line 918), an uncaught exception from TTS propagates up `_stop`, skips both `runStore.save` and the cloud sync, and leaves `_state` stuck in `_ScreenState.finished` with `_finishedRun` set but the run not persisted to disk. The run is lost.

  Wrap the block:
  ```diff
  - if (widget.preferences.audioCues) {
  -   widget.audioCues.announceFinish(
  -     distanceMetres: run.distanceMetres,
  -     elapsed: run.duration,
  -     unit: widget.preferences.unit,
  -   );
  - }
  + if (widget.preferences.audioCues) {
  +   try {
  +     await widget.audioCues.announceFinish(
  +       distanceMetres: run.distanceMetres,
  +       elapsed: run.duration,
  +       unit: widget.preferences.unit,
  +     );
  +   } catch (e) {
  +     debugPrint('announceFinish failed: $e');
  +   }
  + }
  ```

  Verification: add a test that injects a `FlutterTts` stub that throws on `speak`, calls `_stop`, and asserts `runStore.runs` is non-empty afterward. As a manual check, disable the TTS engine in device settings and stop a run — confirm the run appears in history.

---

- [`run_screen.dart:481`] **`announceStart` not wrapped in try/catch — can abort transition to recording state**

  `announceStart()` is called on line 481 before `setState(() => _state = _ScreenState.recording)` on line 483. If TTS throws, the state flip never happens: the recorder and all timers are running (`_incrementalSaveTimer`, `_gpsLostCheckTimer`, `_permissionWatchdogTimer`) but `_state` is still `_ScreenState.countdown`. The user sees the countdown UI permanently. There is no recovery path — they cannot stop the run because `_stop` guards on `_recorder != null` and the recorder is live.

  ```diff
  - if (widget.preferences.audioCues) widget.audioCues.announceStart();
  + if (widget.preferences.audioCues) {
  +   try {
  +     widget.audioCues.announceStart();
  +   } catch (e) {
  +     debugPrint('announceStart failed: $e');
  +   }
  + }
  ```

  Note: `announceStart` is not `await`ed, so the thrown exception will become an unhandled Future error — the state flip still happens in the non-throwing case, but if `_tts.setLanguage` or `_tts.setSpeechRate` throws synchronously during `_init`, the control flow is interrupted. Wrap as above regardless.

  Verification: same TTS-stub approach as P0 item 1 above. Confirm recording state is entered even when TTS init throws.

---

- [`run_share_card.dart:684-691`] **FIT export CRC covers the 14-byte file header — violates spec, produces unreadable files**

  `_runToFitBytes` computes the data CRC by iterating from `i = 0` over the entire byte array (line 685). Per the ANT+ FIT Protocol specification, the data CRC must cover only the bytes from the end of the file header (byte offset 14) through the last record byte. Including the header shifts the CRC, producing a value that no conforming FIT parser will accept. Garmin Connect, Strava, and TrainingPeaks will all silently reject or error on these files.

  ```diff
  - for (var i = 0; i < out.length; i++) {
  + for (var i = 14; i < out.length; i++) {
      crc = _fitCrc(crc, out[i]);
    }
  ```

  Verification: export a run as `.fit`, load it in a local Garmin FIT SDK validator or the `fit_tool` Dart package. Confirm it passes before/fails after the current code, passes after the fix.

---

### P1 — resilience violations, correctness

- [`run_screen.dart:965-1013`] **`_discard()` does not cancel the BLE heart-rate subscription**

  `_hrSub` is created in `_begin()` (line 460). `_stop()` cancels it (line 881). `_discard()` does not. After a discard, `_hrSub` remains live: every BPM notification from the chest strap calls `setState(() => _currentBpm = bpm)` on a widget that has returned to idle state. If the widget is also disposed while the strap is in range, `mounted` is false but `_bpmSamples.add(bpm)` still runs, accumulating stale data that will pollute the next run's average BPM. The next run's `_begin()` clears `_bpmSamples` (line 458) but does not cancel the prior `_hrSub` before creating a new one (line 460), leaving two concurrent listeners on the same stream.

  Add to `_discard()`:
  ```diff
    _snapshotSub?.cancel();
    _stepSub?.cancel();
  + _hrSub?.cancel();
  + _hrSub = null;
  + _bpmSamples.clear();
  + _currentBpm = null;
  ```

  Also add `_hrSub?.cancel()` to `dispose()` alongside the other subscription cancellations (line 1022–1028).

  Verification: pair a BLE strap, start a run, discard it, immediately start another run. Confirm in the debugger that `_bpmSamples` is empty at the start of the second run and that only one listener is attached to `heartRate.stream`.

---

- [`race_controller.dart:141-143`] **`_refresh()` swallows all exceptions silently — no `debugPrint`**

  The catch block on line 141 is `catch (_) {}` with only a comment. Any exception — including `FormatException` from malformed JSON, `TypeError` from an unexpected schema column, or `StackOverflowError` — is discarded without logging. This is the only loop that determines whether a race is shown to the user. Silent swallowing makes diagnosing race-feature failures impossible.

  Replace with:
  ```diff
  - } catch (_) {
  -   // Silent — controller is advisory, shouldn't surface errors to the user.
  - }
  + } catch (e) {
  +   debugPrint('RaceController._refresh failed: $e');
  + }
  ```

  The same change applies to `pushPing` (line 212) and `submitResult` (line 236) — those are already described as best-effort, but they still need a debugPrint on catch so failures leave a trace.

---

- [`run_share_card.dart:102-118`] **`_shareFile` has no try/catch — unhandled exceptions dismissed by the runtime**

  `_shareImage` (line 64) is correctly wrapped in try/catch with a user-facing snackbar on failure. `_shareFile` is not. A `FileSystemException` (permissions, full disk) or an exception from `Share.shareXFiles` propagates unhandled, crashes the sheet's async task, and shows nothing to the user. Wrap the entire body:

  ```diff
  Future<void> _shareFile(String format) async {
  + try {
      final tmp = await getTemporaryDirectory();
      ...
      await Share.shareXFiles([XFile(file.path)], text: _caption);
  + } catch (e) {
  +   debugPrint('_shareFile failed: $e');
  +   if (mounted) {
  +     ScaffoldMessenger.of(context).showSnackBar(
  +       const SnackBar(content: Text('Could not export file')),
  +     );
  +   }
  + }
  }
  ```

---

- [`audio_cues.dart:10-16`] **`_init()` has no error handling — a TTS init failure silently leaves `_initialized = false`, then every subsequent call to `_init` re-attempts and re-throws**

  If `_tts.setLanguage('en-US')` throws (TTS engine not installed, platform channel error), `_initialized` is never set to `true`. Every subsequent `announceSplit`, `announceOffRoute`, etc. call `_init()` again, which throws again. The callers inside `_onSnapshot` have per-block try/catch so no data is lost, but at the call sites in `_begin` and `_stop` (see P0 items above) the throw is not caught.

  Additionally, on successful init, if a subsequent `_tts.speak()` fails, the `_initialized` flag is already `true` so `_init` won't be retried — but speak itself can still throw, which is fine. The real problem is that `_init` failures are not surfaced at all.

  Fix: catch inside `_init` and set a permanent failure flag so callers don't retry indefinitely:
  ```diff
  bool _initialized = false;
  + bool _initFailed = false;

  Future<void> _init() async {
  + if (_initFailed) return;
    if (_initialized) return;
  + try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      _initialized = true;
  + } catch (e) {
  +   _initFailed = true;
  +   debugPrint('AudioCues._init failed: $e');
  + }
  }
  ```

---

- [`ble_heart_rate.dart:106-126`] **`_connect` does not cancel a prior scan in progress before connecting**

  `scan()` calls `FlutterBluePlus.startScan(...)` without checking whether a scan is already running. If the UI calls `scan()` twice (e.g. user dismisses and reopens the pairing sheet), two `startScan` calls are in flight simultaneously and the second one can fail with a platform exception on some Android versions, or the first scan's `scanResults` listener accumulates into a now-orphaned `StreamController`. The `scanResults` subscription (`sub`) is only cancelled after `startScan` completes; if the user navigates away before timeout, the subscription leaks.

  Add an explicit `FlutterBluePlus.stopScan()` call before `startScan`:
  ```diff
  FlutterBluePlus.startScan(
    withServices: [_heartRateService],
    timeout: timeout,
  )
  ```
  Replace with:
  ```diff
  await FlutterBluePlus.stopScan(); // no-op if not scanning
  FlutterBluePlus.startScan(
    withServices: [_heartRateService],
    timeout: timeout,
  )
  ```

  Provide a way for the caller to cancel in-flight: `scan()` currently returns a broadcast stream with no cancellation handle. At minimum, expose a `stopScan()` method on `BleHeartRate` that calls `FlutterBluePlus.stopScan()` so the bottom sheet can invoke it on dismiss.

---

- [`ble_heart_rate.dart:119-125`] **BLE notify subscription has no `onError` handler — a GATT notification error drops silently and kills the stream**

  `hrChar.lastValueStream.listen(...)` (line 120) has no `onError` callback and no `cancelOnError` parameter (defaults to `false`). If the GATT layer emits an error (device out of range, connection reset mid-notification), the error is delivered to the unhandled-exception zone rather than the subscription. The `_sub` field stays non-null but inactive. `disconnect` then `connectCached` would be needed to recover, but nothing triggers that path automatically.

  ```diff
  _sub = hrChar.lastValueStream.listen((bytes) {
    final bpm = _parseHeartRate(bytes);
    if (bpm != null && bpm >= 30 && bpm <= 230) {
      _controller.add(bpm);
    }
  + }, onError: (Object e) {
  +   debugPrint('BLE HR stream error: $e');
  + });
  ```

---

### P2 — maintainability, duplication, code smell

- [`run_screen.dart:496`] **`_onSnapshot` body uses 6-space indentation throughout, inconsistent with the rest of the file (4-space)**

  Every other method in `_RunScreenState` uses 4-space body indentation. `_onSnapshot` uses 6 (method declared at 2-space depth, body at 6). This is cosmetic but creates a notable visual inconsistency in the hottest method in the file. Re-indent the body to 4-space standard (i.e. the same as `_saveInProgress`, `_begin`, `_stop`, etc.).

---

- [`run_share_card.dart:588-691`] **`_runToFitBytes` is 103 lines of low-level binary encoding in a widget file**

  The FIT serialiser has nothing to do with widget rendering, shares no types with the widget, and is untested. It belongs in `run_stats.dart` or a dedicated `fit_exporter.dart` alongside the GPX/TCX string builders. Move the three export functions (`_runToGpx`, `_runToTcx`, `_runToFitBytes`, `_fitCrc`, `_formatDate`, `_formatDuration`) out of the widget file into a separate library file where they can be unit-tested independently of the widget tree. At minimum add tests for `_runToFitBytes` given the CRC bug (P0 item 3) and the missing Activity/Session messages (see P2 item below).

---

- [`run_share_card.dart:636-691`] **FIT export omits required Activity and Session messages**

  A valid FIT activity file must contain at minimum: File ID message (present), Session message (global message number 18), and Activity message (global message number 34), in addition to Record messages. The current output has only File ID and Record messages. Garmin Connect and other platforms that validate conformance will reject the file even after the CRC fix. The Activity message must contain `timestamp` and `total_timer_time`; the Session must contain `sport`, `start_time`, and `total_elapsed_time`. Add these after the Record messages and before the CRC.

---

- [`run_screen.dart:1747`] **`_StatsOverlay` passes `primaryUnit` as the unit for the secondary stat column**

  ```dart
  Expanded(child: _StatColumn(
      label: secondaryLabel, value: secondaryValue, unit: primaryUnit)),
  ```

  When `_activityType.usesSpeed` is true, `primaryUnit` is the speed label (e.g. "km/h") and `secondaryValue` is `_formattedAvgSpeedValue` (correct). When `usesSpeed` is false, `primaryUnit` is the pace label (e.g. "/km") and `secondaryValue` is `_formattedAvgPaceValue` (also correct). So the displayed unit is actually right in both cases — but the field name `primaryUnit` used for the secondary column is misleading and would be wrong the moment anyone adds a secondary stat with a different unit. Introduce a `secondaryUnit` parameter on `_StatsOverlay` and pass it through explicitly.

---

- [`run_stats.dart:1-139`] **`haversineMetres` is duplicated: also exists in `pace_segments.dart` as `_haversineMetres`**

  `run_stats.dart` exports `haversineMetres` (line 123). `pace_segments.dart` contains a private `_haversineMetres` with identical logic (line 80) rather than importing from `run_stats`. The two implementations are arithmetically equivalent (one uses `atan2(sqrt(a), sqrt(1-a))`, the other uses `asin(sqrt(h))` — both correct). Pick one, make it the canonical source, and delete the duplicate.

---

### P3 — nits

- [`live_run_map.dart:491, 504`] **`withOpacity` used in `_PulsingDot`**

  `withOpacity` is acknowledged tech debt project-wide. These two instances are in `_PulsingDot` (lines 491 and 504) which is rebuilt on every animation tick (~60 Hz). Replace with `.withValues(alpha: ...)` to avoid the deprecated API and eliminate a potential color-space precision loss at high refresh rates. The rest of the file correctly uses `withValues`.

---

- [`run_screen.dart:1305-1310`] **`withOpacity` used on the idle-screen START button border**

  `const Color(0xFF22C55E).withOpacity(0.3)` at line 1307. The border is a `const`-context decoration — switch to a pre-computed `const Color(0x4D22C55E)` (0.3 × 255 ≈ 76 = 0x4C, close enough) or `.withValues(alpha: 0.3)` so the idle screen widget can be `const`.

---

- [`route_simplify.dart:30-51`] **`_dpStep` is recursive with no depth guard — theoretical stack overflow on a pathological input**

  For a perfectly alternating-peak input (every other waypoint is maximally off the straight line), the recursion depth is O(n). At n = 3600 (60-minute run at 1 Hz, which is the max before the recorder's 3 m movement filter would thin the track), worst-case recursion is ~3600 frames. Dart's default stack is ~10 000 frames so this is not an immediate production risk, but it is unbounded by the function's contract. `simplifyTrack` is called from `run_detail_screen.dart:969` on stored tracks; consider adding a depth limit or converting to an iterative implementation if tracks grow beyond a few thousand points. File as a known limitation in a code comment rather than a blocking issue.

---

- [`run_stats.dart:51-121`] **`fastestWindowOf` is missing a test for negative window or zero windowMetres**

  Line 71 guards `windowMetres <= 0` by returning null, but the test suite (`run_stats_test.dart`) has no test for that branch. Add a test: `expect(fastestWindowOf(track, 0), isNull)` and `expect(fastestWindowOf(track, -1), isNull)`.

---

## Stats
- P0: 3
- P1: 4
- P2: 5
- P3: 4
