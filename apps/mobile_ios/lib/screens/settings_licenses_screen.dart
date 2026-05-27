import 'package:flutter/material.dart';

class SettingsLicensesScreen extends StatelessWidget {
  const SettingsLicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Licenses')),
      body: SafeArea(
        child: ListView(
          children: [
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Version'),
              subtitle: Text('0.1.0 (dev)'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Open-source licenses'),
              subtitle: const Text('Third-party packages bundled with this app'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context),
            ),
          ],
        ),
      ),
    );
  }
}
