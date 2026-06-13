import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

/// Records universal-bag writes and reports `synced` so the bag-backed
/// tiles light up. `service` returns null, so `_bagValue` falls through
/// to the call-site default ('important') — that's what lets us assert
/// the default-state subtitle without standing up a real SettingsService.
class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> universalWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
    notifyListeners();
  }
}

Future<({Preferences prefs, _FakeSettingsSync sync})> _setUp() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, sync: _FakeSettingsSync(prefs));
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required SettingsSyncService sync,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
    ),
  );
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('push-notifications tile shows the default (Important only)',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Push notifications'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    // With no stored value, the subtitle reflects the 'important' default.
    expect(find.widgetWithText(ListTile, 'Push notifications'), findsOneWidget);
  });

  testWidgets('picking Everything writes push_notifications=all to the bag',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Push notifications'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Push notifications'));
    await tester.pumpAndSettle();

    // The radio dialog is open; pick the "Everything" option.
    await tester.tap(find.text('Everything'));
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'push_notifications': 'all'},
    ]);
  });

  testWidgets('picking Off writes push_notifications=off (full kill-switch)',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Push notifications'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Push notifications'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'push_notifications': 'off'},
    ]);
  });
}
