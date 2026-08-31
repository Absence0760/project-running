import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/race_provider_labels.dart';
import '../lib/race_service.dart';
import '../lib/screens/races_screen.dart';
import '../lib/screens/settings_integrations_screen.dart';

class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => const [];
}

class _FakeRaceService extends RaceService {
  final Set<String> configured;

  _FakeRaceService({this.configured = const {}});

  @override
  Future<bool> isProviderConfigured(String provider) async =>
      configured.contains(provider);
}

Future<void> _pump(WidgetTester tester, {Set<String> configured = const {}}) async {
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
        raceService: _FakeRaceService(configured: configured),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every import provider gets a tile that links to the race calendar',
      (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final labels = raceProviderLabels(l10n);

    for (final spec in raceImportProviders) {
      final row = labels[spec.provider];
      expect(row, isNotNull,
          reason: '${spec.provider} has no name, so its tile cannot be built');
      // The provider probe governs the *import* copy only; the tap is a
      // secondary deep link into the calendar and is never gated on it.
      final tile =
          tester.widget<ListTile>(find.widgetWithText(ListTile, row!.name));
      expect(tile.onTap, isNotNull, reason: '${row.name} must stay tappable');
    }
    expect(find.text(l10n.integrationsRunsignupOpen),
        findsNWidgets(raceImportProviders.length));
  });

  testWidgets('tapping the RunSignUp tile opens the race calendar',
      (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.integrationsRunsignup));
    await tester.pumpAndSettle();
    expect(find.byType(RacesScreen), findsOneWidget);
  });

  testWidgets('tapping the UltraSignup tile opens the race calendar',
      (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.integrationsUltrasignup));
    await tester.pumpAndSettle();
    expect(find.byType(RacesScreen), findsOneWidget);
  });

  testWidgets('each tile reports its own probe, never a peer provider\'s',
      (tester) async {
    // UltraSignup has its own credential pair, so a provisioned RunSignUp key
    // must not make the UltraSignup tile claim the import leg is live.
    await _pump(tester, configured: const {'runsignup'});
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.integrationsRunsignupConnect), findsOneWidget);
    expect(find.text(l10n.integrationsUltrasignupUnavailable), findsOneWidget);
    expect(find.text(l10n.integrationsChronotrackUnavailable), findsOneWidget);
    expect(find.text(l10n.integrationsRunsignupUnavailable), findsNothing);
  });

  testWidgets('a configured UltraSignup tile says the import leg is live',
      (tester) async {
    await _pump(tester, configured: const {'ultrasignup'});
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.integrationsUltrasignupConnect), findsOneWidget);
    expect(find.text(l10n.integrationsUltrasignupUnavailable), findsNothing);
  });
}
