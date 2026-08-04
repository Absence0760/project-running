import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('renders icon, title, body, and CTA', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      EmptyState(
        icon: Icons.fitness_center,
        title: 'No workouts yet',
        body: 'Log your first session to see it here.',
        ctaLabel: 'Log workout',
        onCta: () => taps++,
      ),
    );
    expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    expect(find.text('No workouts yet'), findsOneWidget);
    expect(find.text('Log your first session to see it here.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log workout'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Log workout'));
    expect(taps, 1);
  });

  testWidgets('uses ErrorState proportions: icon 48, padding 32, '
      'titleMedium + bodySmall', (tester) async {
    await _pump(
      tester,
      const EmptyState(
        icon: Icons.restaurant,
        title: 'Nothing logged',
        body: 'Meals appear here.',
      ),
    );
    final context = tester.element(find.text('Nothing logged'));
    final theme = Theme.of(context);
    expect(tester.widget<Icon>(find.byIcon(Icons.restaurant)).size, 48);
    final padding = tester.widget<Padding>(
      find.ancestor(of: find.text('Nothing logged'),
          matching: find.byType(Padding)).first,
    );
    expect(padding.padding, const EdgeInsets.all(32));
    expect(tester.widget<Text>(find.text('Nothing logged')).style,
        theme.textTheme.titleMedium);
    expect(tester.widget<Text>(find.text('Meals appear here.')).style?.fontSize,
        theme.textTheme.bodySmall?.fontSize);
  });

  testWidgets('omits body and CTA when not provided', (tester) async {
    await _pump(
      tester,
      const EmptyState(icon: Icons.flag_outlined, title: 'No races'),
    );
    expect(find.text('No races'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('fills and centres under bounded height, scrollable for '
      'pull-to-refresh hosts', (tester) async {
    await _pump(
      tester,
      const EmptyState(icon: Icons.flag_outlined, title: 'Centred'),
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final surface = tester.getRect(find.byType(EmptyState));
    final title = tester.getCenter(find.text('Centred'));
    expect((title.dy - surface.center.dy).abs(), lessThan(40));
  });

  testWidgets('renders without an inner scrollable under unbounded height',
      (tester) async {
    await _pump(
      tester,
      ListView(
        children: const [
          SizedBox(height: 100),
          EmptyState(icon: Icons.restaurant, title: 'Inline empty'),
        ],
      ),
    );
    expect(find.text('Inline empty'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });
}
