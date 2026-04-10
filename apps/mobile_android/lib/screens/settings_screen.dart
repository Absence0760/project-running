import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../local_run_store.dart';
import '../main.dart' show themeModeNotifier;
import '../preferences.dart';
import 'import_screen.dart';
import 'sign_in_screen.dart';

/// Account settings, preferences, and integrations.
class SettingsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore? runStore;

  const SettingsScreen({
    super.key,
    this.apiClient,
    required this.preferences,
    this.runStore,
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

  Future<void> _editTargetPace() async {
    final prefs = widget.preferences;
    final current = prefs.targetPaceSecPerKm;
    int minutes = current > 0 ? current ~/ 60 : 5;
    int seconds = current > 0 ? current % 60 : 30;

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        final mCtl = TextEditingController(text: '$minutes');
        final sCtl = TextEditingController(text: '$seconds');
        return AlertDialog(
          title: const Text('Target pace per km'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 60,
                child: TextField(
                  controller: mCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'min'),
                  textAlign: TextAlign.center,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':', style: TextStyle(fontSize: 20)),
              ),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: sCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'sec'),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final m = int.tryParse(mCtl.text) ?? 0;
                final s = int.tryParse(sCtl.text) ?? 0;
                Navigator.pop(ctx, m * 60 + s);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result != null) await prefs.setTargetPaceSecPerKm(result);
  }

  Future<void> _exportBackup() async {
    final store = widget.runStore;
    if (store == null) return;
    final runs = store.runs;
    final json = jsonEncode({
      'exported_at': DateTime.now().toIso8601String(),
      'count': runs.length,
      'runs': runs.map((r) => r.toJson()).toList(),
    });
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/runs-backup-${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Run backup — ${runs.length} runs',
    );
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
          ListTile(
            title: const Text('Target pace'),
            subtitle: Text(
              prefs.targetPaceSecPerKm > 0
                  ? '${UnitFormat.pace(prefs.targetPaceSecPerKm.toDouble(), prefs.unit)} '
                      '${UnitFormat.paceLabel(prefs.unit)} '
                      '— alerts when 30s+ off'
                  : 'Not set',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editTargetPace,
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

          // Data
          if (widget.runStore != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Data', style: theme.textTheme.titleSmall),
            ),
            ListTile(
              leading: const Icon(Icons.move_to_inbox),
              title: const Text('Import from another app'),
              subtitle: const Text('Strava, GPX, TCX'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImportScreen(
                      apiClient: widget.apiClient,
                      runStore: widget.runStore!,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Backup runs'),
              subtitle: Text('${widget.runStore!.runs.length} runs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportBackup,
            ),
            const Divider(),
          ],

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
