import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;

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
  int _currentIndex = 1;
  cm.Route? _preselectedRoute;

  void _startRunWithRoute(cm.Route route) {
    setState(() {
      _preselectedRoute = route;
      _currentIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        key: const PageStorageKey('dashboard'),
        runStore: widget.runStore,
        preferences: widget.preferences,
      ),
      RunScreen(
        key: const PageStorageKey('run'),
        apiClient: widget.apiClient,
        runStore: widget.runStore,
        routeStore: widget.routeStore,
        preferences: widget.preferences,
        audioCues: widget.audioCues,
        initialRoute: _preselectedRoute,
      ),
      HistoryScreen(
        key: const PageStorageKey('history'),
        apiClient: widget.apiClient,
        runStore: widget.runStore,
        preferences: widget.preferences,
      ),
      RoutesScreen(
        key: const PageStorageKey('routes'),
        apiClient: widget.apiClient,
        routeStore: widget.routeStore,
        preferences: widget.preferences,
        onStartRun: _startRunWithRoute,
      ),
      SettingsScreen(
        key: const PageStorageKey('settings'),
        apiClient: widget.apiClient,
        preferences: widget.preferences,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
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
