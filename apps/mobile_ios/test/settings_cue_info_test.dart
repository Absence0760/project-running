// Widget tests for the cue-preferences overhaul on
// settings_preferences_screen.dart: the per-cue "info" buttons open an
// explainer dialog, the Target-pace + Splits-announce tiles carry the same
// affordance, and the Splits-announce selector writes the device-local
// SplitPaceMode pref.

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

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

/// Scrolls until [text] is on screen, then fully reveals [target] so a tap
/// lands on it (a bottom-edge tile whose centre is off-screen otherwise
/// swallows the tap — see the sibling settings tests).
Future<void> _reveal(
    WidgetTester tester, String text, Finder target) async {
  await tester.scrollUntilVisible(
    find.text(text),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets("a cue row's info button opens a dialog with that cue's help",
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    final infoBtn = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Off-route warning'),
      matching: find.byIcon(Icons.info_outline),
    );
    await _reveal(tester, 'Off-route warning', infoBtn);
    expect(infoBtn, findsOneWidget);

    await tester.tap(infoBtn);
    await tester.pumpAndSettle();

    // The dialog body carries the cue's spoken-example explainer.
    expect(
      find.textContaining('Only works when you start a run with a saved route'),
      findsOneWidget,
    );
  });

  testWidgets('the Target pace tile info button opens the target-pace help',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    final infoBtn = find.descendant(
      of: find.widgetWithText(ListTile, 'Target pace'),
      matching: find.byIcon(Icons.info_outline),
    );
    await _reveal(tester, 'Target pace', infoBtn);
    expect(infoBtn, findsOneWidget);

    await tester.tap(infoBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('The pace you'), findsOneWidget);
  });

  testWidgets('the Splits announce tile info button opens the split-mode help',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    final infoBtn = find.descendant(
      of: find.widgetWithText(ListTile, 'Splits announce'),
      matching: find.byIcon(Icons.info_outline),
    );
    await _reveal(tester, 'Splits announce', infoBtn);
    expect(infoBtn, findsOneWidget);

    await tester.tap(infoBtn);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('At each split, choose what pace you hear'),
      findsOneWidget,
    );
  });

  testWidgets('Splits announce shows the current mode and defaults to Split',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, 'Splits announce');
    await _reveal(tester, 'Splits announce', tile);
    // Default mode is `split`, so the subtitle reads "Split pace".
    expect(
      find.descendant(of: tile, matching: find.text('Split pace')),
      findsOneWidget,
    );
  });

  testWidgets('picking Average pace writes SplitPaceMode.average',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, 'Splits announce');
    await _reveal(tester, 'Splits announce', tile);
    expect(prefs.splitPaceMode, SplitPaceMode.split);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    // The radio dialog is open; pick "Average pace".
    await tester.tap(find.text('Average pace'));
    await tester.pumpAndSettle();

    expect(prefs.splitPaceMode, SplitPaceMode.average);
  });
}
