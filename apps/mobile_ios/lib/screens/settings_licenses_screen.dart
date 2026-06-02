import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

class SettingsLicensesScreen extends StatelessWidget {
  const SettingsLicensesScreen({super.key});

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
              subtitle: const Text('0.1.0 (dev)'),
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
