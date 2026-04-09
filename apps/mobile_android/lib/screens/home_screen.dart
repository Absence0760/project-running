import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';

import '../local_run_store.dart';
import 'run_screen.dart';
import 'history_screen.dart';
import 'routes_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;
  final LocalRunStore runStore;
  const HomeScreen({super.key, required this.apiClient, required this.runStore});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    RunScreen(apiClient: widget.apiClient, runStore: widget.runStore),
    HistoryScreen(apiClient: widget.apiClient, runStore: widget.runStore),
    const RoutesScreen(),
    const SettingsScreen(),
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
          NavigationDestination(icon: Icon(Icons.play_arrow), label: 'Run'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
