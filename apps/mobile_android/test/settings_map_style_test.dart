// Issue #666 round 2: Settings → Preferences offered Streets / Satellite /
// Outdoors / Dark and persisted the pick to the universal settings bag, but
// nothing read it back — `resolveTileUrl` ignored both the preference and
// the app theme, so all seven map surfaces stayed on `streets-v2-dark`.
//
// The link that was missing is the LOCAL mirror: the map surfaces carry no
// Preferences dep and read `activeMapStyle`, so a pick that only reaches
// the cloud bag changes nothing on screen. These tests pin both writes and
// the subtitle reading back from the same place.

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
/// tiles light up. `service` returns null, so `_bagValue` falls through to
/// the local mirror.
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

Future<void> _openMapStyle(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Map style'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Map style'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('subtitle reads the persisted preference, not a fixed default',
      (tester) async {
    final s = await _setUp();
    await s.prefs.setMapStyle('outdoors');
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Map style'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Map style'),
        matching: find.text('Outdoors'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('picking a style writes the local mirror AND the bag',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await _openMapStyle(tester);
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Satellite'));
    await tester.pumpAndSettle();

    // The mirror is what the maps read back through `activeMapStyle`.
    expect(s.prefs.mapStyle, 'satellite');
    expect(
      s.sync.universalWrites,
      contains(containsPair('map_style', 'satellite')),
    );
  });

  testWidgets('the picked style survives a cold start', (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await _openMapStyle(tester);
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Dark'));
    await tester.pumpAndSettle();

    final reloaded = Preferences();
    await reloaded.init();
    expect(reloaded.mapStyle, 'dark');
  });
}
