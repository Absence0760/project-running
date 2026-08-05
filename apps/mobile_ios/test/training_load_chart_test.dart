import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_load.dart';
import '../lib/widgets/training_load_chart.dart'
    show
        TrainingLoadChart,
        trainingLoadFatigueColour,
        trainingLoadFitnessColour,
        trainingLoadFormColour;

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
}) {
  return tester.pumpWidget(
    MaterialApp(
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
      testWidgets('Form legend swatch matches the plotted line at tsb=$tsb',
          (tester) async {
        await _pump(
          tester,
          points: [
            _point(date: DateTime(2026, 4, 1), atl: 35, ctl: 40, tsb: tsb),
            _point(date: DateTime(2026, 4, 2), atl: 36, ctl: 41, tsb: tsb),
          ],
          hasHr: true,
        );
        expect(_swatchColours(tester), <Color>[
          trainingLoadFitnessColour,
          trainingLoadFatigueColour,
          trainingLoadFormColour,
        ]);
        expect(
          find.byKey(const Key('trainingLoadChartPainter')),
          paints
            ..path(color: trainingLoadFitnessColour)
            ..path(color: trainingLoadFatigueColour)
            ..path(color: trainingLoadFormColour),
        );
      });
    }

    testWidgets('the three series hues are mutually distinct', (tester) async {
      expect(
        <Color>{
          trainingLoadFitnessColour,
          trainingLoadFatigueColour,
          trainingLoadFormColour,
        }.length,
        3,
      );
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
