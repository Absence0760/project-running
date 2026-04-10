import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';

import '../audio_cues.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'routes_screen.dart';
import 'run_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final AudioCues audioCues;

  const HomeScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    DashboardScreen(
      runStore: widget.runStore,
      preferences: widget.preferences,
    ),
    RunScreen(
      apiClient: widget.apiClient,
      runStore: widget.runStore,
      routeStore: widget.routeStore,
      preferences: widget.preferences,
      audioCues: widget.audioCues,
    ),
    HistoryScreen(
      apiClient: widget.apiClient,
      runStore: widget.runStore,
      preferences: widget.preferences,
    ),
    RoutesScreen(
      apiClient: widget.apiClient,
      routeStore: widget.routeStore,
      preferences: widget.preferences,
    ),
    SettingsScreen(
      apiClient: widget.apiClient,
      preferences: widget.preferences,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.play_arrow), label: 'Run'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
