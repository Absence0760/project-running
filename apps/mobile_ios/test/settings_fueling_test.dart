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
/// fueling tiles light up. `service` returns null, so the tile subtitle
/// falls through to the local Preferences value.
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

  testWidgets('carbs-per-hour tile shows the 60 g/h default subtitle',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Carbs per hour'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Carbs per hour'),
        matching: find.text('60 g/h'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('editing carbs/hr writes the bag + updates Preferences',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Carbs per hour'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Carbs per hour'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '75');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'carbs_per_hour': 75},
    ]);
    expect(s.prefs.carbsPerHourG, 75);
  });
}
