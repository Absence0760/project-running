import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_load.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/widgets/training_load_chart.dart'
    show TrainingLoadChart, trainingLoadTickStep;

TrainingLoadPoint _point({
  required DateTime date,
  double stress = 0,
  double atl = 0,
  double ctl = 0,
  double tsb = 0,
}) =>
    TrainingLoadPoint(
      date: date,
      stress: stress,
      atl: atl,
      ctl: ctl,
      tsb: tsb,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<TrainingLoadPoint> points,
  required bool hasHr,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TrainingLoadChart(points: points, hasHr: hasHr),
      ),
    ),
  );
}

void main() {
  group('TrainingLoadChart', () {
    testWidgets('renders the chart heading', (tester) async {
      await _pump(tester, points: const [], hasHr: false);
      expect(find.text('Fitness, Fatigue & Form'), findsOneWidget);
    });

    testWidgets('shows the empty hint when points is empty', (tester) async {
      await _pump(tester, points: const [], hasHr: false);
      expect(
        find.text('Record a few runs to see your fitness trend.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'subtitle reads "Volume-based" when hasHr is false (no HR strap)',
        (tester) async {
      await _pump(tester, points: const [], hasHr: false);
      expect(find.textContaining('Volume-based'), findsOneWidget);
    });

    testWidgets(
        'subtitle reads "Heart-rate TRIMP" when hasHr is true',
        (tester) async {
      await _pump(
        tester,
        points: [
          _point(date: DateTime(2026, 4, 1)),
        ],
        hasHr: true,
      );
      expect(find.textContaining('Heart-rate TRIMP'), findsOneWidget);
    });

    testWidgets('renders the legend keys when points are non-empty',
        (tester) async {
      await _pump(
        tester,
        points: [
          _point(
            date: DateTime(2026, 4, 1),
            stress: 50,
            atl: 35,
            ctl: 40,
            tsb: 5,
          ),
        ],
        hasHr: true,
      );
      // Legend renders "Fitness · 40", "Fatigue · 35", "Form · 5".
      // Use the " · " separator to disambiguate from the
      // "Fitness, Fatigue & Form" heading.
      expect(find.text('Fitness · 40'), findsOneWidget);
      expect(find.text('Fatigue · 35'), findsOneWidget);
      expect(find.text('Form · 5'), findsOneWidget);
    });

    // Issue #666 round 2: the legend recoloured Form by the sign of the
    // last TSB while the painter drew it in a fixed red, so a tapered
    // runner (TSB >= 0 — the state the card exists to celebrate) saw a
    // green key above a red line. Legend and plot now read one constant.
    for (final tsb in const [12.0, -12.0]) {
      for (final entry in {
        'light': (AppTheme.light, ChartPalette.light),
        'dark': (AppTheme.dark, ChartPalette.dark),
      }.entries) {
        testWidgets(
            'Form legend swatch matches the plotted line at tsb=$tsb '
            'in ${entry.key}', (tester) async {
          final (theme, palette) = entry.value;
          final series = palette.series;
          await _pump(
            tester,
            theme: theme,
            points: [
              _point(date: DateTime(2026, 4, 1), atl: 35, ctl: 40, tsb: tsb),
              _point(date: DateTime(2026, 4, 2), atl: 36, ctl: 41, tsb: tsb),
            ],
            hasHr: true,
          );
          expect(_swatchColours(tester), series);
          expect(
            find.byKey(const Key('trainingLoadChartPainter')),
            paints
              ..path(color: series[0])
              ..path(color: series[1])
              ..path(color: series[2]),
          );
        });
      }
    }

    // The series values, their 3:1 floors on each card and the luminance
    // ladder between them are pinned once in
    // packages/ui_kit/test/chart_palette_test.dart, where the palette lives.
    testWidgets('the header is the shared chart eyebrow', (tester) async {
      await _pump(tester, points: const [], hasHr: false);
      expect(
        find.ancestor(
          of: find.text('Fitness, Fatigue & Form'),
          matching: find.byType(ChartCardHeader),
        ),
        findsOneWidget,
      );
    });
  });

  group('trainingLoadTickStep', () {
    // The plot is min/max-normalised, so without labelled ticks CTL 45 and
    // CTL 450 render pixel-identically. The step ladder is what turns the
    // shape back into a magnitude.
    test('walks the 1 / 2 / 5 x 10^n ladder', () {
      expect(trainingLoadTickStep(4), 1);
      expect(trainingLoadTickStep(40), 10);
      expect(trainingLoadTickStep(60), 20);
      expect(trainingLoadTickStep(160), 50);
      expect(trainingLoadTickStep(400), 100);
    });

    test('never returns a non-positive step for a degenerate span', () {
      expect(trainingLoadTickStep(0), greaterThan(0));
      expect(trainingLoadTickStep(-5), greaterThan(0));
      expect(trainingLoadTickStep(double.nan), greaterThan(0));
    });

    test('keeps the tick count at or under the cap', () {
      for (final span in [3.0, 9.0, 37.0, 128.0, 501.0, 4321.0]) {
        final step = trainingLoadTickStep(span);
        expect((span / step).floor() + 1, lessThanOrEqualTo(6),
            reason: 'span $span produced too many ticks at step $step');
      }
    });
  });
}

/// Fill colours of the three 12x12 legend swatches, in render order.
List<Color> _swatchColours(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where((c) =>
        c.constraints == BoxConstraints.tightFor(width: 12, height: 12))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .map((d) => d.color!)
    .toList();
