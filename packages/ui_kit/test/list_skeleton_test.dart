import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
}) =>
    tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

void main() {
  testWidgets('renders one placeholder row per requested row', (tester) async {
    await _pump(tester, const ListSkeleton(label: 'Loading…', rows: 4));
    // Leading disc + two bars per row.
    expect(find.byType(FractionallySizedBox), findsNWidgets(8));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('announces itself to a screen reader', (tester) async {
    await _pump(tester, const ListSkeleton(label: 'Loading clubs…', rows: 2));
    expect(find.bySemanticsLabel('Loading clubs…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('drops the leading disc when the list has no leading column',
      (tester) async {
    await _pump(
      tester,
      const ListSkeleton(label: 'Loading…', rows: 3, hasLeading: false),
    );
    expect(find.byType(FractionallySizedBox), findsNWidgets(6));
    // Only the bars remain — no circular leading block.
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => (c.decoration as BoxDecoration?)?.shape == BoxShape.circle);
    expect(circles, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('holds a static pose under reduced motion', (tester) async {
    await _pump(
      tester,
      const ListSkeleton(label: 'Loading…', rows: 2),
      reduceMotion: true,
    );
    Color barColor() => (tester
            .widget<Container>(find
                .descendant(
                  of: find.byType(FractionallySizedBox),
                  matching: find.byType(Container),
                )
                .first)
            .decoration as BoxDecoration)
        .color!;
    final first = barColor();
    await tester.pump(const Duration(milliseconds: 450));
    expect(barColor(), first);
  });

  testWidgets('does not scroll — it stands in for content, it is not content',
      (tester) async {
    await _pump(tester, const ListSkeleton(label: 'Loading…', rows: 20));
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.physics, isA<NeverScrollableScrollPhysics>());
    await tester.pump(const Duration(milliseconds: 400));
  });
}
