import 'package:flutter/material.dart';

import '../preferences.dart';
import 'run_screen.dart';
import 'runs_screen.dart';
import 'routes_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Preferences preferences;

  const HomeScreen({super.key, required this.preferences});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const RunScreen(),
      const RunsScreen(),
      const RoutesScreen(),
      SettingsScreen(preferences: widget.preferences),
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
