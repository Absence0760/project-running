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

/// A Strava sync that stops early — because Strava throttled us, because an
/// upstream call failed, or because the 20-page cap tripped — used to report
/// the same "Synced. N new, M already present." banner a finished walk does.
/// The runner has then been told there is nothing left to fetch, and what was
/// left is only reachable until it ages past the 90-day lookback window.
class _FakeApi extends ApiClient {
  _FakeApi(this.result);

  final StravaSyncResult result;

  @override
  String? get userId => 'u1';

  @override
  Future<List<IntegrationRow>> fetchIntegrations() async => [
        IntegrationRow(
          id: 'i1',
          userId: 'u1',
          provider: 'strava',
          lastSyncAt: DateTime.utc(2026, 5, 10, 8),
        ),
      ];

  @override
  Future<StravaSyncResult> syncStrava({int lookbackDays = 90}) async => result;
}

Future<AppLocalizations> _pump(WidgetTester tester, StravaSyncResult r) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsIntegrationsScreen(
        apiClient: _FakeApi(r),
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
        preferences: prefs,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.delegate.load(const Locale('en'));
}

Future<void> _tapSync(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(
    find.widgetWithText(ListTile, l10n.integrationsStravaName),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a throttled sync says so instead of reporting a finished one',
      (tester) async {
    const r = StravaSyncResult(
      imported: 40,
      skipped: 2,
      failed: 0,
      rateLimited: true,
      complete: false,
      resumable: false,
    );
    final l10n = await _pump(tester, r);
    await _tapSync(tester, l10n);

    expect(
      find.text(l10n.integrationsSyncPartialRateLimited(40, 2)),
      findsOneWidget,
    );
    expect(find.text(l10n.integrationsSyncResult(40, 2)), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a sync truncated for any other reason is still partial',
      (tester) async {
    // An upstream error, a malformed page and the 20-page safety cap all
    // return `rateLimited: false, complete: false` — before `complete`
    // existed these were indistinguishable from a finished sync.
    const r = StravaSyncResult(
      imported: 1000,
      skipped: 0,
      failed: 0,
      rateLimited: false,
      complete: false,
      resumable: true,
    );
    final l10n = await _pump(tester, r);
    await _tapSync(tester, l10n);

    expect(find.text(l10n.integrationsSyncPartial(1000, 0)), findsOneWidget);
    expect(find.text(l10n.integrationsSyncResult(1000, 0)), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a finished sync keeps the plain banner', (tester) async {
    const r = StravaSyncResult(
      imported: 3,
      skipped: 7,
      failed: 0,
      rateLimited: false,
      complete: true,
      resumable: false,
    );
    final l10n = await _pump(tester, r);
    await _tapSync(tester, l10n);

    expect(find.text(l10n.integrationsSyncResult(3, 7)), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a finished sync that dropped activities reports the failures',
      (tester) async {
    // The phone dropped `failed` entirely where web has reported it since the
    // toast was written — a run Strava served but we could not ingest was
    // invisible on mobile.
    const r = StravaSyncResult(
      imported: 5,
      skipped: 1,
      failed: 2,
      rateLimited: false,
      complete: true,
      resumable: false,
    );
    final l10n = await _pump(tester, r);
    await _tapSync(tester, l10n);

    expect(
      find.text(l10n.integrationsSyncResultWithFailed(5, 1, 2)),
      findsOneWidget,
    );
    expect(find.text(l10n.integrationsSyncResult(5, 1)), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });
}
