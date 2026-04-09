import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import '../main.dart' show themeModeNotifier;

/// Account settings and integrations management.
class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  const SettingsScreen({super.key, required this.apiClient});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useKilometres = true;
  bool _darkMode = themeModeNotifier.value == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Account section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Account', style: theme.textTheme.titleSmall),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                (widget.apiClient.userEmail ?? '?')[0].toUpperCase(),
              ),
            ),
            title: Text(widget.apiClient.userEmail ?? 'Not signed in'),
            subtitle: Text(widget.apiClient.userId != null ? 'Signed in' : 'No account'),
          ),
          const Divider(),

          // Preferences section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Preferences', style: theme.textTheme.titleSmall),
          ),
          SwitchListTile(
            title: const Text('Use kilometres'),
            subtitle: Text(_useKilometres ? 'km, m' : 'mi, ft'),
            value: _useKilometres,
            onChanged: (v) => setState(() => _useKilometres = v),
          ),
          SwitchListTile(
            title: const Text('Dark mode'),
            value: _darkMode,
            onChanged: (v) {
              setState(() => _darkMode = v);
              themeModeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
            },
          ),
          const Divider(),

          // Integrations section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Integrations', style: theme.textTheme.titleSmall),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Strava'),
            subtitle: const Text('Not connected'),
            trailing: FilledButton.tonal(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Strava connect coming soon')),
                );
              },
              child: const Text('Connect'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.directions_run),
            title: const Text('parkrun'),
            subtitle: const Text('Not connected'),
            trailing: FilledButton.tonal(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('parkrun connect coming soon')),
                );
              },
              child: const Text('Connect'),
            ),
          ),
          const Divider(),

          // About section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('About', style: theme.textTheme.titleSmall),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.1.0 (dev)'),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Licenses'),
            onTap: () => showLicensePage(context: context),
          ),
        ],
      ),
    );
  }
}
