import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// StatGrid guard (issue #666 V8 / § 502). Every assertion here is a
/// *derivation* — that the column count falls out of the width a cell needs at
/// the current text scale — never an absolute fit: `flutter_test`'s font is
/// fixed-advance, so a claim that some value fits some width cannot be made in
/// CI (§ 500).
Future<List<double>> _widths(
  WidgetTester tester, {
  required int cells,
  required double width,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: StatGrid(
                cells: [
                  for (var i = 0; i < cells; i++)
                    StatTile.small(
                      icon: Icons.timer,
                      label: 'S$i',
                      value: '$i',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return [
    for (var i = 0; i < cells; i++)
      tester
          .getSize(
            find
                .ancestor(of: find.text('S$i'), matching: find.byType(SizedBox))
                .first,
          )
          .width,
  ];
}

void main() {
  testWidgets('an empty grid occupies nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatGrid(cells: [])),
      ),
    );
    expect(tester.getSize(find.byType(StatGrid)), Size.zero);
  });

  testWidgets('four cells that fit lay out exactly as a Row of Expanded did', (tester) async {
    final widths = await _widths(tester, cells: 4, width: 360);
    expect(widths, everyElement(90.0));
    // One run, so the grid is exactly as tall as a cell — no runSpacing paid.
    final cell = tester
        .getSize(
          find
              .ancestor(of: find.text('S0'), matching: find.byType(SizedBox))
              .first,
        )
        .height;
    expect(tester.getSize(find.byType(StatGrid)).height, cell);
  });

  testWidgets('eight cells reflow instead of dividing the row eight ways', (tester) async {
    final widths = await _widths(tester, cells: 8, width: 360);
    // A Row of eight Expanded gave 45 dp each here. The grid caps at four
    // columns, so each cell keeps a quarter of the row and the eight land on
    // two runs.
    expect(widths, everyElement(90.0));
    expect(widths.every((w) => w >= kStatCellMinWidth), isTrue);
  });

  testWidgets('the column count is derived from the text scale, so a cell '
      'grows by the factor the glyphs did', (tester) async {
    final at1 = await _widths(tester, cells: 8, width: 360);
    final at2 = await _widths(tester, cells: 8, width: 360, textScale: 2.0);
    expect(at2.first, at1.first * 2);
    expect(at2.first, greaterThanOrEqualTo(kStatCellMinWidth * 2));
  });

  testWidgets('a cell never falls below the floor, even one cell per row', (tester) async {
    final widths = await _widths(tester, cells: 4, width: 100);
    expect(widths, everyElement(100.0));
  });

  testWidgets('every cell is bounded, so a hero value shrinks rather than '
      'bursting the run', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: StatGrid(
                cells: [
                  StatTile.large(
                    label: 'Distance',
                    value: '1234.56',
                    unit: 'km',
                  ),
                  StatTile.large(label: 'Time', value: '104:32:11'),
                  StatTile.large(label: 'Pace', value: '12:34', unit: '/km'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('104:32:11'), findsOneWidget);
  });
}
