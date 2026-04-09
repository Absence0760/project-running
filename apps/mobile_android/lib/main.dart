import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:api_client/api_client.dart';
import 'package:ui_kit/ui_kit.dart';

import 'local_run_store.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');

  await ApiClient.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  final store = LocalRunStore();
  await store.init();

  // Auto sign-in with dev credentials from .env.local
  final api = ApiClient();
  final devEmail = dotenv.env['DEV_USER_EMAIL'];
  final devPassword = dotenv.env['DEV_USER_PASSWORD'];
  if (devEmail != null && devPassword != null) {
    try {
      await api.signIn(email: devEmail, password: devPassword);
    } catch (e) {
      debugPrint('Auto sign-in failed: $e');
    }
  }

  runApp(RunApp(apiClient: api, runStore: store));
}

class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark);
}

final themeModeNotifier = ThemeModeNotifier();

class RunApp extends StatelessWidget {
  final ApiClient apiClient;
  final LocalRunStore runStore;
  const RunApp({super.key, required this.apiClient, required this.runStore});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Run',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: HomeScreen(apiClient: apiClient, runStore: runStore),
        );
      },
    );
  }
}
