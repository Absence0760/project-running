import 'package:flutter/material.dart';

/// Account settings and integrations management.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          // TODO: Add auth section, integrations, preferences
          ListTile(title: Text('Account'), subtitle: Text('Sign in')),
          ListTile(title: Text('Units'), subtitle: Text('Kilometres')),
          ListTile(title: Text('Integrations'), subtitle: Text('Strava, parkrun')),
        ],
      ),
    );
  }
}
