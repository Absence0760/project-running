import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_android/goals.dart';
import 'package:mobile_android/preferences.dart';
import 'package:mobile_android/widgets/goal_editor_sheet.dart';

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pumpSheet(
  WidgetTester tester,
  Preferences prefs, {
  RunGoal? existing,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showGoalEditorSheet(
              ctx,
              preferences: prefs,
              existing: existing,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('GoalEditorSheet', () {
    testWidgets('shows "New goal" title when no existing goal supplied',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      expect(find.text('New goal'), findsOneWidget);
    });

    testWidgets(
        'shows "Edit goal" title and pre-populates distance from existing goal',
        (tester) async {
      final prefs = await _makePrefs();
      final goal = RunGoal(
        id: 'g1',
        period: GoalPeriod.week,
        distanceMetres: 40000,
      );
      await _pumpSheet(tester, prefs, existing: goal);
      expect(find.text('Edit goal'), findsOneWidget);
      // 40 km distance pre-populated in the distance field.
      expect(find.text('40.0'), findsOneWidget);
    });

    testWidgets('shows validation error when no target is set on save',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Set at least one target'), findsOneWidget);
    });

    testWidgets('shows validation error when distance is zero or negative',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      // The distance TextField has hint text '-'. Use the suffix 'km' to
      // distinguish it from the other target fields.
      final distanceField = find.ancestor(
        of: find.textContaining('km'),
        matching: find.byType(TextField),
      );
      await tester.enterText(distanceField.first, '0');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Distance: enter a positive number'), findsOneWidget);
    });

    testWidgets('Cancel button dismisses the sheet without saving',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      expect(find.text('New goal'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('New goal'), findsNothing);
      expect(prefs.goals, isEmpty);
    });
  });
}
