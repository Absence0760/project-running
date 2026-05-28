import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/training_service.dart';

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: PlanNewScreen(training: TrainingService()),
    ),
  );
}

void main() {
  group('PlanNewScreen — initial render', () {
    testWidgets('renders the New plan app-bar title', (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(find.text('New plan'), findsOneWidget);
    });

    testWidgets('renders the Start date list tile', (tester) async {
      // Reason: the start date is the anchor for the whole generated
      // plan — its picker tile must be present so users can shift it.
      await _pump(tester);
      await tester.pump();
      expect(find.text('Start date'), findsOneWidget);
    });

    testWidgets('renders the Cancel and Create plan buttons',
        (tester) async {
      // Reason: the wizard is committed only via "Create plan"; the
      // Cancel pop must remain reachable so users can back out.
      // The buttons live at the bottom of a lazy ListView — scroll to
      // bring them into the viewport before asserting.
      await _pump(tester);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Create plan'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create plan'), findsOneWidget);
    });
  });

  group('PlanNewScreen — recent-5K recency gate (comeback persona #24)', () {
    final warnFinder = find.textContaining('too fast for a returning runner');
    final confirmFinder = find.textContaining('reflects my current fitness');

    testWidgets('no confirm checkbox or warning until a 5K time is entered',
        (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(confirmFinder, findsNothing);
      expect(warnFinder, findsNothing);
    });

    testWidgets('entering a 5K time surfaces the confirm box + warning',
        (tester) async {
      // Reason: a returning runner typing an old PR must be told the time
      // isn't trusted until confirmed, and that unconfirmed leaves paces on
      // the conservative goal-based estimate — otherwise the engine would
      // prescribe dangerously fast paces.
      await _pump(tester);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'min').last,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.widgetWithText(TextField, 'min').last, '22');
      await tester.pump();
      expect(confirmFinder, findsOneWidget);
      expect(warnFinder, findsOneWidget);
    });

    testWidgets('ticking the confirm box clears the warning', (tester) async {
      await _pump(tester);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'min').last,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.widgetWithText(TextField, 'min').last, '22');
      await tester.pump();
      // Tap the tile title (the raw Checkbox sits below the fold); the
      // CheckboxListTile toggles from a tap anywhere on the tile.
      await tester.ensureVisible(confirmFinder);
      await tester.pump();
      await tester.tap(confirmFinder);
      await tester.pump();
      expect(warnFinder, findsNothing);
    });
  });
}
