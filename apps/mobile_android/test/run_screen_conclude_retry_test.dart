import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart' hide Route;
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
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/widgets/live_share_indicator.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

/// Stopping the live share mid-run detaches the broadcaster whether or not
/// its `concludeLiveBroadcast` call landed. The run-stop wind-down then read
/// the detached broadcaster as "nothing to conclude" and skipped the stamp, so
/// a runner who stopped sharing while offline left every spectator on a frozen
/// live trace with no conclusion, permanently.
///
/// Harness mirrors run_screen_live_visibility_test.dart (geolocator /
/// wakelock / permission / tts / notification-bridge mocks; spy run
/// store so the save stays on the fake clock).

/// Signed-in fake that records the visibility + broadcast calls the stop
/// path makes. Every remote leg the stop path touches is overridden so
/// nothing reaches the (uninitialised-network) Supabase client.
class _LiveApi extends ApiClient {
  final List<String> calls = [];

  @override
  String? get userId => 'user-1';

  @override
  Future<void> beginLiveBroadcast({
    required String runId,
    required DateTime startedAt,
    String activityType = 'run',
  }) async {
    calls.add('begin');
  }

  @override
  Future<void> insertLivePing({
    required String runId,
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
  }) async {}

  @override
  Future<List<RouteMatchCandidate>> fetchRoutesIntersectingTrack(
    List<Waypoint> track, {
    double toleranceMetres = 100,
    int maxResults = 10,
  }) async =>
      const [];

  @override
  Future<void> saveRun(Run run, {bool? isPublic}) async {
    calls.add('saveRun(isPublic: $isPublic)');
  }

  @override
  Future<void> makeRunPublic(String runId) async {
    calls.add('makeRunPublic');
  }

  @override
  Future<void> makeRunPrivate(String runId) async {
    calls.add('makeRunPrivate');
  }

  /// Number of leading `concludeLiveBroadcast` calls that throw, standing in
  /// for the runner being out of signal when they stop the share.
  int failConcludes = 0;

  @override
  Future<void> concludeLiveBroadcast(String runId) async {
    if (failConcludes > 0) {
      failConcludes--;
      calls.add('conclude-failed');
      throw Exception('offline');
    }
    calls.add('conclude');
  }
}

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

  void emit(Position p) {
    _positions ??= StreamController<Position>.broadcast();
    _positions!.add(p);
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

/// Spy store — captures saves in memory so the Finish flow stays on the
/// fake clock (see run_screen_recording_flow_test.dart for the rationale).
class _CapturingRunStore extends LocalRunStore {
  final List<dynamic> captured = [];

  @override
  Future<Run> save(run) async {
    captured.add(run);
    // save() returns the RESIDENT instance so markManySynced can identify it;
    // the spy has no store, so the argument IS the resident copy here.
    return run;
  }

  @override
  Future<void> clearInProgress() async {}

  @override
  Future<void> markSynced(String id) async {}
}

class _NoOpWakelock extends WakelockPlusPlatformInterface {
  bool _on = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async {
    _on = enable;
  }

  @override
  Future<bool> get enabled async => _on;
}

Position _pos({
  required double metresEast,
  required int secondsFromStart,
}) {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;
  return Position(
    longitude: lngBase + metresEast / metrePerDegLng,
    latitude: lat,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: 5,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 2.5,
    speedAccuracy: 1,
  );
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

    mockMethodChannel('flutter.baseflow.com/permissions/methods',
        (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
        case 'requestPermissions':
          if (call.arguments is List) {
            return {for (final p in (call.arguments as List)) p: 1};
          }
          return 1;
        default:
          return null;
      }
    });
    mockMethodChannel('flutter_tts', (call) async => 1);
    mockMethodChannel('run_app/run_notification', (call) async => null);
    // share_plus — the pre-start "Share live link" hands the URL to the OS
    // sheet; resolve it so the test doesn't rely on the caught
    // MissingPluginException path.
    mockMethodChannel('dev.fluttercommunity.plus/share', (call) async => '');
    mockEventChannelAsSilent('step_count');
    mockEventChannelAsSilent('step_detection');

    runsDir = Directory.systemTemp.createTempSync('run_screen_live_vis_');
  });

  /// The store the last `pumpLiveRunScreen` built, so the teardown can wait on
  /// the in-progress recording write before deleting the directory under it.
  _CapturingRunStore? lastRunStore;

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
    // The incremental-save Timer.periodic drives `saveInProgress` fire-and-
    // forget, and that path is deliberately off the store's write chain, so
    // `debugWritesSettled()` does not answer for it. Deleting `runsDir` with
    // an append still in the air is the § 723 race — wait on the path's own
    // signal first (decisions § 1012).
    await lastRunStore?.debugInProgressSettled();
    lastRunStore = null;
    if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  });

  Future<({_LiveApi api, _CapturingRunStore runStore, Preferences prefs})>
      pumpLiveRunScreen(WidgetTester tester,
          {String privacyDefault = 'private'}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await prefs.setPrivacyDefault(privacyDefault);

    final api = _LiveApi();
    final runStore = _CapturingRunStore();
    lastRunStore = runStore;
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunScreen(
          apiClient: api,
          runStore: runStore,
          routeStore: LocalRouteStore(),
          preferences: prefs,
          audioCues: AudioCues(),
          social: social,
          raceController: RaceController(social),
          training: TrainingService(),
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
        ),
      ),
    );
    await tester.pump();
    return (api: api, runStore: runStore, prefs: prefs);
  }

  /// Share the live link pre-start (attaches the broadcaster via the fake
  /// api), run through the countdown, feed a short track.
  Future<void> shareAndRecord(WidgetTester tester, _LiveApi api) async {
    await tester.tap(find.text('Share live link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls, contains('begin'),
        reason: 'the pre-start share must begin the live broadcast');

    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException(); // LiveRunMap tile-fetch noise

    for (var i = 0; i < 5; i++) {
      geolocator.emit(_pos(metresEast: i * 12.0, secondsFromStart: i * 2));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  Future<void> drainAndUnmount(WidgetTester tester) async {
    tester.takeException();
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  group('RunScreen — the conclusion stamp is owed until it lands', () {
    testWidgets('a stop-share whose stamp failed is retried when the run ends',
        (tester) async {
      final s = await pumpLiveRunScreen(tester);
      s.api.failConcludes = 1;
      await shareAndRecord(tester, s.api);

      await tester.tap(find.byType(LiveShareIndicator));
      // pumpAndSettle never settles here — LiveRunMap animates continuously.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Stop sharing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(s.api.calls, contains('conclude-failed'));
      expect(s.api.calls, isNot(contains('conclude')));
      tester.takeException();

      await holdFinish(tester);
      tester.takeException();

      expect(s.api.calls, contains('conclude'),
          reason: 'the spectator page needs the conclusion marker; the '
              'stop-share attempt that failed does not discharge it');

      await drainAndUnmount(tester);
    });

    testWidgets('a stop-share that succeeded is not stamped twice',
        (tester) async {
      final s = await pumpLiveRunScreen(tester);
      await shareAndRecord(tester, s.api);

      await tester.tap(find.byType(LiveShareIndicator));
      // pumpAndSettle never settles here — LiveRunMap animates continuously.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Stop sharing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      await holdFinish(tester);
      tester.takeException();

      expect(s.api.calls.where((c) => c == 'conclude'), hasLength(1));

      await drainAndUnmount(tester);
    });
  });
}
