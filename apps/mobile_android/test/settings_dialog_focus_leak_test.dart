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

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    notifyListeners();
  }
}

Future<({Preferences prefs, _FakeSettingsSync sync})> _setUp() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, sync: _FakeSettingsSync(prefs));
}

Future<void> _openRestingHrDialog(
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
    find.widgetWithText(ListTile, 'Resting heart rate'),
    find.byType(Scrollable).first,
    const Offset(0, -250),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Resting heart rate'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets(
      'dismissing the resting-HR numeric dialog releases focus and hides the keyboard',
      (tester) async {
    final s = await _setUp();
    await _openRestingHrDialog(tester, prefs: s.prefs, sync: s.sync);

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '55');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsNothing);
    // Without the unfocus, primary focus is stranded in the popped dialog's
    // modal scope, which re-triggers the keyboard on the route underneath.
    expect(
      FocusManager.instance.primaryFocus?.debugLabel ?? '',
      isNot(contains('Modal')),
    );
  });

  testWidgets(
      'cancelling the resting-HR numeric dialog releases focus and hides the keyboard',
      (tester) async {
    final s = await _setUp();
    await _openRestingHrDialog(tester, prefs: s.prefs, sync: s.sync);

    await tester.enterText(find.byType(TextField), '55');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel ?? '',
      isNot(contains('Modal')),
    );
  });
}
