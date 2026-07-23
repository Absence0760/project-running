import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';

/// The result of an update check, decoupled from the `in_app_update` plugin
/// enums so the screen (and its tests) don't depend on the platform channel.
enum LicenseUpdateStatus { checking, available, upToDate, unavailable }

/// Default update check — Google Play In-App Updates (Android only). A
/// non-Play build (dev, sideload, iOS) has no update channel, so it reports
/// [LicenseUpdateStatus.unavailable] and the screen simply hides the update
/// row rather than surfacing an error. L4: any plugin error fails closed to
/// `unavailable`, never a crash on the Licenses screen.
Future<LicenseUpdateStatus> defaultCheckUpdate() async {
  if (!Platform.isAndroid) return LicenseUpdateStatus.unavailable;
  try {
    final info = await InAppUpdate.checkForUpdate();
    return info.updateAvailability == UpdateAvailability.updateAvailable
        ? LicenseUpdateStatus.available
        : LicenseUpdateStatus.upToDate;
  } catch (_) {
    return LicenseUpdateStatus.unavailable;
  }
}

/// Default update trigger — Play's immediate in-app update flow. On success
/// Play downloads + installs + restarts the app; a failure/decline throws and
/// the caller surfaces a banner.
Future<void> defaultPerformUpdate() async {
  await InAppUpdate.performImmediateUpdate();
}

class SettingsLicensesScreen extends StatefulWidget {
  /// Test seams for the update path — production uses the top-level defaults.
  final Future<LicenseUpdateStatus> Function()? checkUpdate;
  final Future<void> Function()? performUpdate;

  const SettingsLicensesScreen({
    super.key,
    this.checkUpdate,
    this.performUpdate,
  });

  @override
  State<SettingsLicensesScreen> createState() =>
      _SettingsLicensesScreenState();
}

class _SettingsLicensesScreenState extends State<SettingsLicensesScreen> {
  late final Future<String> _version = _loadVersion();
  LicenseUpdateStatus _status = LicenseUpdateStatus.checking;
  bool _updating = false;

  Future<String> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version} (${info.buildNumber})';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final check = widget.checkUpdate ?? defaultCheckUpdate;
    final status = await check();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _update() async {
    if (_updating) return;
    final perform = widget.performUpdate ?? defaultPerformUpdate;
    final check = widget.checkUpdate ?? defaultCheckUpdate;
    setState(() => _updating = true);
    try {
      await perform();
      // The immediate flow restarts the app on success; if control returns
      // (a declined / no-op update), re-check so the row reflects reality.
      final status = await check();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).licensesUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.licensesTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.licensesVersion),
              subtitle: FutureBuilder<String>(
                future: _version,
                builder: (context, snapshot) => Text(snapshot.data ?? ''),
              ),
            ),
            if (_status == LicenseUpdateStatus.checking)
              ListTile(
                key: const Key('update-checking'),
                leading: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                title: Text(l10n.licensesCheckingUpdate),
              )
            else if (_status == LicenseUpdateStatus.available)
              ListTile(
                key: const Key('update-available'),
                leading:
                    Icon(Icons.system_update, color: theme.colorScheme.primary),
                title: Text(l10n.licensesUpdateAvailable),
                subtitle: Text(l10n.licensesUpdateAvailableSubtitle),
                trailing: _updating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: _update,
                        child: Text(l10n.licensesUpdate),
                      ),
              )
            else if (_status == LicenseUpdateStatus.upToDate)
              ListTile(
                key: const Key('update-uptodate'),
                leading: Icon(Icons.check_circle_outline,
                    color: theme.colorScheme.primary),
                title: Text(l10n.licensesUpToDate),
              ),
            // LicenseUpdateStatus.unavailable → no update row (dev / sideload /
            // iOS build has no Play update channel).
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(l10n.licensesOpenSource),
              subtitle: Text(l10n.licensesOpenSourceSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context),
            ),
          ],
        ),
      ),
    );
  }
}
