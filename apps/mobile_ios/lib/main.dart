import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import 'preferences.dart';
import 'screens/home_screen.dart';

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
    } catch (e) {
      debugPrint('Supabase init failed: $e');
    }
  }

  // Wire up the Apple Watch → iPhone → Supabase ingest path. The Swift
  // side of the Runner project owns a `WCSessionDelegate`; when a file
  // lands it decodes the gzipped track, combines it with the metadata
  // dict the watch attached, and forwards to Dart via a method channel.
  // Here we subscribe and write each incoming run via `ApiClient.saveRun`.
  if (api != null) {
    WatchIngest.attach(api);
  }

  runApp(RunApp(apiClient: api, preferences: preferences));
}

class RunApp extends StatelessWidget {
  final ApiClient? apiClient;
  final Preferences preferences;

  const RunApp({super.key, this.apiClient, required this.preferences});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Run',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: HomeScreen(preferences: preferences),
    );
  }
}

/// Receives runs from the paired Apple Watch via a method channel owned
/// by `Runner/AppDelegate.swift` + `Runner/WatchIngestBridge.swift`.
/// Each call carries: `{id, started_at, duration_s, distance_m, source,
/// avg_bpm?, track: [{lat, lng, ele?, ts?}]}`. We construct a
/// `core_models.Run` and upload via `ApiClient.saveRun` — same path
/// any other recording source uses, so web + Android see it identically.
class WatchIngest {
  static const _channel = MethodChannel('run_app/watch_ingest');

  static void attach(ApiClient api) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'run') return null;
      final args = call.arguments as Map<Object?, Object?>?;
      if (args == null) return false;
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
