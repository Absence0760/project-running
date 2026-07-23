import 'dart:async';

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

Future<void> _pumpUpdate(
  WidgetTester tester, {
  required Future<LicenseUpdateStatus> Function() checkUpdate,
  Future<void> Function()? performUpdate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsLicensesScreen(
        checkUpdate: checkUpdate,
        performUpdate: performUpdate ?? () async {},
      ),
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

  testWidgets('update available renders the row + Update button',
      (tester) async {
    await _pumpUpdate(tester,
        checkUpdate: () async => LicenseUpdateStatus.available);
    expect(find.byKey(const Key('update-available')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });

  testWidgets('tapping Update invokes performUpdate', (tester) async {
    var performCalls = 0;
    await _pumpUpdate(
      tester,
      checkUpdate: () async => LicenseUpdateStatus.available,
      performUpdate: () async => performCalls++,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pump(); // setState(updating) → await perform
    await tester.pump(); // await re-check → setState
    expect(performCalls, 1);
  });

  testWidgets('up to date renders the reassurance row, no Update button',
      (tester) async {
    await _pumpUpdate(tester,
        checkUpdate: () async => LicenseUpdateStatus.upToDate);
    expect(find.byKey(const Key('update-uptodate')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsNothing);
  });

  testWidgets('unavailable (dev / sideload / iOS) shows no update row',
      (tester) async {
    await _pumpUpdate(tester,
        checkUpdate: () async => LicenseUpdateStatus.unavailable);
    expect(find.byKey(const Key('update-available')), findsNothing);
    expect(find.byKey(const Key('update-uptodate')), findsNothing);
    expect(find.byKey(const Key('update-checking')), findsNothing);
  });

  testWidgets('checking state shows while the update check is in flight',
      (tester) async {
    final gate = Completer<LicenseUpdateStatus>();
    await _pumpUpdate(tester, checkUpdate: () => gate.future);
    expect(find.byKey(const Key('update-checking')), findsOneWidget);
    gate.complete(LicenseUpdateStatus.upToDate);
    await tester.pump();
    expect(find.byKey(const Key('update-checking')), findsNothing);
    expect(find.byKey(const Key('update-uptodate')), findsOneWidget);
  });
}
