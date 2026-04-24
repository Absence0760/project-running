import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

import 'local_route_store.dart';
import 'local_run_store.dart';
import 'preferences.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sign_in_screen.dart';
import 'settings_sync.dart';
import 'watch_ingest_queue.dart';

/// Compile-time Supabase config. Secrets are passed to `flutter run` via
/// `apps/mobile_ios/dart_defines.json` (gitignored) because inline
/// `--dart-define=` flags break on Supabase's `sb_publishable_...` anon
/// keys — see `docs/decisions.md § 13`.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _devEmail = String.fromEnvironment('DEV_USER_EMAIL');
const _devPassword = String.fromEnvironment('DEV_USER_PASSWORD');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = Preferences();
  await preferences.init();

  final runStore = LocalRunStore();
  await runStore.init();

  // Crash recovery: if a previous session left an in-progress run, load it
  // so the run screen can surface a recovery prompt when it is wired to
  // LocalRunStore.
  final inProgress = await runStore.loadInProgress();
  if (inProgress != null) {
    debugPrint('Recovered in-progress run: ${inProgress.id}');
  }

  final routeStore = LocalRouteStore();
  await routeStore.init();

  final watchQueue = WatchIngestQueue();
  await watchQueue.init();

  final settingsSync = SettingsSyncService(preferences: preferences);

  ApiClient? api;
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    try {
      await ApiClient.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
      api = ApiClient();
      if (_devEmail.isNotEmpty && _devPassword.isNotEmpty) {
        try {
          await api.signIn(email: _devEmail, password: _devPassword);
        } catch (e) {
          debugPrint('Auto sign-in failed: $e');
        }
      }
      if (api.userId != null) {
        // Best-effort cloud-settings pull; offline launches just keep the
        // local prefs as the source of truth.
        try {
          await settingsSync.onSignedIn();
        } catch (e) {
          debugPrint('Settings sync on startup failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Supabase init failed: $e');
    }
  }

  // Wire up the Apple Watch → iPhone → Supabase ingest path. When the user
  // is authenticated, saves directly. When unauthenticated, queues the
  // payload to disk so it survives an app restart and is replayed on
  // the next sign-in event.
  if (api != null) {
    final isSignedIn = api.userId != null;
    if (isSignedIn) {
      WatchIngest.attach(api, watchQueue);
    }

    // Re-attach WatchIngest and drain the queue whenever auth state becomes
    // signed-in. This covers: (a) sign-in from SignInScreen, (b) session
    // restored from storage on a cold launch where the user was already
    // signed in. The subscription is held for the lifetime of the app.
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn) {
        WatchIngest.attach(api!, watchQueue);
        try {
          watchQueue.drain(api).catchError((e) {
            debugPrint('Watch ingest queue drain failed: $e');
          });
        } catch (e) {
          debugPrint('Watch ingest queue drain error: $e');
        }
        settingsSync.onSignedIn().catchError((e) {
          debugPrint('Settings sync on signedIn failed: $e');
        });
      }
    });
  }

  runApp(RunApp(
    apiClient: api,
    preferences: preferences,
    runStore: runStore,
    routeStore: routeStore,
    watchQueue: watchQueue,
    settingsSync: settingsSync,
  ));
}

class RunApp extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final WatchIngestQueue watchQueue;
  final SettingsSyncService? settingsSync;

  const RunApp({
    super.key,
    this.apiClient,
    required this.preferences,
    required this.runStore,
    required this.routeStore,
    required this.watchQueue,
    this.settingsSync,
  });

  @override
  State<RunApp> createState() => _RunAppState();
}

class _RunAppState extends State<RunApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Run',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _resolveHome(),
    );
  }

  Widget _resolveHome() {
    final api = widget.apiClient;

    // No Supabase configured — go straight to the app (offline-only mode).
    if (api == null) {
      return _onboardingOrHome();
    }

    final isSignedIn = api.userId != null;
    if (!isSignedIn) {
      return SignInScreen(
        apiClient: api,
        onSignedIn: () => setState(() {}),
      );
    }

    return _onboardingOrHome();
  }

  Widget _onboardingOrHome() {
    if (!widget.preferences.onboarded) {
      return OnboardingScreen(
        preferences: widget.preferences,
        onDone: () => setState(() {}),
      );
    }
    return HomeScreen(
      preferences: widget.preferences,
      runStore: widget.runStore,
      routeStore: widget.routeStore,
      apiClient: widget.apiClient,
      settingsSync: widget.settingsSync,
    );
  }
}

/// Receives runs from the paired Apple Watch via a method channel owned
/// by `Runner/AppDelegate.swift` + `Runner/WatchIngestBridge.swift`.
/// Each call carries: `{id, started_at, duration_s, distance_m, source,
/// avg_bpm?, track: [{lat, lng, ele?, ts?}]}`. We construct a
/// `core_models.Run` and upload via `ApiClient.saveRun` — same path
/// any other recording source uses, so web + Android see it identically.
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
        // User is not signed in — persist to disk for later replay.
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
        // Return false so WatchIngestBridge re-queues on its side too,
        // ensuring the run is not lost if the app process restarts before
        // our queue file is written.
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
    final source = raw['source'] as String? ?? 'app';
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
      // Swift side passed the raw JSON file contents — decode here.
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
    return cm.RunSource.app;
  }
}
