import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../main.dart' show themeModeNotifier;
import '../preferences.dart';
import 'sign_in_screen.dart';

/// Account settings, preferences, and integrations.
class SettingsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;

  const SettingsScreen({
    super.key,
    this.apiClient,
    required this.preferences,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = themeModeNotifier.value == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    final api = widget.apiClient;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backend not configured')),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(apiClient: api)),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _signOut() async {
    final api = widget.apiClient;
    if (api == null) return;
    await api.signOut();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = widget.preferences;
    final signedIn = widget.apiClient?.userId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Account
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Account', style: theme.textTheme.titleSmall),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: signedIn
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Text(
                widget.apiClient?.userEmail != null
                    ? widget.apiClient!.userEmail![0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(widget.apiClient?.userEmail ?? 'Offline mode'),
            subtitle: Text(signedIn
                ? 'Signed in — runs will sync'
                : 'Sign in to sync runs across devices'),
            trailing: signedIn
                ? IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: _signOut,
                  )
                : FilledButton.tonal(
                    onPressed: _signIn,
                    child: const Text('Sign in'),
                  ),
          ),
          const Divider(),

          // Preferences
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Preferences', style: theme.textTheme.titleSmall),
          ),
          SwitchListTile(
            title: const Text('Use miles'),
            subtitle: Text(prefs.useMiles ? 'mi, ft' : 'km, m'),
            value: prefs.useMiles,
            onChanged: prefs.setUseMiles,
          ),
          SwitchListTile(
            title: const Text('Audio cues'),
            subtitle: const Text('Spoken split announcements'),
            value: prefs.audioCues,
            onChanged: prefs.setAudioCues,
          ),
          SwitchListTile(
            title: const Text('Auto-pause'),
            subtitle: const Text('Pause timer when not moving'),
            value: prefs.autoPause,
            onChanged: prefs.setAutoPause,
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

          // Integrations
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

          // About
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
