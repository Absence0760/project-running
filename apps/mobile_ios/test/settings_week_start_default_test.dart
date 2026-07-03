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
  Future<void> updateUniversal(Map<String, dynamic> changes) async {}
}

Future<void> _pump(WidgetTester tester, Locale deviceLocale) async {
  tester.platformDispatcher.localeTestValue = deviceLocale;
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
          preferences: prefs, settingsSync: _FakeSettingsSync(prefs)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Week starts on'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
}

Finder _weekStartSubtitle(String label) => find.descendant(
      of: find.widgetWithText(ListTile, 'Week starts on'),
      matching: find.text(label),
    );

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets(
      'week-start tile defaults to Sunday for a US device locale when unset',
      (tester) async {
    await _pump(tester, const Locale('en', 'US'));
    expect(_weekStartSubtitle('Sunday'), findsOneWidget);
  });

  testWidgets(
      'week-start tile defaults to Monday for a German device locale',
      (tester) async {
    await _pump(tester, const Locale('de', 'DE'));
    expect(_weekStartSubtitle('Monday'), findsOneWidget);
  });
}
