import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  Widget host(ActivityLoaderKind kind,
          {double size = 76, String label = 'Chargement…'}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
              child: ActivityLoader(kind: kind, size: size, label: label)),
        ),
      );

  for (final kind in ActivityLoaderKind.values) {
    testWidgets('renders + animates without throwing: ${kind.name}',
        (tester) async {
      await tester.pumpWidget(host(kind));

      expect(find.byType(ActivityLoader), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // Advance the repeating controller across several frames; the painter is
      // evaluated at each tick and must not throw for any t.
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.takeException(), isNull);
      expect(find.byType(ActivityLoader), findsOneWidget);
    });
  }

  testWidgets('sizes the figure at the 120:170 aspect ratio', (tester) async {
    await tester.pumpWidget(host(ActivityLoaderKind.run, size: 120));
    final size = tester.getSize(find.byType(ActivityLoader));
    expect(size.width, 120);
    expect(size.height, closeTo(170, 0.01));
  });

  testWidgets('announces the caller-supplied label verbatim', (tester) async {
    await tester.pumpWidget(
        host(ActivityLoaderKind.fuel, label: 'Cargando actividades'));
    expect(find.bySemanticsLabel('Cargando actividades'), findsOneWidget);
    // The one thing a locale-free package must never announce.
    expect(find.bySemanticsLabel('Loading'), findsNothing);
  });

  testWidgets('paints the rest pose when animations are disabled',
      (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
                child: ActivityLoader(
                    kind: ActivityLoaderKind.train, label: 'Wird geladen…')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('FullBodyLoader centres the figure and carries its label',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FullBodyLoader(
          kind: ActivityLoaderKind.run,
          label: 'Chargement…',
        ),
      ),
    ));
    expect(find.bySemanticsLabel('Chargement…'), findsOneWidget);
    final loader = tester.widget<ActivityLoader>(find.byType(ActivityLoader));
    expect(loader.size, 76);
    expect(find.ancestor(of: find.byType(ActivityLoader),
        matching: find.byType(Center)), findsWidgets);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
