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
}
