import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup.dart';
import '../backup_server_client.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../widgets/top_banner.dart';
import 'import_screen.dart';
import 'guided_runs_screen.dart';
import 'privacy_zones_screen.dart';
import 'trusted_contacts_screen.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';

class SettingsAccountScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore? runStore;
  final LocalRouteStore? routeStore;
  final SettingsSyncService? settingsSync;

  const SettingsAccountScreen({
    super.key,
    required this.apiClient,
    required this.preferences,
    required this.settingsSync,
    this.runStore,
    this.routeStore,
  });

  @override
  State<SettingsAccountScreen> createState() => _SettingsAccountScreenState();
}

class _SettingsAccountScreenState extends State<SettingsAccountScreen> {
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
      showTopBanner(context, 'Backend not configured');
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
    try {
      await api.signOut();
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'Sign out failed — check your connection');
        return;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _changePassword() async {
    final pwdCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setInner) => AlertDialog(
            title: const Text('Change password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pwdCtl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (pwdCtl.text.length < 8) {
                    setInner(
                        () => error = 'Password must be at least 8 characters');
                    return;
                  }
                  if (pwdCtl.text != confirmCtl.text) {
                    setInner(() => error = 'Passwords do not match');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    if (!mounted) return;
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: pwdCtl.text));
      if (!mounted) return;
      showTopBanner(context, 'Password updated');
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Could not update password: $e');
    }
  }

  Future<void> _deleteAccount() async {
    // Re-entry challenge mirroring the web ConfirmDialog `requireText`
    // gate: the user must type their email (or "DELETE" when offline /
    // no email) before the Delete button enables. Apple 5.1.1 +
    // data-loss confirmation — a stray tap can't trigger an
    // irreversible server-side wipe.
    final email = widget.apiClient?.userEmail ?? '';
    final challengeTarget = email.isEmpty ? 'DELETE' : email;
    final challengeCtl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final met = challengeCtl.text.trim().toLowerCase() ==
              challengeTarget.trim().toLowerCase();
          return AlertDialog(
            title: const Text('Delete account?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently removes your runs, routes, and profile '
                  'from the server. Local device data is kept unless you sign '
                  'in as a new user. This cannot be undone.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: challengeCtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: email.isEmpty
                        ? 'Type "DELETE" to confirm'
                        : 'Type your email ($email) to confirm',
                  ),
                  onChanged: (_) => setInner(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: met ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Delete'),
              ),
            ],
          );
        },
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    try {
      final api = widget.apiClient;
      if (api == null) {
        showTopBanner(context, 'Sign in first to delete your account.');
        return;
      }
      await api.deleteAccount();
      await api.signOut();
      if (mounted) {
        showTopBanner(context, 'Account deleted');
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Account deletion failed: $e');
    }
  }

  Future<void> _exportRunsCsv() async {
    final store = widget.runStore;
    final runs = store?.runs ?? const [];
    if (runs.isEmpty) {
      showTopBanner(context, 'No runs to export.');
      return;
    }
    try {
      final buf =
          StringBuffer('date,distance_m,duration_s,pace_s_per_km,source\n');
      for (final r in runs) {
        final pace = r.distanceMetres > 0
            ? (r.duration.inSeconds / (r.distanceMetres / 1000)).round()
            : 0;
        buf.writeln(
          '${r.startedAt.toUtc().toIso8601String()},'
          '${r.distanceMetres.round()},'
          '${r.duration.inSeconds},'
          '$pace,'
          '${r.source.name}',
        );
      }
      final tmp = await getTemporaryDirectory();
      final ts =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${tmp.path}/runs-$ts.csv');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        text: 'Run app — runs export',
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'CSV export failed: $e');
    }
  }

  Future<void> _exportBackup() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(context, 'Sign in first to back up your runs.');
      return;
    }
    showTopBanner(context, 'Preparing backup…');
    try {
      final tmp = await getTemporaryDirectory();
      final ts =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${tmp.path}/run-app-backup-$ts.zip');
      final serviceBase = dotenv.env['LIVE_HUB_URL']?.trim() ?? '';
      await BackupService(
        api: api,
        serverClient: serviceBase.isEmpty
            ? null
            : BackupServerClient(baseUrl: serviceBase),
      ).createBackup(outputFile: file);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Run app backup',
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Backup failed: $e');
    }
  }

  Future<void> _restoreBackup() async {
    final api = widget.apiClient;
    final store = widget.runStore;
    if (store == null) {
      showTopBanner(context, 'Backup service unavailable.');
      return;
    }
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    final offline = api == null || api.userId == null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: Text(
          offline
              ? 'You\'re not signed in. Runs will be restored to this device '
                  'and synced to your account the next time you sign in.'
              : 'This adds or overwrites runs and routes matching IDs in the '
                  'backup. It will not delete runs or routes that aren\'t in '
                  'the backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    showTopBanner(context, 'Restoring…');
    try {
      final res = await BackupService(api: api).restore(
        zipFile: File(path),
        runStore: store,
        routeStore: widget.routeStore,
      );
      if (!mounted) return;
      showTopBanner(
        context,
        'Restored ${res.runsImported} runs · ${res.tracksUploaded} tracks · ${res.routesImported} routes'
        '${res.warnings.isNotEmpty ? ' · ${res.warnings.length} warnings' : ''}',
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = widget.apiClient?.userId != null;
    final email = widget.apiClient?.userEmail ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: signedIn
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  email.isNotEmpty ? email[0].toUpperCase() : '?',
                ),
              ),
              title: Text(email.isEmpty ? 'Offline mode' : email),
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
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('View profile'),
                subtitle: const Text(
                    'Your runs, followers, following, notifications'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final api = widget.apiClient;
                  final uid = api?.userId;
                  if (api == null || uid == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(api: api, userId: uid),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.headset),
              title: const Text('Guided runs'),
              subtitle: const Text(
                  'Coach-voice scripted workouts with TTS cues'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GuidedRunsScreen(),
                  ),
                );
              },
            ),
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy zones'),
                subtitle: const Text(
                    'Clip start/end of public tracks near home'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final s = widget.settingsSync;
                  if (s == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrivacyZonesScreen(settingsSync: s),
                    ),
                  );
                },
              ),
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.contact_emergency_outlined),
                title: const Text('Trusted contacts'),
                subtitle: const Text(
                    'Designated people for the planned overdue-run / panic surface'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final s = widget.settingsSync;
                  if (s == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TrustedContactsScreen(settingsSync: s),
                    ),
                  );
                },
              ),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Text('Send error reports'),
              subtitle: const Text(
                'Anonymised crash + error data to Sentry (US). Toggle off to withdraw consent. Applies on next launch.',
              ),
              value: !widget.preferences.sentryOptOut,
              onChanged: (enabled) async {
                await widget.preferences.setSentryOptOut(!enabled);
                if (!mounted) return;
                showTopBanner(
                  context,
                  enabled
                      ? 'Error reporting enabled — restart the app to apply.'
                      : 'Error reporting disabled — restart the app to apply.',
                );
              },
            ),
            if (widget.runStore != null) ...[
              const Divider(),
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
                        routeStore: widget.routeStore,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Full backup'),
                subtitle: const Text(
                  'Every run with its GPS trace, plus routes, profile, and preferences. '
                  'Restores on web or Android.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _exportBackup,
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Export runs as CSV'),
                subtitle: const Text(
                  'date, distance, duration, pace, source — one row per run. '
                  'Same shape as the web GDPR export.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _exportRunsCsv,
              ),
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Restore from backup'),
                subtitle: const Text('Pick a previously saved .zip backup.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _restoreBackup,
              ),
            ],
            if (signedIn) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePassword,
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete account',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: const Text('Permanently removes server data'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _deleteAccount,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
