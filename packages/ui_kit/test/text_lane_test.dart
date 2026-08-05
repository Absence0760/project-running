import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<Size> _pump(
  WidgetTester tester, {
  required double scale,
  required Widget child,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [TextLane(width: 40, child: child)],
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(TextLane));
}

void main() {
  testWidgets('lane width tracks the OS text scale', (tester) async {
    // A zero-width child leaves the floor as the only term, so the derivation
    // is read directly. Deliberately not an absolute fit claim: the assertion
    // is that the lane grew by the same factor as the glyphs would have.
    const child = SizedBox.shrink();
    expect(await _pump(tester, scale: 1.0, child: child), const Size(40, 0));
    expect(await _pump(tester, scale: 1.5, child: child), const Size(60, 0));
    expect(await _pump(tester, scale: 2.0, child: child), const Size(80, 0));
  });

  testWidgets('a child wider than the floor widens the lane, never crops',
      (tester) async {
    final size = await _pump(
      tester,
      scale: 1.0,
      child: const SizedBox(width: 137, height: 10),
    );
    expect(size.width, 137);
  });

  testWidgets('the floor still applies once the scale outruns the child',
      (tester) async {
    final size = await _pump(
      tester,
      scale: 2.0,
      child: const SizedBox(width: 50, height: 10),
    );
    expect(size.width, 80);
  });

  testWidgets('a bounded parent caps the lane rather than overflowing it',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 25,
              child: TextLane(width: 40, child: Container(height: 10)),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(TextLane)).width, 25);
  });
}
