import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/mileage_trend_card.dart';

Run _run({
  required DateTime startedAt,
  required double distanceM,
}) =>
    Run(
      id: 'r-${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: distanceM,
      source: RunSource.app,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Run> runs,
  DistanceUnit unit = DistanceUnit.km,
  required DateTime now,
  double textScale = 1.0,
  Locale? locale,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MileageTrendCard(runs: runs, unit: unit, now: now),
        ),
      ),
    ),
  );
}

void main() {
  final now = DateTime(2026, 5, 19, 12); // Tuesday

  group('MileageTrendCard', () {
    testWidgets(
        'renders the empty-but-framed chart when there are no runs '
        '(3 back-filled buckets — minBuckets=3 opt-in at the card '
        'layer per user request "ensure 3 weeks/months/years are '
        'shown even with little/no data")',
        (tester) async {
      await _pump(tester, runs: const [], now: now);
      // Card frame must render — header label + segmented toggle —
      // even when the data set is empty. Pre-fix this collapsed
      // to SizedBox.shrink and the dashboard had a "missing tile"
      // gap until the user logged their first run.
      expect(find.text('MILEAGE'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
    });

    testWidgets('renders the header + view toggle when populated',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      expect(find.text('MILEAGE'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
    });

    testWidgets('default view is weekly — week labels visible on first frame',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      // Weekly bucket starts Monday 11 May → "May 11".
      expect(find.text('May 11'), findsOneWidget);
    });

    testWidgets(
        'tapping Month switches to monthly buckets ("May \'26" label)',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      await tester.tap(find.text('Month'));
      await tester.pump();
      expect(find.text("May '26"), findsOneWidget);
      expect(find.text('May 11'), findsNothing,
          reason: 'monthly view must replace the weekly bucket label');
    });

    testWidgets('tapping Year switches to yearly buckets (4-digit year label)',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      await tester.tap(find.text('Year'));
      await tester.pump();
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('spotlight headline honours the user unit (km vs mi)',
        (tester) async {
      // The per-bar numeric labels were dropped (they overflowed the
      // narrow weekly view + looked cramped on yearly). The most-
      // recent bucket's value now anchors the card as a spotlight
      // headline. Pin both unit branches of UnitFormat.distance:
      // "10.00 km" vs "6.21 mi".
      // Dated into `now`'s own week (Mon 18 May) — the spotlight reports the
      // CURRENT bucket, so a run from a previous week must not fill it.
      final tenKm = [_run(startedAt: DateTime(2026, 5, 18, 7), distanceM: 10000)];

      await _pump(tester, runs: tenKm, unit: DistanceUnit.km, now: now);
      expect(find.text('10.00 km'), findsOneWidget);
      // Spotlight context suffix — pin the "this week" copy so a
      // future tweak to monthly / yearly fallthrough fails loud.
      expect(find.text('this week'), findsOneWidget);

      await _pump(tester, runs: tenKm, unit: DistanceUnit.mi, now: now);
      // 10 km ≈ 6.21 mi.
      expect(find.text('6.21 mi'), findsOneWidget);
    });

    testWidgets('an idle week spotlights zero, not the last week with data',
        (tester) async {
      // The series used to end at the last bucket WITH DATA while the card
      // labelled that bucket "this week", so a runner who last ran eight days
      // ago read their old total as the current one.
      await _pump(
        tester,
        runs: [_run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 10000)],
        now: now,
      );
      expect(find.text('0.00 km'), findsOneWidget);
      expect(find.text('this week'), findsOneWidget);
      expect(find.text('10.00 km'), findsNothing);
    });

    testWidgets(
        'the axis-label lane scales with the OS text size (issue #666 V12)',
        (tester) async {
      final runs = [_run(startedAt: DateTime(2026, 5, 18, 7), distanceM: 10000)];

      // The label lane is the only fixed-height box under each bar. It holds
      // a rotated labelSmall line, so at 2x it needs 32 px, not 20 — a fixed
      // lane let the label paint back over the bars.
      final lane = find.byWidgetPredicate((w) =>
          w is SizedBox &&
          w.child is Transform &&
          w.height != null);

      final label = find.descendant(of: lane.first, matching: find.byType(Text));

      await _pump(tester, runs: runs, now: now);
      final small = tester.getSize(lane.first).height;
      expect(small, 20);
      expect(tester.getSize(label).height, lessThanOrEqualTo(small));

      await _pump(tester, runs: runs, now: now, textScale: 2.0);
      final grown = tester.getSize(lane.first).height;
      expect(grown, greaterThan(small));
      expect(tester.getSize(label).height, lessThanOrEqualTo(grown));
    });

    testWidgets('the view toggle reflows instead of bursting the card',
        (tester) async {
      // Issue #666 round 9. As a SegmentedButton the toggle overflowed a
      // 360 dp card by 90 px in French and 68 in Spanish at 2x OS text
      // scale, and by 60 px in French at 1.5x on 320 dp — the control takes
      // its intrinsic width whatever the parent offers, so even a line of
      // its own would not have held it.
      addTearDown(tester.view.reset);
      final runs = [
        _run(startedAt: DateTime(2026, 5, 18, 7), distanceM: 5000),
      ];
      for (final width in const [411.0, 360.0, 320.0]) {
        for (final locale in const [
          Locale('en'),
          Locale('fr'),
          Locale('es'),
        ]) {
          for (final scale in const [1.0, 1.5, 2.0]) {
            tester.view.physicalSize = Size(width, 2400);
            tester.view.devicePixelRatio = 1.0;
            await tester.pumpWidget(const SizedBox.shrink());
            // The dashboard supplies a 16 dp gutter, and the card's width
            // is the whole question here, so the harness reproduces it.
            await tester.pumpWidget(MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    MileageTrendCard(
                        runs: runs, unit: DistanceUnit.km, now: now),
                  ],
                ),
              ),
            ));
            final where = '$width dp / $locale / ${scale}x';
            // Deliberately not an exception assertion. The spotlight
            // headline's Row is a different, pre-existing shape — a short
            // stat value beside an Expanded sibling, which § 486 swept and
            // left — and in this harness's fixed-advance test font it bursts
            // at 2x on its own ("5.00 km" wants 308 px of 288). Roboto wants
            // 159 and fits. The toggle is asserted geometrically instead, so
            // the guard does not depend on the harness font.
            tester.takeException();
            // Asserted on the labels, not on the control's type: what has
            // to hold is that all three view options stay inside the card,
            // whatever reflows them.
            final l10n = AppLocalizations.of(
                tester.element(find.byType(MileageTrendCard)));
            for (final label in [
              l10n.mileageWeek,
              l10n.mileageMonth,
              l10n.mileageYear,
            ]) {
              final f = find.text(label);
              expect(f, findsOneWidget, reason: '$where $label');
              expect(tester.getBottomRight(f).dx,
                  lessThanOrEqualTo(width - 16),
                  reason: '$where $label');
            }
          }
        }
      }
    });

    // Issue #666 round 10 S7: the bars drew in colorScheme.primary and the
    // rotated axis labels in colorScheme.outline — a brand token used as data,
    // and §487's 3:1 boundary token used as 11 sp text (4.058:1 on the light
    // card, under WCAG 1.4.3's 4.5:1).
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('bars draw the chart palette in $name', (tester) async {
        await _pump(
          tester,
          runs: [_run(startedAt: DateTime(2026, 5, 18, 7), distanceM: 10000)],
          now: now,
          theme: theme,
        );
        final palette = ChartPalette.ofTheme(theme);
        expect(_barColours(tester), everyElement(palette.bar));
        expect(_barColours(tester), isNot(contains(theme.colorScheme.primary)));
      });

      testWidgets('the axis labels do not paint in the boundary token in $name',
          (tester) async {
        await _pump(
          tester,
          runs: [_run(startedAt: DateTime(2026, 5, 18, 7), distanceM: 10000)],
          now: now,
          theme: theme,
        );
        final labels = tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => t.softWrap == false && t.overflow == TextOverflow.visible)
            .map((t) => t.style?.color)
            .toSet();
        expect(labels, isNotEmpty);
        expect(labels, isNot(contains(theme.colorScheme.outline)));
        expect(labels, everyElement(theme.colorScheme.onSurfaceVariant));
      });
    }

    testWidgets('the header is the shared chart eyebrow', (tester) async {
      await _pump(tester, runs: const [], now: now);
      expect(
        find.ancestor(
          of: find.text('MILEAGE'),
          matching: find.byType(ChartCardHeader),
        ),
        findsOneWidget,
      );
    });
  });
}

/// Fill colours of the rendered bars, in column order.
List<Color> _barColours(WidgetTester tester) => tester
    .widgetList<Container>(find.descendant(
      of: find.byType(MileageTrendCard),
      matching: find.byType(Container),
    ))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.borderRadius is BorderRadius)
    .map((d) => d.color!)
    .toList();
