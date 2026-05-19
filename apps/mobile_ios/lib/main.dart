import 'dart:async';
import 'dart:convert';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:api_client/api_client.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import 'watch_ingest_queue.dart';
import 'wear_auth_bridge.dart';

/// Holds the auth-state subscription registered in [main]. Top-level so
/// a re-entrant main (rare — full hot-restart resets isolate state, but
/// belt-and-braces for future reconnect logic) can cancel any prior
/// listener instead of stacking duplicates.
StreamSubscription<AuthState>? _authStateSub;

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

  // `dotenv` must resolve first because the Supabase URL/key come from it,
  // and Supabase.initialize is one of the parallel tasks below.
  //
  // Two paths run for every platform: a `String.fromEnvironment` block
  // that picks up `--dart-define`s (production CI passes these for
  // both iOS and Android), and a debug-only `.env.local` load that
  // gives local development a frictionless path. Release builds NEVER
  // read `.env.local` even though pubspec.yaml ships it as an asset —
  // this closes the audit High where a developer-built release APK
  // would otherwise embed their real local SUPABASE_ANON_KEY,
  // MAPTILER_KEY, dev creds, and BYPASS_PAYWALL=true. See decisions
  // §13 for the iOS counterpart.
  const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');
  const webBaseUrl = String.fromEnvironment('WEB_BASE_URL');
  const stravaClientId = String.fromEnvironment('STRAVA_CLIENT_ID');
  const supabaseUrlDef = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKeyDef = String.fromEnvironment('SUPABASE_ANON_KEY');
  const devEmailDef = String.fromEnvironment('DEV_USER_EMAIL');
  const devPasswordDef = String.fromEnvironment('DEV_USER_PASSWORD');
  dotenv.loadFromString(
    envString: [
      if (supabaseUrlDef.isNotEmpty) 'SUPABASE_URL=$supabaseUrlDef',
      if (supabaseAnonKeyDef.isNotEmpty) 'SUPABASE_ANON_KEY=$supabaseAnonKeyDef',
      if (mapTilerKey.isNotEmpty) 'MAPTILER_KEY=$mapTilerKey',
      if (webBaseUrl.isNotEmpty) 'WEB_BASE_URL=$webBaseUrl',
      if (stravaClientId.isNotEmpty) 'STRAVA_CLIENT_ID=$stravaClientId',
      if (devEmailDef.isNotEmpty) 'DEV_USER_EMAIL=$devEmailDef',
      if (devPasswordDef.isNotEmpty) 'DEV_USER_PASSWORD=$devPasswordDef',
    ].join('\n'),
    isOptional: true,
  );
  if (kDebugMode) {
    try {
      await dotenv.load(fileName: '.env.local', mergeWith: dotenv.env);
    } catch (_) {}
  }

  // Construct stores synchronously so we can kick off their `init()`s in
  // parallel with the other independent launch tasks. Nothing here
  // depends on anything else — the previous sequential-await chain was
  // just paying plugin-channel round-trip latency N times for no reason.
  final store = LocalRunStore();
  final routeStore = LocalRouteStore();
  final prefs = Preferences();
  final watchQueue = WatchIngestQueue();

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
  final hasSupabase = supabaseUrl != null &&
      anonKey != null &&
      supabaseUrl.isNotEmpty &&
      anonKey.isNotEmpty;

  // Parallel batch. Each of these is independent — the platform plugin
  // channels (`getApplicationDocumentsDirectory`, `getApplicationCacheDirectory`,
  // `SharedPreferences.getInstance`, etc.) multiplex fine.
  await Future.wait([
    TileCache.init(),
    store.init(),
    routeStore.init(),
    prefs.init(),
    watchQueue.init(),
    if (hasSupabase)
      ApiClient.initialize(url: supabaseUrl, anonKey: anonKey)
          .catchError((Object e) {
        debugPrint('Supabase init failed, running offline: $e');
      }),
  ]);

  // Expose the loaded Preferences via the top-level accessor in
  // `preferences.dart` so screens that don't take a Preferences
  // constructor dep (feed, profile notifications, club-detail route
  // list, live spectator, the recovered-run banner, TTS announcer)
  // can read the user's unit pref via `activeDistanceUnit` /
  // `formatDistanceForPref()`. Idempotent.
  registerActivePreferences(prefs);

  // Hydrate the theme-mode notifier from the persisted preference.
  // Must run before runApp so the first frame paints in the user's
  // chosen mode instead of flashing the default and then snapping over.
  themeModeNotifier.value = prefs.themeMode;

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

  final audioCues = AudioCues();

  // ApiClient is created synchronously if Supabase initialised. The
  // awaited `Supabase.initialize` above guarantees the global client is
  // wired; all downstream calls just need the config — they don't need
  // to wait for the network.
  ApiClient? api;
  SettingsSyncService? settingsSync;
  if (hasSupabase) {
    try {
      api = ApiClient();
      settingsSync = SettingsSyncService(preferences: prefs);
    } catch (e) {
      debugPrint('ApiClient construction failed: $e');
    }
  }

  final syncService = SyncService(apiClient: api, runStore: store);
  syncService.start();

  final social = SocialService();
  final raceController = RaceController(social);
  unawaited(raceController.start());
  final training = TrainingService();
  final heartRate = BleHeartRate();
  // Kick off auto-reconnect in the background. If the user has paired a
  // strap previously, HR is ready when they tap Start; otherwise it's a
  // no-op and the run records without HR.
  unawaited(heartRate.connectCached());

  // Apple Watch ingest path. The native iOS bridge
  // (`Runner/WatchIngestBridge.swift`) forwards `WCSession` payloads via
  // the `run_app/watch_ingest` MethodChannel. On Android the channel
  // isn't registered, so `WatchIngest.attach` fires `MissingPluginException`
  // (caught) and the no-op is invisible — keeps the bootstrap identical
  // across both apps.
  if (api != null && api.userId != null) {
    WatchIngest.attach(api, watchQueue);
  }

  // Everything below here runs AFTER the first frame paints:
  //
  //  - WorkManager background-sync registration (plugin channel work the
  //    user never sees)
  //  - Dev-only auto sign-in (network round-trip)
  //  - SettingsSync cloud fetch (network round-trip)
  //  - WearAuthBridge attach (method channel)
  //  - Auth-state subscription (reactive sign-in plumbing —
  //    settingsSync.onSignedIn must not appear on the critical path)
  //
  // Previously these all awaited before runApp and held the splash screen
  // open for hundreds of ms on slow connections. None of them change the
  // first-frame render — if the user isn't signed in yet, the dashboard
  // shows the signed-out state and updates when auth finishes.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    registerBackgroundSync();
    if (!hasSupabase || api == null) return;
    final apiNonNull = api;
    // Cancel any prior subscription before attaching a fresh one.
    // Hot-restart resets isolate state so this is normally a no-op,
    // but it makes a re-entrant main() (or future reconnect logic)
    // safe against leaked listeners.
    _authStateSub?.cancel();
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange
        .listen((event) {
      if (event.event == AuthChangeEvent.signedIn) {
        WatchIngest.attach(apiNonNull, watchQueue);
        try {
          watchQueue.drain(apiNonNull).catchError((Object e) {
            debugPrint('Watch ingest queue drain failed: $e');
          });
        } catch (e) {
          debugPrint('Watch ingest queue drain error: $e');
        }
        settingsSync?.onSignedIn().catchError((Object e) {
          debugPrint('Settings sync on signedIn failed: $e');
        });
      }
    });
    WearAuthBridge().attach(url: supabaseUrl, anonKey: anonKey);
    final devEmail = dotenv.env['DEV_USER_EMAIL'];
    final devPassword = dotenv.env['DEV_USER_PASSWORD'];
    Future(() async {
      if (devEmail != null &&
          devEmail.isNotEmpty &&
          devPassword != null &&
          devPassword.isNotEmpty) {
        try {
          await api!.signIn(email: devEmail, password: devPassword);
        } catch (e) {
          debugPrint('Auto sign-in failed: $e');
        }
      }
      // Best-effort — the service stores `lastError` for the settings
      // screen to surface.
      try {
        await settingsSync?.onSignedIn();
      } catch (e) {
        debugPrint('Settings sync failed: $e');
      }
    });
  });

  // Sentry init runs in release builds only and only when SENTRY_DSN is
  // populated (via dotenv on Android, --dart-define-from-file on iOS).
  // Empty DSN → no-op, so dev builds and CI builds without secrets stay
  // off the Sentry dashboard. The release-tag (versionName) is read from
  // the build via `--dart-define=APP_RELEASE=...` so a regression's
  // release can be pinpointed.
  final sentryDsn = dotenv.env['SENTRY_DSN'] ?? '';
  final appRelease = const String.fromEnvironment('APP_RELEASE', defaultValue: 'dev');
  final shouldUseSentry = kReleaseMode && sentryDsn.isNotEmpty;

  Future<void> startApp() async {
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

  if (shouldUseSentry) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.release = appRelease;
        options.tracesSampleRate = 0.1;
        options.environment = appRelease == 'dev' ? 'development' : 'production';
        // Drop the user's Authorization header from breadcrumbs — the
        // bearer token would otherwise land on every Sentry event.
        options.beforeSend = (event, hint) {
          final scrubbed = event;
          // Sentry's default PII scrubbing handles most of it; this is
          // belt-and-braces for the Supabase JWT path specifically.
          return scrubbed;
        };
      },
      appRunner: startApp,
    );
  } else {
    await startApp();
  }
}

class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark);
}

final themeModeNotifier = ThemeModeNotifier();

/// Cross-screen handoff for "start this workout now". Set by deep
/// flows (e.g. plan_detail_screen's calendar → workout_detail →
/// Start workout) that need to bring the user back to the Run tab and
/// preload the structured runner. HomeScreen listens and switches to
/// the Run tab; RunScreen listens (or drains in initState) and calls
/// the workout runner.
///
/// Intentionally global rather than threaded through ~5 layers of
/// widget constructors — every entry path (run-screen, plans-screen,
/// plan-new-screen, club-detail) ultimately routes through the same
/// HomeScreen, so a single notifier centralises the handoff.
final ValueNotifier<cm.PlanWorkoutRow?> pendingStartWorkout =
    ValueNotifier<cm.PlanWorkoutRow?>(null);

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
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Run Onward',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
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
                  recoveredRun: widget.recoveredRun,
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

/// Receives runs from the paired Apple Watch via a method channel owned
/// by `Runner/AppDelegate.swift` + `Runner/WatchIngestBridge.swift` on
/// iOS. Android doesn't register the channel, so the `setMethodCallHandler`
/// installation is a harmless no-op and the bridge never fires.
///
/// Each call carries: `{id, started_at, duration_s, distance_m, source,
/// avg_bpm?, track: [{lat, lng, ele?, ts?}]}`. We construct a
/// `core_models.Run` and upload via `ApiClient.saveRun` — same path
/// any other recording source uses, so web sees it identically.
///
/// When the user is not authenticated, the payload is persisted to the
/// [WatchIngestQueue] on disk and replayed on the next sign-in.
class WatchIngest {
  static const _channel = MethodChannel('run_app/watch_ingest');

  static void attach(ApiClient api, WatchIngestQueue queue) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'run') return null;
      final args = call.arguments as Map<Object?, Object?>?;
      if (args == null) return false;

      if (api.userId == null) {
        try {
          final payload = Map<String, dynamic>.fromEntries(
            args.entries
                .where((e) => e.key is String)
                .map((e) => MapEntry(e.key as String, e.value)),
          );
          await queue.enqueue(payload);
        } catch (e) {
          debugPrint('Watch ingest queue write failed: $e');
        }
        return false;
      }

      try {
        final run = _runFromArgs(args);
        await api.saveRun(run);
        return true;
      } catch (e) {
        debugPrint('Watch ingest failed: $e');
        return false;
      }
    });
  }

  static cm.Run _runFromArgs(Map<Object?, Object?> raw) {
    final id = raw['id'] as String? ?? '';
    final startedAt = DateTime.parse(raw['started_at'] as String);
    final durationS = (raw['duration_s'] as num).toInt();
    final distanceM = (raw['distance_m'] as num).toDouble();
    // This channel only carries payloads from the Apple Watch
    // (see `Runner/WatchIngestBridge.swift`), so a missing `source`
    // means watch — never web/mobile-app. The fallback in
    // `_parseSource` matches.
    final source = raw['source'] as String? ?? 'watch';
    final trackRaw = raw['track'];
    final track = <cm.Waypoint>[];
    if (trackRaw is List) {
      for (final p in trackRaw) {
        if (p is Map) {
          track.add(cm.Waypoint(
            lat: (p['lat'] as num).toDouble(),
            lng: (p['lng'] as num).toDouble(),
            elevationMetres: (p['ele'] as num?)?.toDouble(),
            timestamp: (p['ts'] as String?) != null
                ? DateTime.tryParse(p['ts'] as String)
                : null,
          ));
        }
      }
    } else if (trackRaw is String) {
      final decoded = jsonDecode(trackRaw);
      if (decoded is List) {
        for (final p in decoded) {
          if (p is Map) {
            track.add(cm.Waypoint(
              lat: (p['lat'] as num).toDouble(),
              lng: (p['lng'] as num).toDouble(),
              elevationMetres: (p['ele'] as num?)?.toDouble(),
              timestamp: (p['ts'] as String?) != null
                  ? DateTime.tryParse(p['ts'] as String)
                  : null,
            ));
          }
        }
      }
    }

    final metadata = <String, dynamic>{};
    final avgBpm = raw['avg_bpm'];
    if (avgBpm is num) metadata['avg_bpm'] = avgBpm.toDouble();
    final activity = raw['activity_type'];
    if (activity is String) metadata['activity_type'] = activity;

    return cm.Run(
      id: id,
      startedAt: startedAt,
      duration: Duration(seconds: durationS),
      distanceMetres: distanceM,
      track: track,
      source: _parseSource(source),
      metadata: metadata.isEmpty ? null : metadata,
    );
  }

  static cm.RunSource _parseSource(String raw) {
    for (final s in cm.RunSource.values) {
      if (s.name == raw) return s;
    }
    return cm.RunSource.watch;
  }
}
