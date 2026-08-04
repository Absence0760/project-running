import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_about_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsAboutScreen(),
    ),
  );
  await tester.pump();
}

Future<void> _pumpUpdate(
  WidgetTester tester, {
  required Future<AppUpdateStatus> Function() checkUpdate,
  Future<void> Function()? performUpdate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsAboutScreen(
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

  testWidgets('rows read version → update → open-source licenses',
      (tester) async {
    // The update path is why this screen is called About & updates rather
    // than Licenses — the version and the update affordance come first, the
    // licenses page last.
    await _pump(tester);
    final version = tester.getTopLeft(find.text('Version')).dy;
    final update = tester.getTopLeft(find.text('Check for updates')).dy;
    final licenses = tester.getTopLeft(find.text('Open-source licenses')).dy;
    expect(version, lessThan(update));
    expect(update, lessThan(licenses));
  });

  testWidgets('does NOT run an update check on mount', (tester) async {
    // Opening the screen used to fire a Play round-trip from initState —
    // an unasked-for network call on every visit to the licenses page.
    var checkCalls = 0;
    await _pumpUpdate(tester, checkUpdate: () async {
      checkCalls++;
      return AppUpdateStatus.upToDate;
    });
    await tester.pump();
    expect(checkCalls, 0);
    expect(find.byKey(const Key('update-check')), findsOneWidget);
  });

  testWidgets('tapping Check for updates runs the check', (tester) async {
    var checkCalls = 0;
    await _pumpUpdate(tester, checkUpdate: () async {
      checkCalls++;
      return AppUpdateStatus.upToDate;
    });
    await tester.tap(find.byKey(const Key('update-check')));
    await tester.pumpAndSettle();
    expect(checkCalls, 1);
    expect(find.byKey(const Key('update-uptodate')), findsOneWidget);
  });

  testWidgets('update available renders the row + Update button',
      (tester) async {
    await _pumpUpdate(tester,
        checkUpdate: () async => AppUpdateStatus.available);
    await tester.tap(find.byKey(const Key('update-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-available')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });

  testWidgets('tapping Update invokes performUpdate', (tester) async {
    var performCalls = 0;
    await _pumpUpdate(
      tester,
      checkUpdate: () async => AppUpdateStatus.available,
      performUpdate: () async => performCalls++,
    );
    await tester.tap(find.byKey(const Key('update-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();
    expect(performCalls, 1);
  });

  testWidgets('up to date renders the reassurance row, no Update button',
      (tester) async {
    await _pumpUpdate(tester,
        checkUpdate: () async => AppUpdateStatus.upToDate);
    await tester.tap(find.byKey(const Key('update-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-uptodate')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsNothing);
  });

  testWidgets('unavailable (dev / sideload / iOS) says so instead of going '
      'silent', (tester) async {
    await _pumpUpdate(tester,
        checkUpdate: () async => AppUpdateStatus.unavailable);
    await tester.tap(find.byKey(const Key('update-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-unavailable')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsNothing);
  });

  testWidgets('checking state shows while the update check is in flight',
      (tester) async {
    final gate = Completer<AppUpdateStatus>();
    await _pumpUpdate(tester, checkUpdate: () => gate.future);
    await tester.tap(find.byKey(const Key('update-check')));
    await tester.pump();
    expect(find.byKey(const Key('update-checking')), findsOneWidget);
    gate.complete(AppUpdateStatus.upToDate);
    await tester.pump();
    expect(find.byKey(const Key('update-checking')), findsNothing);
    expect(find.byKey(const Key('update-uptodate')), findsOneWidget);
  });
}
