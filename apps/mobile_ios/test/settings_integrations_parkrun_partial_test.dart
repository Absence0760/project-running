import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_integrations_screen.dart';

/// `parkrun-import` bounds the result set at `MAX_PARKRUN_ROWS` and says so
/// with `complete`. A capped history and a whole one both arrive as a positive
/// count, so reading only `imported` told the runner "Imported 40 parkrun
/// results" about a history that has more. decisions § 1014.
class _FakeApi extends ApiClient {
  _FakeApi(this.result);

  final ImportCompleteness result;

  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => const [];

  @override
  Future<UserProfileRow?> fetchMyProfile() async => null;

  @override
  Future<void> setParkrunAthleteNumber(String? athleteNumber) async {}

  @override
  Future<ImportCompleteness> importParkrunResults(String athleteNumber) async =>
      result;
}

Future<AppLocalizations> _pump(
    WidgetTester tester, ImportCompleteness result) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsIntegrationsScreen(
        apiClient: _FakeApi(result),
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
        preferences: prefs,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.delegate.load(const Locale('en'));
}

Future<void> _runImport(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.widgetWithText(ListTile, l10n.integrationsParkrunName));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
    'A123456',
  );
  await tester.tap(find.widgetWithText(FilledButton, l10n.integrationsImport));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a capped history names the gap rather than only its existence',
      (tester) async {
    const r = ImportCompleteness(
        imported: 40, skipped: 2, total: 300, complete: false);
    final l10n = await _pump(tester, r);
    await _runImport(tester, l10n);

    expect(find.text(l10n.integrationsImportPartialOf(40, 300)), findsOneWidget);
    expect(find.text(l10n.integrationsParkrunImported(40)), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a shortfall with no total still says a shortfall happened',
      (tester) async {
    // A body from a deployment that predates `total`, or one this build
    // cannot read. Fail-closed: partial, with no fabricated denominator.
    const r =
        ImportCompleteness(imported: 12, skipped: 0, total: null, complete: false);
    final l10n = await _pump(tester, r);
    await _runImport(tester, l10n);

    expect(find.text(l10n.integrationsImportPartial(12)), findsOneWidget);
    expect(find.text(l10n.integrationsParkrunImported(12)), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a whole history still reads as a plain success', (tester) async {
    const r =
        ImportCompleteness(imported: 7, skipped: 1, total: 8, complete: true);
    final l10n = await _pump(tester, r);
    await _runImport(tester, l10n);

    expect(find.text(l10n.integrationsParkrunImported(7)), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a complete import that found nothing new says so', (tester) async {
    const r =
        ImportCompleteness(imported: 0, skipped: 9, total: 9, complete: true);
    final l10n = await _pump(tester, r);
    await _runImport(tester, l10n);

    expect(find.text(l10n.integrationsParkrunNoneNew), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
