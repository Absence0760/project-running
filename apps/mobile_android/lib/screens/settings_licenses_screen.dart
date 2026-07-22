import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/gen/app_localizations.dart';

class SettingsLicensesScreen extends StatefulWidget {
  const SettingsLicensesScreen({super.key});

  @override
  State<SettingsLicensesScreen> createState() =>
      _SettingsLicensesScreenState();
}

class _SettingsLicensesScreenState extends State<SettingsLicensesScreen> {
  late final Future<String> _version = _loadVersion();

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
  Widget build(BuildContext context) {
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
