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
import '../l10n/gen/app_localizations.dart';
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
      showTopBanner(
          context, AppLocalizations.of(context).settingsAccountBackendNotConfigured);
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
        showTopBanner(
            context, AppLocalizations.of(context).settingsAccountSignOutFailed);
        return;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _changePassword() async {
    final l10n = AppLocalizations.of(context);
    final pwdCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setInner) => AlertDialog(
            title: Text(l10n.settingsAccountChangePassword),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pwdCtl,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: l10n.settingsAccountNewPassword),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtl,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: l10n.settingsAccountConfirm),
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
                child: Text(l10n.settingsAccountCancel),
              ),
              FilledButton(
                onPressed: () {
                  if (pwdCtl.text.length < 8) {
                    setInner(() =>
                        error = l10n.settingsAccountPasswordTooShort);
                    return;
                  }
                  if (pwdCtl.text != confirmCtl.text) {
                    setInner(
                        () => error = l10n.settingsAccountPasswordsMismatch);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(l10n.settingsAccountSave),
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
      showTopBanner(context, l10n.settingsAccountPasswordUpdated);
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountPasswordUpdateFailed(e));
    }
  }

  Future<void> _deleteAccount() async {
    // Re-entry challenge mirroring the web ConfirmDialog `requireText`
    // gate: the user must type their email (or "DELETE" when offline /
    // no email) before the Delete button enables. Apple 5.1.1 +
    // data-loss confirmation — a stray tap can't trigger an
    // irreversible server-side wipe.
    final l10n = AppLocalizations.of(context);
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
            title: Text(l10n.settingsAccountDeleteTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsAccountDeleteBody),
                const SizedBox(height: 16),
                TextField(
                  controller: challengeCtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: email.isEmpty
                        ? l10n.settingsAccountDeleteChallengeText
                        : l10n.settingsAccountDeleteChallengeEmail(email),
                  ),
                  onChanged: (_) => setInner(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.settingsAccountCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: met ? () => Navigator.pop(ctx, true) : null,
                child: Text(l10n.settingsAccountDelete),
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
        showTopBanner(context, l10n.settingsAccountDeleteSignInFirst);
        return;
      }
      await api.deleteAccount();
      await api.signOut();
      if (mounted) {
        showTopBanner(context, l10n.settingsAccountDeleted);
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountDeleteFailed(e));
    }
  }

  Future<void> _exportRunsCsv() async {
    final l10n = AppLocalizations.of(context);
    final store = widget.runStore;
    final runs = store?.runs ?? const [];
    if (runs.isEmpty) {
      showTopBanner(context, l10n.settingsAccountNoRunsToExport);
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
        text: l10n.settingsAccountCsvShareText,
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountCsvExportFailed(e));
    }
  }

  Future<void> _exportBackup() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(context, l10n.settingsAccountBackupSignInFirst);
      return;
    }
    showTopBanner(context, l10n.settingsAccountBackupPreparing);
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
        text: l10n.settingsAccountBackupShareText,
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountBackupFailed(e));
    }
  }

  Future<void> _restoreBackup() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    final store = widget.runStore;
    if (store == null) {
      showTopBanner(context, l10n.settingsAccountRestoreUnavailable);
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
        title: Text(l10n.settingsAccountRestoreTitle),
        content: Text(
          offline
              ? l10n.settingsAccountRestoreBodyOffline
              : l10n.settingsAccountRestoreBodyOnline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.settingsAccountCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.settingsAccountRestore),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    showTopBanner(context, l10n.settingsAccountRestoring);
    try {
      final res = await BackupService(api: api).restore(
        zipFile: File(path),
        runStore: store,
        routeStore: widget.routeStore,
      );
      if (!mounted) return;
      showTopBanner(
        context,
        l10n.settingsAccountRestoreDone(
          res.runsImported,
          res.tracksUploaded,
          res.routesImported,
          res.warnings.isNotEmpty
              ? l10n.settingsAccountRestoreWarningsSuffix(res.warnings.length)
              : '',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountRestoreFailed(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final signedIn = widget.apiClient?.userId != null;
    final email = widget.apiClient?.userEmail ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccountTitle)),
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
              title: Text(
                  email.isEmpty ? l10n.settingsAccountOfflineMode : email),
              subtitle: Text(signedIn
                  ? l10n.settingsAccountSignedInSync
                  : l10n.settingsAccountSignInToSync),
              trailing: signedIn
                  ? IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: l10n.settingsAccountSignOut,
                      onPressed: _signOut,
                    )
                  : FilledButton.tonal(
                      onPressed: _signIn,
                      child: Text(l10n.settingsAccountSignIn),
                    ),
            ),
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(l10n.settingsAccountViewProfile),
                subtitle: Text(l10n.settingsAccountViewProfileSubtitle),
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
              title: Text(l10n.settingsAccountGuidedRuns),
              subtitle: Text(l10n.settingsAccountGuidedRunsSubtitle),
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
                title: Text(l10n.settingsAccountPrivacyZones),
                subtitle: Text(l10n.settingsAccountPrivacyZonesSubtitle),
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
                title: Text(l10n.settingsAccountTrustedContacts),
                subtitle: Text(l10n.settingsAccountTrustedContactsSubtitle),
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
              title: Text(l10n.settingsAccountSendErrorReports),
              subtitle: Text(l10n.settingsAccountSendErrorReportsSubtitle),
              value: !widget.preferences.sentryOptOut,
              onChanged: (enabled) async {
                await widget.preferences.setSentryOptOut(!enabled);
                if (!mounted) return;
                showTopBanner(
                  context,
                  enabled
                      ? l10n.settingsAccountErrorReportingEnabled
                      : l10n.settingsAccountErrorReportingDisabled,
                );
              },
            ),
            if (widget.runStore != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.move_to_inbox),
                title: Text(l10n.settingsAccountImport),
                subtitle: Text(l10n.settingsAccountImportSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImportScreen(
                        apiClient: widget.apiClient,
                        runStore: widget.runStore!,
                        routeStore: widget.routeStore,
                        preferences: widget.preferences,
                        settingsSync: widget.settingsSync,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(l10n.settingsAccountFullBackup),
                subtitle: Text(l10n.settingsAccountFullBackupSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _exportBackup,
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(l10n.settingsAccountExportCsv),
                subtitle: Text(l10n.settingsAccountExportCsvSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _exportRunsCsv,
              ),
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: Text(l10n.settingsAccountRestoreTile),
                subtitle: Text(l10n.settingsAccountRestoreTileSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _restoreBackup,
              ),
            ],
            if (signedIn) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.settingsAccountChangePassword),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePassword,
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  l10n.settingsAccountDeleteAccount,
                  style: const TextStyle(color: Colors.red),
                ),
                subtitle: Text(l10n.settingsAccountDeleteAccountSubtitle),
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
