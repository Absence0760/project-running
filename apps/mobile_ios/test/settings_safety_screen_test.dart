import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_safety_screen.dart';
import '../lib/settings_sync.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // api null: no Supabase round-trips — exercises the offline/empty UI
      // (the screen short-circuits the load when api/userId is null).
      home: const SettingsSafetyScreen(api: null),
    ),
  );
  await tester.pumpAndSettle();
}

/// Surfaces one incoming request and gates the confirm RPC so the in-flight
/// window stays open across a second tap.
class _SafetyApi extends ApiClient {
  int confirmCalls = 0;
  final Completer<void> confirmGate = Completer<void>();

  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() async => const [];

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async => [
        PendingSafetyRequest(
          id: 'req-1',
          ownerName: 'Jordan',
          createdAt: DateTime.utc(2026, 5, 1),
        ),
      ];

  @override
  Future<bool> confirmSafetyRequest(String id) async {
    confirmCalls++;
    await confirmGate.future;
    return true;
  }
}


/// Records bag writes and reports `synced` so the pref controls enable —
/// same shape as settings_email_notifications_test's fake. `service`
/// returns null, so the screen renders the defaults (Off / switch off).
class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> universalWrites = [];
  final List<Map<String, dynamic>> deviceWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
    notifyListeners();
  }

  @override
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    deviceWrites.add(changes);
    notifyListeners();
  }
}

Future<_FakeSettingsSync> _fakeSync() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return _FakeSettingsSync(prefs);
}

void main() {
  group('SettingsSafetyScreen', () {
    testWidgets('renders the add form, intro and empty state', (tester) async {
      await _pump(tester);
      expect(find.text('Safety contacts'), findsWidgets);
      expect(find.text('Contact email'), findsOneWidget);
      expect(find.text('Add contact'), findsOneWidget);
      expect(find.text('No safety contacts yet.'), findsOneWidget);
      // No incoming-requests section without pending requests.
      expect(find.text('Requests for you'), findsNothing);
    });

    testWidgets('invalid email shows the inline validation banner',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      // Drain the top-banner auto-dismiss timer so no Timer outlives the test.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a valid-looking email passes the inline check',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'partner@example.com');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      // With api == null the add is a no-op, but it must NOT trip the
      // invalid-email guard — that is the only client-side branch.
      expect(find.text('Enter a valid email address.'), findsNothing);
    });

    testWidgets('double-tapping Confirm on an incoming request fires once',
        (tester) async {
      final api = _SafetyApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      // The incoming-requests section sits below the overdue/auto-share
      // prefs; scroll it into the lazily-built ListView viewport first.
      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      await tester.scrollUntilVisible(
        confirm,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(confirm, findsOneWidget);

      await tester.tap(confirm);
      await tester.pump();
      // Second tap while the first confirm is gated in flight — disabled now.
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();

      expect(api.confirmCalls, 1);

      api.confirmGate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('SettingsSafetyScreen — overdue + auto-live-share prefs', () {
    testWidgets('renders the overdue section with Off default + the switch off',
        (tester) async {
      final sync = await _fakeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overdue alert'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isFalse);
      // The public-by-link disclosure is load-bearing copy.
      expect(
        find.textContaining('viewable by anyone with the link'),
        findsOneWidget,
      );
    });

    testWidgets('picking a window writes the universal pref', (tester) async {
      final sync = await _fakeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();

      expect(sync.universalWrites, [
        {'safety_overdue_minutes': 30},
      ]);
      // Drain the saved-banner timer.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('the auto-live-share toggle writes the device pref',
        (tester) async {
      final sync = await _fakeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(sync.deviceWrites, [
        {'auto_live_share': true},
      ]);
      expect(sync.universalWrites, isEmpty,
          reason: 'the device pref must not leak into the universal bag');
    });

    testWidgets('controls are disabled without a settings service',
        (tester) async {
      await _pump(tester); // api: null, settingsSync: null
      final dropdown = tester.widget<DropdownButton<int?>>(
        find.byType(DropdownButton<int?>),
      );
      expect(dropdown.onChanged, isNull);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
    });
  });
}
