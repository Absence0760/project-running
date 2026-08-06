import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(WidgetTester tester, Widget pill,
    {double textScale = 1.0, double width = 400}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: Align(
            alignment: Alignment.topLeft, child: pill)),
        ),
      ),
    ),
  ));
  await tester.pump();
}

EdgeInsets _paddingOf(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(of: find.byType(StatusPill), matching: find.byType(Container))
        .first,
  );
  return container.padding! as EdgeInsets;
}

double _fontSizeOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.fontSize!;

void main() {
  test('a pill leads with a dot or an icon, never both', () {
    expect(
        () => StatusPill(
            label: 'x',
            foreground: const Color(0xFF000000),
            dot: true,
            icon: Icons.check),
        throwsAssertionError);
  });

  testWidgets('the padding follows the size, and so does the type step',
      (tester) async {
    await _pump(
        tester,
        const StatusPill(
            label: 'Live',
            foreground: Color(0xFF2E6B3C),
            size: StatusPillSize.compact));
    expect(_paddingOf(tester),
        const EdgeInsets.symmetric(horizontal: 8, vertical: 2));
    expect(_fontSizeOf(tester, 'Live'), 11);

    await _pump(
        tester,
        const StatusPill(
            label: 'Live',
            foreground: Color(0xFF2E6B3C),
            size: StatusPillSize.standard));
    expect(_paddingOf(tester),
        const EdgeInsets.symmetric(horizontal: 10, vertical: 4));
    expect(_fontSizeOf(tester, 'Live'), 12);
  });

  testWidgets('standard is the default, so a call site cannot pick a padding '
      'without picking a size', (tester) async {
    await _pump(tester,
        const StatusPill(label: 'Live', foreground: Color(0xFF2E6B3C)));
    expect(_paddingOf(tester),
        const EdgeInsets.symmetric(horizontal: 10, vertical: 4));
  });

  testWidgets('the leading glyph is derived from the label size',
      (tester) async {
    for (final (size, expected) in [
      (StatusPillSize.compact, 13.0),
      (StatusPillSize.standard, 14.0),
    ]) {
      await _pump(
          tester,
          StatusPill(
              label: 'Due',
              foreground: const Color(0xFF8A5712),
              icon: Icons.warning_amber,
              size: size));
      expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber)).size,
          expected);
    }
  });

  testWidgets('the dot is two thirds of the label and takes the foreground',
      (tester) async {
    await _pump(
        tester,
        const StatusPill(
            label: 'Live', foreground: Color(0xFF2E6B3C), dot: true));
    final dot = tester.widget<Container>(
      find
          .descendant(of: find.byType(StatusPill), matching: find.byType(Container))
          .at(1),
    );
    expect(tester.getSize(find.byWidget(dot)), const Size(8, 8));
    expect((dot.decoration! as BoxDecoration).color, const Color(0xFF2E6B3C));
  });

  testWidgets('a long label ellipsizes instead of bursting its row',
      (tester) async {
    await _pump(
      tester,
      const StatusPill(
          label: 'Ein sehr langer Statustext der nicht passt',
          foreground: Color(0xFF2E6B3C)),
      textScale: 2.0,
      width: 160,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(StatusPill)).width,
        lessThanOrEqualTo(160.0));
    expect(tester.widget<Text>(find.textContaining('Ein sehr')).overflow,
        TextOverflow.ellipsis);
  });

  testWidgets('an unfilled pill carries an outline instead', (tester) async {
    await _pump(
        tester,
        const StatusPill(
            label: 'Private',
            foreground: Color(0xFF49454E),
            outline: Color(0xFF8A806A)));
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(StatusPill), matching: find.byType(Container))
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect((decoration.border! as Border).top.color, const Color(0xFF8A806A));
  });
}
