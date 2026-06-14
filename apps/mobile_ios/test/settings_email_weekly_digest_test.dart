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
/// to the call-site default — for email_weekly_digest that's an absent
/// key (treated as 'off'), which is what lets us assert the default-off
/// state without standing up a real SettingsService.
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
  // The weekly-digest toggle is the last row in a long preferences list.
  // On the default 800x600 test viewport, scrollUntilVisible leaves its
  // centre just below the fold (y≈626), so tap() can't hit it. Give the
  // test a tall viewport so the whole list is reachable.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

  testWidgets('weekly-digest toggle defaults off (opt-in consent)',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Weekly digest email'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly digest email'),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('opting in writes email_weekly_digest=on to the bag',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Weekly digest email'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Weekly digest email'));
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'email_weekly_digest': 'on'},
    ]);
  });
}
