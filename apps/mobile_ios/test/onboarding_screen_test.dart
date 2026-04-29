import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/preferences.dart';
import '../lib/screens/onboarding_screen.dart';

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  VoidCallback? onDone,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: OnboardingScreen(
        preferences: prefs,
        onDone: onDone ?? () {},
      ),
    ),
  );
}

void main() {
  group('OnboardingScreen', () {
    testWidgets('renders the first page title and description',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      expect(find.text('Track every run'), findsOneWidget);
      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('first-page CTA reads "Next"', (tester) async {
      // Reason: only the final page swaps to "Grant permission" — if
      // the first page already says that, the location prompt would
      // fire too early.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Grant permission'), findsNothing);
    });

    testWidgets('renders three page indicator dots', (tester) async {
      // Reason: the indicator row is generated from the _pages list —
      // 3 dots means the three onboarding pages are still wired up.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      expect(find.byType(AnimatedContainer), findsNWidgets(3));
    });

    testWidgets('tapping Next advances to the second page', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Follow routes'), findsOneWidget);
      expect(find.byIcon(Icons.route), findsOneWidget);
    });

    testWidgets('the final page swaps the CTA to "Grant permission"',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      // Advance to page 2.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Advance to page 3 (last).
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Grant permission'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Location access'), findsOneWidget);
    });
  });
}
