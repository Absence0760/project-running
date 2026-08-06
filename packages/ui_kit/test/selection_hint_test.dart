import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  const label = 'Appuyez longuement sur un itinéraire pour en '
      'sélectionner plusieurs';

  Future<void> pump(WidgetTester tester,
      {double scale = 1.0, double width = 320}) async {
    await tester.binding.setSurfaceSize(Size(width, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: SelectionHint(label: label)),
    ));
    await tester.pump();
  }

  testWidgets('renders the caller-supplied label at the labelSmall floor',
      (tester) async {
    await pump(tester);
    expect(find.text(label), findsOneWidget);
    final style = tester.widget<Text>(find.byType(Text)).style;
    final floor = Theme.of(tester.element(find.byType(SelectionHint)))
        .textTheme
        .labelSmall;
    expect(style?.fontSize, floor?.fontSize);
    expect(floor?.fontSize, 11, reason: 'the §482 micro-label floor moved');
  });

  testWidgets('reflows rather than clipping when the text scale doubles',
      (tester) async {
    await pump(tester, scale: 1.0);
    // Read the scalars, not the RenderObject: pumpWidget reuses the element
    // tree, so holding the render object would hand back the 2.0x layout.
    final onex = tester.renderObject<RenderParagraph>(find.byType(Text));
    final oneLineHeight = onex.preferredLineHeight;
    final oneLines = onex.size.height / oneLineHeight;

    await pump(tester, scale: 2.0);
    final twox = tester.renderObject<RenderParagraph>(find.byType(Text));

    // The derivation, not a width (§500): the glyphs doubled, so the label
    // needs proportionally more lines in the same lane. Nothing is lost — a
    // fixed box would have held its height and painted over its neighbour.
    expect(twox.preferredLineHeight, greaterThan(oneLineHeight * 1.9));
    expect(twox.size.height / twox.preferredLineHeight,
        greaterThan(oneLines));
    expect(twox.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });
}
