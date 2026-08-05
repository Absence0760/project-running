import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_load.dart';
import 'dart:math' as math;

import 'package:ui_kit/ui_kit.dart';

import '../lib/widgets/training_load_chart.dart'
    show TrainingLoadChart, TrainingLoadPalette, trainingLoadTickStep;

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

double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  // ignore: deprecated_member_use
  return 0.2126 * chan(c.red.toDouble()) +
      // ignore: deprecated_member_use
      0.7152 * chan(c.green.toDouble()) +
      // ignore: deprecated_member_use
      0.0722 * chan(c.blue.toDouble());
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
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
        'light': (AppTheme.light, TrainingLoadPalette.light),
        'dark': (AppTheme.dark, TrainingLoadPalette.dark),
      }.entries) {
        testWidgets(
            'Form legend swatch matches the plotted line at tsb=$tsb '
            'in ${entry.key}', (tester) async {
          final (theme, palette) = entry.value;
          await _pump(
            tester,
            theme: theme,
            points: [
              _point(date: DateTime(2026, 4, 1), atl: 35, ctl: 40, tsb: tsb),
              _point(date: DateTime(2026, 4, 2), atl: 36, ctl: 41, tsb: tsb),
            ],
            hasHr: true,
          );
          expect(_swatchColours(tester), <Color>[
            palette.fitness,
            palette.fatigue,
            palette.form,
          ]);
          expect(
            find.byKey(const Key('trainingLoadChartPainter')),
            paints
              ..path(color: palette.fitness)
              ..path(color: palette.fatigue)
              ..path(color: palette.form),
          );
        });
      }
    }

    // Issue #666 round 8: one fixed trio could not clear WCAG 1.4.11's 3:1
    // non-text floor in both themes — the old indigo was 2.57:1 on the dark
    // card and the old amber 1.94:1 on the light one. Each series is a
    // graphical object carrying meaning alone, so each owes 3:1 to the card
    // it is drawn on, and the three must separate from each other.
    for (final entry in {
      'light': (TrainingLoadPalette.light, AppTheme.parchment),
      'dark': (TrainingLoadPalette.dark, AppTheme.duskDeep),
    }.entries) {
      test('series clear 3:1 on the ${entry.key} card and separate', () {
        final (palette, card) = entry.value;
        final series = <String, Color>{
          'fitness': palette.fitness,
          'fatigue': palette.fatigue,
          'form': palette.form,
        };
        for (final s in series.entries) {
          final ratio = _contrast(s.value, card);
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: '${s.key} is $ratio against the ${entry.key} card');
        }
        // Pairwise 3:1 is unreachable for three series that each also owe
        // 3:1 to their card, so the floor here is the achievable one and the
        // ORDER is what has to hold: a strictly monotone luminance ladder is
        // what survives greyscale and red-green colour-vision deficiency.
        final byLuminance = series.values.map(_luminance).toList()..sort();
        for (var i = 0; i + 1 < byLuminance.length; i++) {
          final ratio = (byLuminance[i + 1] + 0.05) / (byLuminance[i] + 0.05);
          expect(ratio, greaterThanOrEqualTo(1.7),
              reason: 'adjacent ${entry.key} series separate by only $ratio');
        }
      });
    }

    testWidgets('the three series hues are mutually distinct', (tester) async {
      for (final palette in [
        TrainingLoadPalette.light,
        TrainingLoadPalette.dark,
      ]) {
        expect(
          <Color>{palette.fitness, palette.fatigue, palette.form}.length,
          3,
        );
      }
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
