import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_licenses_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsLicensesScreen(),
    ),
  );
  await tester.pump();
}

void main() {
  // Runs before any setMockInitialValues so the platform channel is
  // genuinely unavailable — the mock is a process-wide static that
  // cannot be cleared once set.
  testWidgets('version tile degrades to an empty subtitle when the platform '
      'channel fails', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('0.1.0 (dev)'), findsNothing);
  });

  testWidgets('version tile shows the runtime version and build number',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Run',
      packageName: 'com.example.run',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
      installerStore: null,
    );
    await _pump(tester);
    expect(find.text('1.2.3 (45)'), findsOneWidget);
  });
}
