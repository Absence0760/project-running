import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

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

const _zonesDialogTitle = 'Heart-rate zones (upper bounds, bpm)';
const _confirmDialogTitle = 'Clear heart-rate zones?';

Finder _dialogWithTitle(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(AlertDialog),
    );

Future<({Preferences prefs, _FakeSettingsSync sync})> _setUp() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, sync: _FakeSettingsSync(prefs));
}

Future<void> _openZonesDialog(
  WidgetTester tester, {
  required Preferences prefs,
  required SettingsSyncService sync,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
    ),
  );
  await tester.pumpAndSettle();
  await tester.dragUntilVisible(
    find.text('Heart-rate zones'),
    find.byType(Scrollable).first,
    const Offset(0, -250),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Heart-rate zones'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets(
      'cancelling the clear-zones confirmation keeps the zones dialog open with its values',
      (tester) async {
    final s = await _setUp();
    await _openZonesDialog(tester, prefs: s.prefs, sync: s.sync);

    await tester.enterText(find.byType(TextField).first, '150');
    await tester.pump(const Duration(milliseconds: 300));

    final zonesDialog = _dialogWithTitle(_zonesDialogTitle);
    await tester.tap(
      find.descendant(of: zonesDialog, matching: find.text('Clear')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_confirmDialogTitle), findsOneWidget);

    final confirmDialog = _dialogWithTitle(_confirmDialogTitle);
    await tester.tap(
      find.descendant(of: confirmDialog, matching: find.text('Cancel')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_confirmDialogTitle), findsNothing);
    expect(find.text(_zonesDialogTitle), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '150',
    );
    expect(s.sync.universalWrites, isEmpty);
  });

  testWidgets('confirming the clear-zones dialog clears the zones',
      (tester) async {
    final s = await _setUp();
    await _openZonesDialog(tester, prefs: s.prefs, sync: s.sync);

    await tester.enterText(find.byType(TextField).first, '150');
    await tester.pump(const Duration(milliseconds: 300));

    final zonesDialog = _dialogWithTitle(_zonesDialogTitle);
    await tester.tap(
      find.descendant(of: zonesDialog, matching: find.text('Clear')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final confirmDialog = _dialogWithTitle(_confirmDialogTitle);
    await tester.tap(
      find.descendant(of: confirmDialog, matching: find.text('Clear')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_confirmDialogTitle), findsNothing);
    expect(find.text(_zonesDialogTitle), findsNothing);
    expect(s.sync.universalWrites, [
      {'hr_zones': null},
    ]);
  });
}
