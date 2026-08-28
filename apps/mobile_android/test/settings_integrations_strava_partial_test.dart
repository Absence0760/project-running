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

  StravaSyncResult result;
  final List<int> lookbacks = [];

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
  Future<StravaSyncResult> syncStrava({int lookbackDays = 90}) async {
    lookbacks.add(lookbackDays);
    return result;
  }
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  StravaSyncResult r, {
  _FakeApi? api,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsIntegrationsScreen(
        apiClient: api ?? _FakeApi(r),
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

  testWidgets('a truncated sync leaves a note on the tile, and a finished one clears it',
      (tester) async {
    // The banner says it once and slides away. The lookback window is measured
    // from now, so the record of "there is more to fetch" has to outlive it or
    // the rest ages out unnoticed.
    final api = _FakeApi(const StravaSyncResult(
      imported: 1000,
      skipped: 0,
      failed: 0,
      rateLimited: false,
      complete: false,
      resumable: true,
    ));
    final l10n = await _pump(tester, api.result, api: api);
    expect(find.text(l10n.integrationsSyncPartialNoteResumable), findsNothing);

    await _tapSync(tester, l10n);
    expect(
      find.text(l10n.integrationsSyncPartialNoteResumable),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4));
    api.result = const StravaSyncResult(
      imported: 5,
      skipped: 0,
      failed: 0,
      rateLimited: false,
      complete: true,
      resumable: false,
    );
    await _tapSync(tester, l10n);
    expect(find.text(l10n.integrationsSyncPartialNoteResumable), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a truncation that recorded no restart point says so', (tester) async {
    // A throttle on the first page advances nothing, so "carry on from where we
    // stopped" would be a claim about a point that does not exist.
    const r = StravaSyncResult(
      imported: 0,
      skipped: 0,
      failed: 0,
      rateLimited: true,
      complete: false,
      resumable: false,
    );
    final l10n = await _pump(tester, r);
    await _tapSync(tester, l10n);

    expect(find.text(l10n.integrationsSyncPartialNote), findsOneWidget);
    expect(find.text(l10n.integrationsSyncPartialNoteResumable), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the history picker offers every window and syncs with the one chosen',
      (tester) async {
    // Neither client could ask for more than 90 days, so a truncation left long
    // enough for the missed activities to age out of that window had no in-app
    // recovery at all — the only remaining path was the bulk export.
    final api = _FakeApi(const StravaSyncResult(
      imported: 12,
      skipped: 0,
      failed: 0,
      rateLimited: false,
      complete: true,
      resumable: false,
    ));
    final l10n = await _pump(tester, api.result, api: api);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.integrationsStravaSyncHistory));
    await tester.pumpAndSettle();

    for (final label in [
      l10n.integrationsStravaLookback90,
      l10n.integrationsStravaLookback180,
      l10n.integrationsStravaLookback365,
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text(l10n.integrationsStravaLookback365));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.integrationsSyncNow),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(api.lookbacks, [365]);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the plain Sync now path still asks for the default window',
      (tester) async {
    // Widening is an explicit act: Strava's per-user budget is 100 requests /
    // 15 minutes and the walk spends one per 50 activities, so a wider default
    // would make every routine sync several times heavier.
    final api = _FakeApi(const StravaSyncResult(
      imported: 1,
      skipped: 0,
      failed: 0,
      rateLimited: false,
      complete: true,
      resumable: false,
    ));
    final l10n = await _pump(tester, api.result, api: api);
    await _tapSync(tester, l10n);

    expect(api.lookbacks, [90]);

    await tester.pump(const Duration(seconds: 4));
  });
}
