import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/widgets/collapsible_panel.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool initiallyExpanded = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: CollapsiblePanel(
                initiallyExpanded: initiallyExpanded,
                expandedChild: const Text('expanded content'),
                collapsedChild: const Text('collapsed content'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('CollapsiblePanel', () {
    testWidgets('shows expandedChild when initiallyExpanded is true',
        (tester) async {
      await _pump(tester, initiallyExpanded: true);
      await tester.pumpAndSettle();
      expect(find.text('expanded content'), findsOneWidget);
    });

    testWidgets('shows collapsedChild when initiallyExpanded is false',
        (tester) async {
      await _pump(tester, initiallyExpanded: false);
      await tester.pumpAndSettle();
      expect(find.text('collapsed content'), findsOneWidget);
    });

    testWidgets('tapping the drag handle toggles from expanded to collapsed',
        (tester) async {
      await _pump(tester, initiallyExpanded: true);
      await tester.pumpAndSettle();

      // The Semantics node for the handle has a label we can find.
      final handleFinder = find.bySemanticsLabel('Collapse stats panel');
      expect(handleFinder, findsOneWidget);
      await tester.tap(handleFinder);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Expand stats panel'), findsOneWidget);
    });

    testWidgets('tapping the drag handle toggles from collapsed to expanded',
        (tester) async {
      await _pump(tester, initiallyExpanded: false);
      await tester.pumpAndSettle();

      final handleFinder = find.bySemanticsLabel('Expand stats panel');
      expect(handleFinder, findsOneWidget);
      await tester.tap(handleFinder);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Collapse stats panel'), findsOneWidget);
    });

    testWidgets('drag handle has button semantics for accessibility',
        (tester) async {
      await _pump(tester, initiallyExpanded: true);
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.bySemanticsLabel('Collapse stats panel'),
      );
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    });
  });
}
