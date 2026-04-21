import 'dart:async';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:api_client/api_client.dart';
import 'package:ui_kit/ui_kit.dart';

import 'audio_cues.dart';
import 'background_sync.dart';
import 'local_route_store.dart';
import 'local_run_store.dart';
import 'preferences.dart';
import 'race_controller.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'settings_sync.dart';
import 'social_service.dart';
import 'sync_service.dart';
import 'ble_heart_rate.dart';
import 'tile_cache.dart';
import 'training_service.dart';
import 'wear_auth_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Replace Flutter's default red-screen error widget in release builds
  // with a quiet fallback card. A crash inside a single subtree (most
  // likely the live map — flutter_map is the widest surface area in the
  // run screen) would otherwise take down the whole screen, including
  // the recording stats. RunRecorder lives outside the widget tree, so
  // recording itself keeps going while the user sees a replaced subtree.
  //
  // Kept as the default red screen in debug so we don't mask bugs during
  // development.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) {
      debugPrint('ErrorWidget: ${details.exception}');
      return Container(
        color: const Color(0xFF1E1B4B),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B),
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              "This section couldn't load.\nRecording is still running.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      );
    };
  }

  await dotenv.load(fileName: '.env.local');

  // Disk-backed map tile cache. Survives app restarts so repeated runs in
  // the same area render the basemap from disk instead of re-downloading.
  await TileCache.init();

  final store = LocalRunStore();
  await store.init();

  // Recover a run that was in progress when the app was last killed
  // (crash, force-stop, OOM). We promote the partial data to a regular
  // completed run so at least the user keeps whatever was captured. Only
  // runs with meaningful content are kept — tiny "I tapped start then
  // backgrounded" runs are dropped silently.
  //
  // An indoor (pedometer-only) run has no track and its distance came
  // from `steps × stride`. For those, we accept the run if duration ≥ 60s
  // instead of requiring GPS waypoints — a treadmill session that crashed
  // after 10 minutes shouldn't evaporate just because there are no fixes.
  cm.Run? recoveredRun;
  try {
    final partial = await store.loadInProgress();
    final indoorEstimated =
        partial?.metadata?['indoor_estimated'] == true;
    final hasEnoughGps = partial != null &&
        partial.track.length >= 3 &&
        partial.distanceMetres >= 50;
    final hasEnoughIndoor = partial != null &&
        indoorEstimated &&
        partial.duration.inSeconds >= 60;
    if (hasEnoughGps || hasEnoughIndoor) {
      final metadata = Map<String, dynamic>.from(partial.metadata ?? {});
      metadata['recovered_from_crash'] = true;
      final recovered = cm.Run(
        id: partial.id,
        startedAt: partial.startedAt,
        duration: partial.duration,
        distanceMetres: partial.distanceMetres,
        track: partial.track,
        routeId: partial.routeId,
        source: partial.source,
        externalId: partial.externalId,
        metadata: metadata,
        createdAt: partial.createdAt,
      );
      await store.save(recovered);
      recoveredRun = recovered;
    }
    await store.clearInProgress();
  } catch (e) {
    debugPrint('In-progress recovery failed: $e');
  }

  final routeStore = LocalRouteStore();
  await routeStore.init();

  final prefs = Preferences();
  await prefs.init();

  final audioCues = AudioCues();

  // Try to initialize Supabase — skip if not configured or unreachable
  ApiClient? api;
  SettingsSyncService? settingsSync;
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl != null && supabaseUrl.isNotEmpty &&
      anonKey != null && anonKey.isNotEmpty) {
    try {
      await ApiClient.initialize(url: supabaseUrl, anonKey: anonKey);
      api = ApiClient();

      // Forward the Supabase session to the paired Wear OS watch whenever
      // it changes. No-op if no watch is paired — DataClient just holds
      // the DataItem until one shows up.
      WearAuthBridge().attach(url: supabaseUrl, anonKey: anonKey);

      final devEmail = dotenv.env['DEV_USER_EMAIL'];
      final devPassword = dotenv.env['DEV_USER_PASSWORD'];
      if (devEmail != null && devEmail.isNotEmpty &&
          devPassword != null && devPassword.isNotEmpty) {
        try {
          await api.signIn(email: devEmail, password: devPassword);
        } catch (e) {
          debugPrint('Auto sign-in failed: $e');
        }
      }
      settingsSync = SettingsSyncService(preferences: prefs);
      // Best-effort — a failed settings sync shouldn't block launch. The
      // service stores `lastError` for the settings screen to surface.
      try {
        await settingsSync.onSignedIn();
      } catch (e) {
        debugPrint('Settings sync failed: $e');
      }
    } catch (e) {
      debugPrint('Supabase init failed, running offline: $e');
      api = null;
    }
  }

  final syncService = SyncService(apiClient: api, runStore: store);
  syncService.start();

  // Background sync for all users. The gate infrastructure exists in
  // features.ts / paywall.md if this needs to be paywalled later.
  registerBackgroundSync();

  final social = SocialService();
  final raceController = RaceController(social);
  unawaited(raceController.start());
  final training = TrainingService();
  final heartRate = BleHeartRate();
  // Kick off auto-reconnect in the background. If the user has paired a
  // strap previously, HR is ready when they tap Start; otherwise it's a
  // no-op and the run records without HR.
  unawaited(heartRate.connectCached());

  runApp(RunApp(
    apiClient: api,
    runStore: store,
    routeStore: routeStore,
    preferences: prefs,
    audioCues: audioCues,
    syncService: syncService,
    settingsSync: settingsSync,
    social: social,
    raceController: raceController,
    training: training,
    heartRate: heartRate,
    recoveredRun: recoveredRun,
  ));
}

class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark);
}

final themeModeNotifier = ThemeModeNotifier();

class RunApp extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final AudioCues audioCues;
  final SyncService syncService;
  final SettingsSyncService? settingsSync;
  final SocialService social;
  final RaceController raceController;
  final TrainingService training;
  final BleHeartRate heartRate;
  final cm.Run? recoveredRun;
  const RunApp({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
    required this.syncService,
    this.settingsSync,
    required this.social,
    required this.raceController,
    required this.training,
    required this.heartRate,
    this.recoveredRun,
  });

  @override
  State<RunApp> createState() => _RunAppState();
}

class _RunAppState extends State<RunApp> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    final recovered = widget.recoveredRun;
    if (recovered != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Recovered unfinished run — '
              '${(recovered.distanceMetres / 1000).toStringAsFixed(2)} km, '
              '${recovered.duration.inMinutes} min',
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                // Navigating from a root snackbar action is app-specific —
                // for now the run is already in history, surfaced by the
                // default list view. Dismiss the snackbar.
                _messengerKey.currentState?.hideCurrentSnackBar();
              },
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Better Runner',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          scaffoldMessengerKey: _messengerKey,
          home: widget.preferences.onboarded
              ? HomeScreen(
                  apiClient: widget.apiClient,
                  runStore: widget.runStore,
                  routeStore: widget.routeStore,
                  preferences: widget.preferences,
                  audioCues: widget.audioCues,
                  social: widget.social,
                  raceController: widget.raceController,
                  training: widget.training,
                  heartRate: widget.heartRate,
                  settingsSync: widget.settingsSync,
                )
              : OnboardingScreen(
                  preferences: widget.preferences,
                  onDone: () => setState(() {}),
                ),
        );
      },
    );
  }
}
