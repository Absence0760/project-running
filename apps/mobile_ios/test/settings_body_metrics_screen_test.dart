import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;

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

/// Consented, with a birth date on file. Records whether the withdrawal
/// path writes the age record back — since decisions § 721 the server keeps
/// the column, so the screen must not touch it.
class _ConsentedWithDobApi extends ApiClient {
  bool withdrawCalled = false;
  int ageRecordCalls = 0;

  @override
  String? get userId => 'u1';
  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(
        shadowHidden: false,
        id: 'u1',
        healthDataConsentAt: DateTime.utc(2026, 1, 1),
        heightCm: 175,
        dateOfBirth: DateTime.utc(1990, 1, 15),
      );
  @override
  Future<double?> fetchLatestBodyWeightKg() async => 70.0;
  @override
  Future<void> withdrawHealthDataConsent() async => withdrawCalled = true;
  @override
  Future<void> setMyDateOfBirth(DateTime? dateOfBirth) async =>
      ageRecordCalls++;
}

/// Records the universal-bag writes so the Art 9 mirror clear is observable.
class _RecordingSync extends SettingsSyncService {
  _RecordingSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> writes = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    writes.add(changes);
    notifyListeners();
  }
}

/// The profile read fails. Before the fail-closed guard the screen fell back
/// to consent-off with no stamp, which made Save read as a withdrawal.
class _FailingLoadApi extends ApiClient {
  bool withdrawCalled = false;
  int profileCalls = 0;

  @override
  String? get userId => 'u1';
  @override
  Future<UserProfileRow?> fetchMyProfile() async {
    profileCalls++;
    throw Exception('offline');
  }

  @override
  Future<double?> fetchLatestBodyWeightKg() async => 70.0;
  @override
  Future<void> withdrawHealthDataConsent() async => withdrawCalled = true;
}

/// Never resolves the profile fetch, so the loading frame is observable.
class _HangingApi extends ApiClient {
  @override
  String? get userId => 'u1';
  @override
  Future<UserProfileRow?> fetchMyProfile() =>
      Completer<UserProfileRow?>().future;
  @override
  Future<double?> fetchLatestBodyWeightKg() async => null;
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
    testWidgets('the loading frame stands form rows, not a bare spinner',
        (tester) async {
      final prefs = await _prefs();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsBodyMetricsScreen(
            api: _HangingApi(),
            settingsSync: null,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

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

    testWidgets('a height or weight outside the column range is refused here',
        (tester) async {
      // `body_metrics.weight_kg` is CHECK-bounded `> 0 and <= 500` and
      // `user_profiles.height_cm` `> 0 and <= 300`; this screen guarded only
      // `> 0`, so a typed 600 kg reached the insert as a raw 23514 naming a
      // constraint and no field (decisions § 792).
      await _pump(tester, await _prefs());
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      final weight = find.widgetWithText(TextField, 'Weight');
      await tester.enterText(weight, '600');
      await tester.pump();
      expect(find.text('Enter a weight between 20 and 250 kg.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.enterText(weight, '72');
      await tester.pump();
      expect(find.text('Enter a weight between 20 and 250 kg.'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      await tester.enterText(find.widgetWithText(TextField, 'Height'), '500');
      await tester.pump();
      expect(find.text('Enter a height between 50 and 300 cm.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('the refused range is stated in the unit the field is typed in',
        (tester) async {
      // The field takes lbs when the runner's weight unit is lbs but the
      // column is kilograms, so a bound stated in kg would name numbers the
      // field never shows. The floor rounds UP through the conversion, so the
      // number offered is one the kg gate actually accepts.
      SharedPreferences.setMockInitialValues({'weight_unit': 'lbs'});
      final prefs = Preferences();
      await prefs.init();
      await _pump(tester, prefs);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '1200');
      await tester.pump();
      expect(find.text('Enter a weight between 44.1 and 551.1 lbs.'),
          findsOneWidget);
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

    });
  });

  group('SettingsBodyMetricsScreen — failed load', () {
    testWidgets('shows an error state instead of an unconsented form',
        (tester) async {
      final prefs = await _prefs();
      final api = _FailingLoadApi();
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining("Couldn't load your body metrics"),
          findsOneWidget);
      // Save is what would have fired the erasure — it must be unreachable.
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(api.withdrawCalled, isFalse);
    });

    testWidgets('Retry re-runs the load', (tester) async {
      final prefs = await _prefs();
      final api = _FailingLoadApi();
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.profileCalls, 1);

      await tester.runAsync(() => tester.tap(find.text('Retry')));
      await tester.pumpAndSettle();
      expect(api.profileCalls, 2);
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

    });

    testWidgets('withdrawal clears the Art 9 mirror and leaves the age record '
        'to the server', (tester) async {
      // Two DOB stores, two lawful bases (§ 718). The prefs-bag mirror is
      // the Art 9 health-use copy and goes with the consent; the
      // `user_profiles` column is the child-safety age record the under-18
      // discoverability floor reads, and since § 721 the withdrawal RPC
      // leaves it standing. This screen used to write it back straight after
      // the RPC — a compensation whose whole failure mode was a crash
      // between the two calls leaving a declared minor discoverable.
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      final api = _ConsentedWithDobApi();
      final sync = _RecordingSync(prefs);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsBodyMetricsScreen(
            api: api,
            settingsSync: sync,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.widgetWithText(TextField, 'Height'), '');
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '');
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester
          .runAsync(() => tester.tap(find.widgetWithText(FilledButton, 'Save')));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => tester.tap(find.widgetWithText(TextButton, 'Withdraw & erase')));
      await tester.pumpAndSettle();

      expect(api.withdrawCalled, isTrue);
      expect(api.ageRecordCalls, 0,
          reason: 'the age record is the server\'s to keep, not this '
              'screen\'s to re-assert');
      expect(sync.writes.any((w) => w.containsKey(SettingsKeys.dateOfBirth) &&
              w[SettingsKeys.dateOfBirth] == null), isTrue,
          reason: 'the Art 9 prefs-bag mirror must be cleared');

      await tester.pump(const Duration(seconds: 4));
    });
  });
}
