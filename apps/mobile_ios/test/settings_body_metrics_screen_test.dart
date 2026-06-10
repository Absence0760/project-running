import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_body_metrics_screen.dart';

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, Preferences prefs) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // api + settingsSync null: no Supabase round-trips, exercises the
      // consent-gate UI offline.
      home: SettingsBodyMetricsScreen(
        api: null,
        settingsSync: null,
        preferences: prefs,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SettingsBodyMetricsScreen', () {
    testWidgets('consent off by default — height & weight fields are hidden',
        (tester) async {
      await _pump(tester, await _prefs());
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Height'), findsNothing);
      expect(find.text('Weight'), findsNothing);
    });

    testWidgets('turning on consent reveals the height + weight inputs',
        (tester) async {
      await _pump(tester, await _prefs());
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
    });

    testWidgets('activity level + goal show defaults and open a picker',
        (tester) async {
      await _pump(tester, await _prefs());
      // Defaults: moderate activity, maintain goal. Activity labels describe
      // the non-exercise baseline (logged workouts are added on top).
      expect(find.text('Moderately active (on your feet often)'), findsOneWidget);
      expect(find.text('Maintain weight'), findsOneWidget);

      await tester.tap(find.text('Activity level'));
      await tester.pumpAndSettle();
      // The picker lists all five activity levels.
      expect(find.text('Mostly sitting (desk job)'), findsOneWidget);
      expect(find.text('Lightly active (light daily movement)'), findsOneWidget);
      expect(find.text('Extremely active (hard physical labour)'), findsOneWidget);
    });
  });
}
