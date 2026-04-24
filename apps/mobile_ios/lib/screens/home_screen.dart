import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import 'run_screen.dart';
import 'runs_screen.dart';
import 'routes_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Preferences preferences;
  final LocalRunStore? runStore;
  final LocalRouteStore? routeStore;
  final ApiClient? apiClient;
  final SettingsSyncService? settingsSync;

  const HomeScreen({
    super.key,
    required this.preferences,
    this.runStore,
    this.routeStore,
    this.apiClient,
    this.settingsSync,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final runStore = widget.runStore;
    final prefs = widget.preferences;

    final screens = [
      runStore != null
          ? RunScreen(runStore: runStore, preferences: prefs)
          : const _OfflineRunPlaceholder(),
      const RunsScreen(),
      const RoutesScreen(),
      SettingsScreen(
        preferences: prefs,
        apiClient: widget.apiClient,
        settingsSync: widget.settingsSync,
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.play_arrow), label: 'Run'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Runs'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _OfflineRunPlaceholder extends StatelessWidget {
  const _OfflineRunPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Run recording not available in offline mode.'),
      ),
    );
  }
}
