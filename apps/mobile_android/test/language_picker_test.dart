// Widget test for the Settings > Preferences language picker (A4). Mirrors
// web's "picking a language re-renders the shell" e2e: tapping a language
// flips the global localeNotifier and persists the choice to Preferences.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/main.dart' show localeNotifier;
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(WidgetTester tester, Preferences prefs) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        preferences: prefs,
        settingsSync: null,
      ),
    ),
  );
}

void main() {
  setUp(() => localeNotifier.value = null);
  tearDown(() => localeNotifier.value = null);

  testWidgets('shows the Language row with the System-default subtitle',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('picking Deutsch flips localeNotifier and persists the choice',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    // The radio sheet lists every endonym.
    expect(find.text('Deutsch'), findsOneWidget);
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(localeNotifier.value, const Locale('de'));
    expect(prefs.locale, const Locale('de'));
    // The row subtitle now reflects the chosen endonym.
    expect(find.text('Deutsch'), findsOneWidget);
  });

  testWidgets('selecting System default clears an existing override',
      (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'ja'});
    final prefs = Preferences();
    await prefs.init();
    localeNotifier.value = const Locale('ja');
    await _pump(tester, prefs);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();

    expect(localeNotifier.value, isNull);
    expect(prefs.locale, isNull);
  });
}
