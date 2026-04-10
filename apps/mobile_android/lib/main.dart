import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:api_client/api_client.dart';
import 'package:ui_kit/ui_kit.dart';

import 'audio_cues.dart';
import 'local_route_store.dart';
import 'local_run_store.dart';
import 'preferences.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');

  final store = LocalRunStore();
  await store.init();

  final routeStore = LocalRouteStore();
  await routeStore.init();

  final prefs = Preferences();
  await prefs.init();

  final audioCues = AudioCues();

  // Try to initialize Supabase — skip if not configured or unreachable
  ApiClient? api;
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl != null && supabaseUrl.isNotEmpty &&
      anonKey != null && anonKey.isNotEmpty) {
    try {
      await ApiClient.initialize(url: supabaseUrl, anonKey: anonKey);
      api = ApiClient();

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
    } catch (e) {
      debugPrint('Supabase init failed, running offline: $e');
      api = null;
    }
  }

  runApp(RunApp(
    apiClient: api,
    runStore: store,
    routeStore: routeStore,
    preferences: prefs,
    audioCues: audioCues,
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
  const RunApp({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
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
          title: 'Run',
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
