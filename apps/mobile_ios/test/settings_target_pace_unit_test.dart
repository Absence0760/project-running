// The Target pace row reads its value back through the runner's distance
// unit, so the editor behind it has to collect it in that unit too. It used to
// store the typed minutes:seconds verbatim as seconds per KM regardless: a
// miles runner who set 8:00 got a 8:00/km target (a 4:58/mi pace the off-pace
// cue then held them to) and a row that immediately read 12:52 /mi.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

Future<Preferences> _setUp(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(WidgetTester tester, Preferences prefs) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: null),
    ),
  );
}

Future<void> _openTargetPace(WidgetTester tester) async {
  final row = find.ancestor(
    of: find.text('Target pace'),
    matching: find.byType(ListTile),
  );
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(row, 250, scrollable: scrollable);
  // scrollUntilVisible stops with the row still under the pinned section
  // header, which eats the tap.
  await tester.drag(scrollable, const Offset(0, 220));
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Finder _field(int index) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ).at(index);

Future<void> _enter(WidgetTester tester, int minutes, int seconds) async {
  await tester.enterText(_field(0), '$minutes');
  await tester.enterText(_field(1), seconds.toString().padLeft(2, '0'));
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  test('the two pace conversions are inverses within the unit', () {
    expect(UnitFormat.paceSecPerUnit(300, DistanceUnit.km), 300);
    expect(UnitFormat.paceSecPerKm(300, DistanceUnit.km), 300);
    expect(
      UnitFormat.paceSecPerUnit(300, DistanceUnit.mi),
      closeTo(482.8, 0.1),
    );
    expect(
      UnitFormat.paceSecPerKm(482.8, DistanceUnit.mi),
      closeTo(300, 0.1),
    );
  });

  testWidgets('a metric runner stores the pace they typed', (tester) async {
    final prefs = await _setUp({'use_miles': false});
    await _pump(tester, prefs);
    await _openTargetPace(tester);
    await _enter(tester, 5, 30);

    expect(prefs.targetPaceSecPerKm, 330);
    expect(find.textContaining('5:30 /km'), findsOneWidget);
  });

  testWidgets('an imperial runner stores a per-mile pace as seconds per km',
      (tester) async {
    final prefs = await _setUp({'use_miles': true});
    await _pump(tester, prefs);
    await _openTargetPace(tester);
    await _enter(tester, 8, 0);

    expect(prefs.targetPaceSecPerKm, 298);
    expect(find.textContaining('8:00 /mi'), findsOneWidget);
  });

  testWidgets('the editor prefills in the unit the row displays',
      (tester) async {
    final prefs = await _setUp({
      'use_miles': true,
      'target_pace_sec_per_km': 298,
    });
    await _pump(tester, prefs);
    await _openTargetPace(tester);

    expect(tester.widget<TextField>(_field(0)).controller!.text, '8');
    expect(tester.widget<TextField>(_field(1)).controller!.text, '0');
  });

  testWidgets('Clear turns the target off in either unit', (tester) async {
    final prefs = await _setUp({
      'use_miles': true,
      'target_pace_sec_per_km': 298,
    });
    await _pump(tester, prefs);
    await _openTargetPace(tester);
    await tester.tap(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Clear')),
    );
    await tester.pumpAndSettle();

    expect(prefs.targetPaceSecPerKm, 0);
  });
}
