import 'package:core_models/core_models.dart' as cm;
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
import 'sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');

  final store = LocalRunStore();
  await store.init();

  // Recover a run that was in progress when the app was last killed
  // (crash, force-stop, OOM). We promote the partial data to a regular
  // completed run so at least the user keeps whatever was captured. Only
  // runs with meaningful content are kept — tiny "I tapped start then
  // backgrounded" runs are dropped silently.
  cm.Run? recoveredRun;
  try {
    final partial = await store.loadInProgress();
    if (partial != null &&
        partial.track.length >= 3 &&
        partial.distanceMetres >= 50) {
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

  final syncService = SyncService(apiClient: api, runStore: store);
  syncService.start();

  runApp(RunApp(
    apiClient: api,
    runStore: store,
    routeStore: routeStore,
    preferences: prefs,
    audioCues: audioCues,
    syncService: syncService,
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
  final cm.Run? recoveredRun;
  const RunApp({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
    required this.syncService,
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
          title: 'Run',
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
