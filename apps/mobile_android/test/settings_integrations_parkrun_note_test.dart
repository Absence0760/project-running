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
import '../lib/text_limits.dart';

class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => const [];

  @override
  Future<UserProfileRow?> fetchMyProfile() async =>
      UserProfileRow(shadowHidden: false, id: 'u1');
}

Future<void> _pump(WidgetTester tester, Locale deviceLocale) async {
  tester.platformDispatcher.localeTestValue = deviceLocale;
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsIntegrationsScreen(
        apiClient: _FakeApi(),
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
        preferences: prefs,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'parkrun tile discloses the limited footprint outside parkrun countries',
      (tester) async {
    await _pump(tester, const Locale('es', 'ES'));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.integrationsParkrunRegionNote), findsOneWidget);
    expect(find.text(l10n.integrationsParkrunTileSubtitle), findsNothing);
    // The tile stays tappable — the note is a disclosure, not a gate.
    final tile = tester.widget<ListTile>(find.widgetWithText(
        ListTile, l10n.integrationsParkrunName));
    expect(tile.onTap, isNotNull);
  });

  testWidgets('parkrun tile keeps the normal subtitle in a parkrun country',
      (tester) async {
    await _pump(tester, const Locale('en', 'GB'));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.integrationsParkrunTileSubtitle), findsOneWidget);
    expect(find.text(l10n.integrationsParkrunRegionNote), findsNothing);
  });

  testWidgets('the parkrun field takes every character the column stores',
      (tester) async {
    // decisions § 792: the column caps at 32 and this field capped at 20, so a
    // 25-character parkrun id typed fine on web and was truncated here.
    await _pump(tester, const Locale('en', 'GB'));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.widgetWithText(ListTile, l10n.integrationsParkrunName));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.widgetWithText(
        TextField, l10n.integrationsParkrunFieldLabel));
    expect(field.maxLength, kParkrunNumberMaxLength);
  });
}
