import 'package:flutter/material.dart';

import '../preferences.dart';

/// Account settings and integrations management.
class SettingsScreen extends StatefulWidget {
  final Preferences preferences;

  const SettingsScreen({super.key, required this.preferences});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = widget.preferences;
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
              child: const Text('JH'),
            ),
            title: const Text('Jared Howard'),
            subtitle: const Text('jared@example.com'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),

          // Preferences section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Preferences', style: theme.textTheme.titleSmall),
          ),
          SwitchListTile(
            title: const Text('Use kilometres'),
            subtitle: Text(prefs.useMiles ? 'mi, ft' : 'km, m'),
            value: !prefs.useMiles,
            onChanged: (v) {
              prefs.setUseMiles(!v);
              setState(() {});
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
