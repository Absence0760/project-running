import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/gen/app_localizations.dart';
import '../legal_links.dart';
import '../widgets/top_banner.dart';

/// The result of an update check, decoupled from the `in_app_update` plugin
/// enums so the screen (and its tests) don't depend on the platform channel.
/// [idle] is the mount state — the check is user-initiated, so opening the
/// screen costs no Play round-trip.
enum AppUpdateStatus { idle, checking, available, upToDate, unavailable }

/// Default update check — Google Play In-App Updates (Android only). A
/// non-Play build (dev, sideload, iOS) has no update channel, so it reports
/// [AppUpdateStatus.unavailable] and the screen says so rather than
/// surfacing an error. L4: any plugin error fails closed to `unavailable`,
/// never a crash on the About screen.
Future<AppUpdateStatus> defaultCheckUpdate() async {
  if (!Platform.isAndroid) return AppUpdateStatus.unavailable;
  try {
    final info = await InAppUpdate.checkForUpdate();
    return info.updateAvailability == UpdateAvailability.updateAvailable
        ? AppUpdateStatus.available
        : AppUpdateStatus.upToDate;
  } catch (_) {
    return AppUpdateStatus.unavailable;
  }
}

/// Default update trigger — Play's immediate in-app update flow. On success
/// Play downloads + installs + restarts the app; a failure/decline throws and
/// the caller surfaces a banner.
Future<void> defaultPerformUpdate() async {
  await InAppUpdate.performImmediateUpdate();
}

/// Settings → About & updates: the installed version, the update path, and
/// the open-source licenses. Mirrors web's `/settings/licenses` plus the
/// version + update rows a web build has no need for.
class SettingsAboutScreen extends StatefulWidget {
  /// Test seams for the update path — production uses the top-level defaults.
  final Future<AppUpdateStatus> Function()? checkUpdate;
  final Future<void> Function()? performUpdate;

  const SettingsAboutScreen({
    super.key,
    this.checkUpdate,
    this.performUpdate,
  });

  @override
  State<SettingsAboutScreen> createState() => _SettingsAboutScreenState();
}

class _SettingsAboutScreenState extends State<SettingsAboutScreen> {
  late final Future<String> _version = _loadVersion();
  AppUpdateStatus _status = AppUpdateStatus.idle;
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

  Future<void> _checkForUpdate() async {
    if (_status == AppUpdateStatus.checking) return;
    setState(() => _status = AppUpdateStatus.checking);
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
        showTopBanner(context, AppLocalizations.of(context).aboutUpdateFailed);
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
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.aboutVersion),
              subtitle: FutureBuilder<String>(
                future: _version,
                builder: (context, snapshot) => Text(snapshot.data ?? ''),
              ),
            ),
            _updateRow(theme, l10n),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(l10n.licensesOpenSource),
              subtitle: Text(l10n.licensesOpenSourceSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                l10n.aboutLegalSection.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Same four documents web links from its settings nav footer.
            // Signed-in users had no route to any of them on mobile — the
            // only links lived on the pre-account sign-up screen.
            for (final doc in LegalDoc.values)
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: Text(legalDocLabel(l10n, doc)),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => openLegalDoc(context, doc),
              ),
          ],
        ),
      ),
    );
  }

  Widget _updateRow(ThemeData theme, AppLocalizations l10n) {
    switch (_status) {
      case AppUpdateStatus.idle:
        return ListTile(
          key: const Key('update-check'),
          leading: const Icon(Icons.system_update),
          title: Text(l10n.aboutCheckForUpdates),
          trailing: const Icon(Icons.chevron_right),
          onTap: _checkForUpdate,
        );
      case AppUpdateStatus.checking:
        return ListTile(
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
          title: Text(l10n.aboutCheckingUpdate),
        );
      case AppUpdateStatus.available:
        return ListTile(
          key: const Key('update-available'),
          leading: Icon(Icons.system_update, color: theme.colorScheme.primary),
          title: Text(l10n.aboutUpdateAvailable),
          subtitle: Text(l10n.aboutUpdateAvailableSubtitle),
          trailing: _updating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton(
                  onPressed: _update,
                  child: Text(l10n.aboutUpdate),
                ),
        );
      case AppUpdateStatus.upToDate:
        return ListTile(
          key: const Key('update-uptodate'),
          leading: Icon(Icons.check_circle_outline,
              color: theme.colorScheme.primary),
          title: Text(l10n.aboutUpToDate),
          trailing: const Icon(Icons.refresh),
          onTap: _checkForUpdate,
        );
      case AppUpdateStatus.unavailable:
        // Dev / sideload / iOS build: no Play update channel. Say so rather
        // than hiding the row — the user just asked, and silence reads as a
        // broken button.
        return ListTile(
          key: const Key('update-unavailable'),
          leading: const Icon(Icons.system_update),
          title: Text(l10n.aboutCheckForUpdates),
          subtitle: Text(l10n.aboutUpdateUnavailable),
        );
    }
  }
}
