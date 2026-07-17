// Widget tests for the "Dim screen while recording" tile on
// settings_preferences_screen.dart (issue #271): the tile renders with its
// battery-saver subtitle, toggling it flips the per-device pref, and it is
// disabled while keep-screen-on is off (nothing to dim).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

Future<void> _pump(WidgetTester tester, Preferences prefs) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: null),
    ),
  );
}

SwitchListTile _dimTile() => find
    .widgetWithText(SwitchListTile, 'Dim screen while recording')
    .evaluate()
    .single
    .widget as SwitchListTile;

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('renders with its battery-saver subtitle, enabled by default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Dim screen while recording'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Dim screen while recording'),
        matching: find.textContaining('save battery'),
      ),
      findsOneWidget,
    );
    // keep-screen-on defaults true, so the dim toggle is interactive.
    expect(_dimTile().onChanged, isNotNull);
  });

  testWidgets('toggling the tile flips the per-device pref', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Dim screen while recording'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(prefs.dimScreenWhileRecording, isFalse);
    await tester.tap(find.text('Dim screen while recording'));
    await tester.pumpAndSettle();
    expect(prefs.dimScreenWhileRecording, isTrue);
  });

  testWidgets('is disabled while keep-screen-on is off', (tester) async {
    SharedPreferences.setMockInitialValues({'keep_screen_on': false});
    final prefs = Preferences();
    await prefs.init();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Dim screen while recording'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(_dimTile().onChanged, isNull);
  });
}
