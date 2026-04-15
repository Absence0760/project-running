import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import 'local_run_store.dart';
import 'run_watch_screen.dart';

/// Point the watch at a different Supabase by passing
/// `--dart-define SUPABASE_URL=... --dart-define SUPABASE_ANON_KEY=...`
/// to `flutter run` / `flutter build`. Defaults match the local stack
/// so `flutter run` on a dev machine Just Works.
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  final store = LocalRunStore();
  await store.load();
  runApp(WearRunApp(apiClient: ApiClient(), runStore: store));
}

class WearRunApp extends StatelessWidget {
  final ApiClient apiClient;
  final LocalRunStore runStore;

  const WearRunApp({
    super.key,
    required this.apiClient,
    required this.runStore,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Run',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: RunWatchScreen(apiClient: apiClient, runStore: runStore),
    );
  }
}
