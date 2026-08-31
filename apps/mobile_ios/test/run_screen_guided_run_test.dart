import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/guided_runs.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/main.dart' show pendingArmGuidedRun;
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/run_screen.dart';
import '../lib/sim_watch_sync.dart' show WatchBleTransport;
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/watch_settings.dart';
import 'pump_until.dart';

/// Drives the REAL RunScreen through the REAL guided-run affordance and the
/// REAL recorder tick — not a replica of the screen's wiring beside it
/// (decisions § 704).
///
/// The scripted cues sit on minute marks and the recorder's elapsed clock is a
/// real `Stopwatch` (flutter_test's fake clock does not reach it), so the mark
/// these tests can actually cross is the script's own 0:00 opener. That is
/// enough to pin what matters at this seam: that a cue fires at all, that it
/// fires exactly once however many ticks arrive, that each gate silences it,
/// and that a throwing TTS engine cannot take the recording down. The
/// clock-source rule the pause behaviour rests on is pinned by the source
/// guard at the bottom of this file, against the already-tested recorder
/// invariant that its stopwatch stops while paused
/// (`packages/run_recorder/test/run_recorder_test.dart`).

const _localBackend = 'http://127.0.0.1:54321';
const _prodBackend = 'https://abcdefgh.supabase.co';

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  StreamController<Position>? _positions;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    _positions ??= StreamController<Position>.broadcast();
    return _positions!.stream;
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

class _NoOpWakelock extends WakelockPlusPlatformInterface {
  bool _on = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async => _on = enable;

  @override
  Future<bool> get enabled async => _on;
}

/// Records every guided cue the recorder decides to speak, without touching
/// the TTS engine. [throwOnCue] drives the L4-isolation case.
class _SpyAudioCues extends AudioCues {
  _SpyAudioCues({this.throwOnCue = false});

  final bool throwOnCue;
  final List<String> spoken = [];

  @override
  Future<void> announceGuidedCue(String text) async {
    spoken.add(text);
    if (throwOnCue) throw StateError('TTS engine is gone');
  }

  @override
  Future<void> announceStart() async {}

  @override
  Future<void> announceFinish({
    required double distanceMetres,
    required Duration elapsed,
    required DistanceUnit unit,
  }) async {}
}

/// Captures `save` / `saveInProgress` in memory — the real store's file I/O
/// does not resolve under the fake test clock.
class _CapturingRunStore extends LocalRunStore {
  final List<cm.Run> captured = [];
  final List<cm.Run> capturedInProgress = [];

  @override
  Future<cm.Run> save(run) async {
    captured.add(run);
    return run;
  }

  @override
  Future<void> saveInProgress(run) async => capturedInProgress.add(run);

  @override
  Future<void> clearInProgress() async {}
}

/// Settings-only transport: the guided-run arm writes one SET1 frame and
/// nothing else is exercised. An empty `readPushStatus` is a watch with no
/// verdict, which leaves the push unconfirmed rather than retrying.
class _FakeSettingsTransport implements WatchBleTransport {
  final settingsWrites = <List<int>>[];
  int scans = 0;
  int disconnects = 0;

  @override
  Future<void> scan() async => scans++;
  @override
  Future<void> disconnect() async => disconnects++;
  @override
  Future<List<int>> readPushStatus() async => const [];
  @override
  Stream<List<int>> get chunkStream => const Stream<List<int>>.empty();
  @override
  Future<List<int>> readManifest() async => const [];
  @override
  Future<void> writeChunkRequest(List<int> request) async {}
  @override
  Future<void> writeWorkout(List<int> chunk) async {}
  @override
  Future<void> writeScreens(List<int> frame) async {}
  @override
  Future<void> writeCourse(List<int> chunk) async {}
  @override
  Future<void> writeRoadbook(List<int> chunk) async {}

  @override
  Future<void> writeSettings(List<int> frame) async => settingsWrites.add(frame);

  /// The NUL-trimmed ASCII guided-run id carried by the last frame written,
  /// read back off the wire layout rather than off the object that built it.
  String? get lastGuidedRunId {
    if (settingsWrites.isEmpty) return null;
    final frame = settingsWrites.last;
    if (frame[6] & 0x20 == 0) return null;
    final id = frame.sublist(8, 8 + guidedRunIdLen);
    return String.fromCharCodes(id.takeWhile((b) => b != 0));
  }
}

void main() {
  late _FakeGeolocatorPlatform geolocator;
  late Directory runsDir;
  bool supabaseReady = false;

  final mockedMethodChannels = <String>[];
  final mockedEventChannels = <String>[];

  void mockMethodChannel(
      String name, Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), handler);
    mockedMethodChannels.add(name);
  }

  void mockEventChannelAsSilent(String name) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel(name, const StandardMethodCodec()),
      (call) async => null,
    );
    mockedEventChannels.add(name);
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // A scheme dart:io rejects synchronously, so LiveRunMap's tile fetches
    // fail immediately instead of parking fake-async timers.
    dotenv.loadFromString(
      envString: 'TILE_URL_TEMPLATE=offline-no-network://tiles/{z}/{x}/{y}.png',
      isOptional: true,
    );
    if (!supabaseReady) {
      await Supabase.initialize(
        url: 'http://127.0.0.1:54321',
        anonKey: 'eyJ.local.test',
      );
      supabaseReady = true;
    }
  });

  setUp(() async {
    geolocator = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocator;
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();

    mockMethodChannel('flutter.baseflow.com/permissions/methods', (call) async {
      if (call.arguments is List) {
        return {for (final p in (call.arguments as List)) p: 1};
      }
      return 1;
    });
    mockMethodChannel('flutter_tts', (call) async => 1);
    mockMethodChannel('run_app/run_notification', (call) async => null);
    mockEventChannelAsSilent('step_count');
    mockEventChannelAsSilent('step_detection');

    runsDir = Directory.systemTemp.createTempSync('run_screen_guided_');
  });

  tearDown(() async {
    for (final name in mockedMethodChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
    for (final name in mockedEventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel(name, const StandardMethodCodec()),
        null,
      );
    }
    mockedMethodChannels.clear();
    mockedEventChannels.clear();
    await geolocator.dispose();
    pendingArmGuidedRun.value = null;
    if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  });

  /// Mount the real RunScreen. [backendUrl] drives the custom-watch gate.
  Future<
      ({
        _SpyAudioCues cues,
        Preferences prefs,
        _CapturingRunStore runStore,
        _FakeSettingsTransport watch,
      })> pumpRunScreen(
    WidgetTester tester, {
    bool throwOnCue = false,
    String backendUrl = _prodBackend,
    Future<void> Function(Preferences prefs)? configure,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await configure?.call(prefs);

    final runStore = _CapturingRunStore();
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();
    final cues = _SpyAudioCues(throwOnCue: throwOnCue);
    final watch = _FakeSettingsTransport();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunScreen(
          apiClient: null,
          runStore: runStore,
          routeStore: LocalRouteStore(),
          preferences: prefs,
          audioCues: cues,
          social: social,
          raceController: RaceController(social),
          training: TrainingService(),
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
          devBackendUrl: backendUrl,
          watchTransportFactory: () => watch,
        ),
      ),
    );
    await tester.pump();
    return (cues: cues, prefs: prefs, runStore: runStore, watch: watch);
  }

  /// Open the idle picker and choose the row labelled [title].
  Future<void> armGuidedRun(WidgetTester tester, String title) async {
    await tester.tap(find.byIcon(Icons.headset_mic_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  /// START → countdown → recording, then [ticks] further recorder snapshots.
  Future<void> startRecording(WidgetTester tester, {int ticks = 4}) async {
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // LiveRunMap's tile fetches log DioExceptions in the test env.
    tester.takeException();
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    tester.takeException();
  }

  const easyTitle = '30-Minute Easy Run';
  const easyOpener = 'Let’s go. Start easy — this is your recovery pace.';
  const firstTimerTitle = 'First-Timer 15-Minute Run/Walk';

  group('RunScreen — arming a guided run', () {
    testWidgets('the idle affordance names the armed run, and can clear it',
        (tester) async {
      await pumpRunScreen(tester);

      // Nothing armed: the affordance offers itself by name.
      expect(find.text('Guided run'), findsOneWidget);
      expect(find.text(easyTitle), findsNothing);

      await armGuidedRun(tester, easyTitle);
      expect(find.text(easyTitle), findsOneWidget,
          reason: 'the idle affordance must show WHICH run is armed');
      expect(find.text('Guided run'), findsNothing);

      // Re-open and clear.
      await tester.tap(find.text(easyTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No guided run'));
      await tester.pumpAndSettle();
      expect(find.text('Guided run'), findsOneWidget);
      expect(find.text(easyTitle), findsNothing);
    });

    testWidgets('every shipped guided run is offered', (tester) async {
      await pumpRunScreen(tester);
      await tester.tap(find.byIcon(Icons.headset_mic_outlined));
      await tester.pumpAndSettle();
      for (final g in guidedRunLibrary(
          await AppLocalizations.delegate.load(const Locale('en')))) {
        expect(find.text(g.title), findsOneWidget,
            reason: '${g.id} must be reachable from the run screen');
      }
      await tester.tap(find.text('No guided run'));
      await tester.pumpAndSettle();
    });
  });

  group('RunScreen — the guided-run handoff', () {
    testWidgets('an id parked before the screen exists arms it', (tester) async {
      // The Run tab is built lazily, so a detail screen deeper in the stack
      // routinely parks the id before this State has ever existed.
      pendingArmGuidedRun.value = 'easy-30';
      await pumpRunScreen(tester);

      expect(find.text(easyTitle), findsOneWidget);
      expect(pendingArmGuidedRun.value, isNull,
          reason: 'the handoff is spent on arrival');
    });

    testWidgets('an id parked while the screen is up arms it', (tester) async {
      await pumpRunScreen(tester);
      expect(find.text('Guided run'), findsOneWidget);

      pendingArmGuidedRun.value = 'first-timer-15';
      await tester.pump();

      expect(find.text(firstTimerTitle), findsOneWidget);
      expect(pendingArmGuidedRun.value, isNull);
    });

    testWidgets('a second visit to the Run tab does not re-arm', (tester) async {
      pendingArmGuidedRun.value = 'easy-30';
      await pumpRunScreen(tester);
      expect(find.text(easyTitle), findsOneWidget);

      // Tear the screen down and come back. An id left parked would arm the
      // script again on a visit the runner never asked for it on.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpRunScreen(tester);

      expect(find.text(easyTitle), findsNothing);
      expect(find.text('Guided run'), findsOneWidget);
    });

    testWidgets('the handoff arms down the same path the picker uses',
        (tester) async {
      // The wrist push is what proves it: a second arming path that skipped
      // _armGuidedRun would leave the watch on whatever it was last told.
      pendingArmGuidedRun.value = 'easy-30';
      final s = await pumpRunScreen(tester, backendUrl: _localBackend);
      await pumpUntil(tester, () => s.watch.settingsWrites.isNotEmpty,
          describe: 'the guided-run SET1 frame to reach the watch');
      expect(s.watch.lastGuidedRunId, 'easy-30');
    });

    testWidgets('an id no build ships is dropped, not armed', (tester) async {
      pendingArmGuidedRun.value = 'easy-30-remix';
      await pumpRunScreen(tester);

      expect(find.text('Guided run'), findsOneWidget);
      expect(pendingArmGuidedRun.value, isNull);
    });
  });

  group('RunScreen — guided cues on the recorder tick', () {
    testWidgets('the script opener speaks once, and only once', (tester) async {
      final s = await pumpRunScreen(tester);
      await armGuidedRun(tester, easyTitle);
      await startRecording(tester, ticks: 8);

      expect(s.cues.spoken, [easyOpener],
          reason: 'the 0:00 cue fires on the first tick and must not re-fire '
              'as further snapshots arrive at the same elapsed second');
    });

    testWidgets('no guided run armed speaks nothing', (tester) async {
      final s = await pumpRunScreen(tester);
      await startRecording(tester, ticks: 8);
      expect(s.cues.spoken, isEmpty);
    });

    testWidgets('the master voice gate silences the script', (tester) async {
      final s = await pumpRunScreen(
        tester,
        configure: (prefs) => prefs.setAudioCues(false),
      );
      await armGuidedRun(tester, easyTitle);
      await startRecording(tester, ticks: 4);
      expect(s.cues.spoken, isEmpty);
    });

    testWidgets('the guided_run per-cue toggle silences the script',
        (tester) async {
      final s = await pumpRunScreen(
        tester,
        configure: (prefs) =>
            prefs.setVoiceCueEnabled(VoiceCue.guidedRun, false),
      );
      await armGuidedRun(tester, easyTitle);
      await startRecording(tester, ticks: 4);
      expect(s.cues.spoken, isEmpty);
    });

    testWidgets('muting workout steps does NOT silence a guided run',
        (tester) async {
      // The whole reason guided_run is its own id: a runner who turned off a
      // structured workout's step calls has said nothing about coach scripts.
      final s = await pumpRunScreen(
        tester,
        configure: (prefs) =>
            prefs.setVoiceCueEnabled(VoiceCue.workoutSteps, false),
      );
      await armGuidedRun(tester, easyTitle);
      await startRecording(tester, ticks: 4);
      expect(s.cues.spoken, [easyOpener]);
    });

    testWidgets('a throwing TTS engine leaves the recording stack intact',
        (tester) async {
      final s = await pumpRunScreen(tester, throwOnCue: true);
      await armGuidedRun(tester, firstTimerTitle);
      await startRecording(tester, ticks: 6);

      expect(s.cues.spoken, hasLength(1),
          reason: 'the cue was attempted, and the failure did not re-arm it');
      expect(tester.takeException(), isNull,
          reason: 'an L4 cue failure must not escape as an unhandled error');

      // L0/L1 are still live: the recording surface is up and the real stop
      // path still saves the run.
      final stopped = await holdFinish(tester);
      expect(stopped(), isTrue);
      expect(s.runStore.captured, hasLength(1),
          reason: 'the run must still save after an L4 cue threw');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a manual pause keeps the run armed and speaks nothing more',
        (tester) async {
      // The cue clock is the recorder's stopwatch, which stops on pause, so a
      // pause must hold the runner's place in the script — not disarm it, not
      // reset the cursor, and not fire the marks it is sitting between.
      final s = await pumpRunScreen(tester);
      await armGuidedRun(tester, easyTitle);
      await startRecording(tester, ticks: 3);
      expect(s.cues.spoken, [easyOpener]);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget,
          reason: 'the control must now offer Resume');
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      tester.takeException();
      expect(s.cues.spoken, [easyOpener],
          reason: 'a paused run holds its place in the script');

      // Resume, and the run is still the one that was armed.
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      tester.takeException();
      expect(s.cues.spoken, [easyOpener]);

      final stopped = await holdFinish(tester);
      expect(stopped(), isTrue);
      expect(
        s.runStore.captured.single.metadata?[cm.MetadataKeys.guidedRunId],
        'easy-30',
        reason: 'the pause must not have dropped the arming',
      );
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('RunScreen — what a guided run leaves behind', () {
    testWidgets('the crash checkpoint carries the arming too', (tester) async {
      // A process-kill mid-script must not cost the recovered run its
      // attribution — the incremental save mirrors what _stop writes.
      final s = await pumpRunScreen(tester);
      await armGuidedRun(tester, easyTitle);
      await startRecording(tester, ticks: 12);
      await pumpUntil(tester, () => s.runStore.capturedInProgress.isNotEmpty,
          describe: 'the 10 s in-progress checkpoint');
      expect(
        s.runStore.capturedInProgress.last.metadata?[
            cm.MetadataKeys.guidedRunId],
        'easy-30',
      );
    });

    testWidgets('finishing stamps guided_run_id and disarms the run',
        (tester) async {
      final s = await pumpRunScreen(tester);
      await armGuidedRun(tester, firstTimerTitle);
      await startRecording(tester, ticks: 3);

      final stopped = await holdFinish(tester);
      expect(stopped(), isTrue);

      expect(s.runStore.captured, hasLength(1));
      expect(
        s.runStore.captured.single.metadata?[cm.MetadataKeys.guidedRunId],
        'first-timer-15',
        reason: 'the saved run must name the script it was recorded under',
      );

      // The arm is spent: the next recording starts silent unless re-armed.
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(firstTimerTitle), findsNothing);
    });

    testWidgets('no guided run armed leaves the key off the saved run',
        (tester) async {
      final s = await pumpRunScreen(tester);
      await startRecording(tester, ticks: 2);
      final stopped = await holdFinish(tester);
      expect(stopped(), isTrue);
      expect(s.runStore.captured, hasLength(1));
      expect(
        s.runStore.captured.single.metadata
            ?.containsKey(cm.MetadataKeys.guidedRunId),
        isNot(isTrue),
      );
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('RunScreen — arming the wrist', () {
    testWidgets('arming pushes the library id to the watch', (tester) async {
      final s = await pumpRunScreen(tester, backendUrl: _localBackend);
      await armGuidedRun(tester, easyTitle);
      await pumpUntil(tester, () => s.watch.settingsWrites.isNotEmpty,
          describe: 'the guided-run SET1 frame to reach the watch');
      expect(s.watch.lastGuidedRunId, 'easy-30',
          reason: 'the wire carries the library id, never a library index');
    });

    testWidgets('clearing pushes the empty id that deselects', (tester) async {
      final s = await pumpRunScreen(tester, backendUrl: _localBackend);
      await armGuidedRun(tester, easyTitle);
      await pumpUntil(tester, () => s.watch.settingsWrites.isNotEmpty,
          describe: 'the arming frame');

      await tester.tap(find.text(easyTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No guided run'));
      await tester.pumpAndSettle();
      await pumpUntil(tester, () => s.watch.settingsWrites.length >= 2,
          describe: 'the disarming frame');
      expect(s.watch.lastGuidedRunId, '');
    });

    testWidgets('against a production backend nothing reaches the radio',
        (tester) async {
      // The custom watch is research-tier with no unit in anyone's hands
      // (decisions § 71) — the same loopback gate every other push carries.
      final s = await pumpRunScreen(tester, backendUrl: _prodBackend);
      await armGuidedRun(tester, easyTitle);
      await tester.pump(const Duration(milliseconds: 200));
      expect(s.watch.scans, 0);
      expect(s.watch.settingsWrites, isEmpty);
    });
  });

  group('RunScreen — guided cue clock (source guard)', () {
    // The cue marks are minutes apart and the recorder's elapsed clock is a
    // real Stopwatch, so a widget test cannot cross one. These pin the two
    // properties that behaviour rests on.
    final src = File('lib/screens/run_screen.dart').readAsStringSync();
    final block = src.substring(
      src.indexOf('// L4 — Guided-run coach cues.'),
      src.indexOf("debugPrint('guided-run cue dispatch failed"),
    );

    test('the clock is the recorder elapsed, which stops on a manual pause',
        () {
      // `RunRecorder.pause()` stops the monotonic stopwatch
      // (run_recorder_test.dart, "stopwatch stops during pause"), so reading
      // snapshot.elapsed is what makes a paused run hold its place in the
      // script instead of skipping past cues nobody heard. A wall-clock read
      // here would silently undo that.
      expect(block.contains('snapshot.elapsed.inSeconds'), isTrue);
      expect(block.contains('DateTime.now()'), isFalse);
    });

    test('the cursor only ever advances', () {
      // cuesDue is idempotent over a range, but only while the range floor
      // never walks backwards — a rewound cursor would re-speak every mark
      // between the two.
      expect(block.contains('nowSec > _guidedCueSec'), isTrue);
      expect(block.contains('_guidedCueSec = nowSec;'), isTrue);
    });
  });
}
