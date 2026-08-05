import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/races_screen.dart';
import '../lib/screens/settings_integrations_screen.dart';

class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => const [];
}

Future<void> _pump(WidgetTester tester) async {
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
  testWidgets('both timing-provider tiles link to the race calendar and say so',
      (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // The provider probe governs the *import* copy only; the tap is a
    // secondary deep link into the calendar and is never gated on it.
    for (final name in [l10n.integrationsRunsignup, l10n.integrationsChronotrack]) {
      final tile =
          tester.widget<ListTile>(find.widgetWithText(ListTile, name));
      expect(tile.onTap, isNotNull, reason: '$name must stay tappable');
    }
    expect(find.text(l10n.integrationsRunsignupOpen), findsNWidgets(2));
  });

  testWidgets('tapping the RunSignUp tile opens the race calendar',
      (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.integrationsRunsignup));
    await tester.pumpAndSettle();
    expect(find.byType(RacesScreen), findsOneWidget);
  });
}
