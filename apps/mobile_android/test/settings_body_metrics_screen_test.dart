import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_body_metrics_screen.dart';
import '../lib/settings_sync.dart';

/// A settings-sync whose universal-bag write always fails — drives the
/// _putBag error-surfacing path for the activity / goal pickers.
class _ThrowingSync extends SettingsSyncService {
  _ThrowingSync(Preferences prefs) : super(preferences: prefs);

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    throw Exception('boom');
  }
}

/// Fake with prior consent + a saved weight so the withdrawal path has
/// something to erase. Records the destructive calls.
class _ConsentedApi extends ApiClient {
  bool withdrawCalled = false;

  @override
  String? get userId => 'u1';
  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(shadowHidden: false, 
        id: 'u1',
        healthDataConsentAt: DateTime.utc(2026, 1, 1),
        heightCm: 175,
      );
  @override
  Future<double?> fetchLatestBodyWeightKg() async => 70.0;
  @override
  Future<void> withdrawHealthDataConsent() async => withdrawCalled = true;
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, Preferences prefs) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // api + settingsSync null: no Supabase round-trips, exercises the
      // consent-gate UI offline.
      home: SettingsBodyMetricsScreen(
        api: null,
        settingsSync: null,
        preferences: prefs,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SettingsBodyMetricsScreen', () {
    testWidgets('consent off by default — height & weight fields are hidden',
        (tester) async {
      await _pump(tester, await _prefs());
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Height'), findsNothing);
      expect(find.text('Weight'), findsNothing);
    });

    testWidgets('turning on consent reveals the height + weight inputs',
        (tester) async {
      await _pump(tester, await _prefs());
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
    });

    testWidgets('activity level + goal show defaults and open a picker',
        (tester) async {
      await _pump(tester, await _prefs());
      // Defaults: moderate activity, maintain goal. Activity labels describe
      // the non-exercise baseline (logged workouts are added on top).
      expect(find.text('Moderately active (on your feet often)'), findsOneWidget);
      expect(find.text('Maintain weight'), findsOneWidget);

      await tester.tap(find.text('Activity level'));
      await tester.pumpAndSettle();
      // The picker lists all five activity levels.
      expect(find.text('Mostly sitting (desk job)'), findsOneWidget);
      expect(find.text('Lightly active (light daily movement)'), findsOneWidget);
      expect(find.text('Extremely active (hard physical labour)'), findsOneWidget);
    });

    testWidgets('a failed activity-pref save surfaces an error banner',
        (tester) async {
      final prefs = await _prefs();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsBodyMetricsScreen(
            api: null,
            settingsSync: _ThrowingSync(prefs),
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Activity level'));
      await tester.pumpAndSettle();
      // Pick a different level — the _putBag write throws, so the screen
      // must show the failure banner rather than silently swallowing it.
      await tester.runAsync(
          () => tester.tap(find.text('Mostly sitting (desk job)')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save'), findsOneWidget);

      // Drain the showTopBanner auto-dismiss timer.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('SettingsBodyMetricsScreen — withdraw-consent confirm', () {
    testWidgets('Cancel does not erase; confirm calls the withdrawal RPC',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      final api = _ConsentedApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsBodyMetricsScreen(
            api: api,
            settingsSync: null,
            preferences: prefs,
          ),
        ),
      );
      // Let _load resolve (consent on, height/weight populated).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SwitchListTile), findsOneWidget);

      // Clear the height + weight fields first (otherwise the
      // consent-required guard fires before the withdrawal path), then
      // toggle consent OFF → Save → confirm dialog appears.
      await tester.enterText(find.widgetWithText(TextField, 'Height'), '');
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '');
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.runAsync(() => tester.tap(find.widgetWithText(FilledButton, 'Save')));
      await tester.pumpAndSettle();
      expect(find.text('Withdraw health-data consent?'), findsOneWidget);

      // Cancel → nothing erased.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(api.withdrawCalled, isFalse);

      // Save again → confirm via "Withdraw & erase" → the RPC fires.
      await tester.runAsync(() => tester.tap(find.widgetWithText(FilledButton, 'Save')));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => tester.tap(find.widgetWithText(TextButton, 'Withdraw & erase')));
      await tester.pumpAndSettle();
      expect(api.withdrawCalled, isTrue);

      // Drain the showTopBanner auto-dismiss timer.
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
