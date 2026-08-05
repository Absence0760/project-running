import 'dart:math' as math;

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/plan_calendar.dart';

/// The last item §510 left open with a number, plus the sibling it turned out to
/// have: two surfaces dim a whole subtree to say "out of scope" — the plan
/// calendar's adjacent-month cells (was 0.55) and the retired-gear tiles (was
/// 0.65) — and both subtrees contain text and wrap an `InkWell`.
///
/// §510 deferred the calendar as "a layout change on a plan surface". That
/// premise was wrong: `Opacity` is a paint-time widget with no layout effect at
/// all — it sizes and positions its child exactly as if absent and composites
/// the layer afterwards. Changing the value moves no pixel's position.
///
/// What is true is that an `Opacity` around text is a contrast multiplier on
/// that text, so the value is bounded above by 1.4.3 rather than chosen by
/// taste. This derives that bound for both surface families instead of trusting
/// it, and reads the opacity out of the live tree so a per-site literal
/// reappearing is a failure too.
///
/// The same multiplier applies to a MARK, and there the interaction with §505's
/// chart scales is decisive: a `ChartPalette` entry is built to 1.4.11's 3:1
/// against its surface and to nothing more, so it has no headroom to be dimmed
/// at all. That is why the plan calendar's workout branch carries no `Opacity`
/// — the dim and the kind mark are mutually exclusive — and the last two tests
/// below derive that exclusion and then assert the tree honours it.
double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every text pair inside a dimmed subtree, at [opacity].
///
/// Both the glyph and the fill behind it are inside the opacity layer, so BOTH
/// composite over the page — measuring the glyph against an UNDIMMED fill is
/// §503's trap and reports the calendar as passing.
Iterable<(String, double)> _dimmedPairs(ThemeData theme, double opacity) {
  final s = theme.colorScheme;
  final page = theme.scaffoldBackgroundColor;
  Color dim(Color c) => Color.alphaBlend(c.withValues(alpha: opacity), page);
  Iterable<(String, double)> on(String where, Color fill) => [
        ('muted/$where', _contrast(dim(s.onSurfaceVariant), dim(fill))),
        ('body/$where', _contrast(dim(s.onSurface), dim(fill))),
      ];
  return [
    // A calendar cell: scheduled, then completed.
    ...on('surfaceContainerHigh', s.surfaceContainerHigh),
    ...on('tertiaryContainer', s.tertiaryContainer),
    // A retired-gear tile sits on the card fill.
    ...on('card', theme.cardTheme.color!),
  ];
}

/// The fills a plan-calendar or week-strip cell can take, read off the theme
/// rather than hardcoded — a seeded container step that moves must move here.
Map<String, Color> _cellFills(ThemeData theme) => {
      'card': theme.cardTheme.color!,
      'scaffold': theme.scaffoldBackgroundColor,
      'surfaceContainerHigh': theme.colorScheme.surfaceContainerHigh,
      'tertiaryContainer': theme.colorScheme.tertiaryContainer,
    };

/// Every colour [decoration] actually paints: the fill plus each border side.
Iterable<Color> _paintedColors(Decoration? decoration) {
  if (decoration is! BoxDecoration) return const [];
  final border = decoration.border;
  return [
    if (decoration.color != null) decoration.color!,
    if (border != null)
      for (final side in [border.top, border.bottom])
        if (side.style != BorderStyle.none) side.color,
    if (border is Border)
      for (final side in [border.left, border.right])
        if (side.style != BorderStyle.none) side.color,
  ];
}

/// Walks the pumped tree and reports every `ChartPalette` mark that is painted
/// INSIDE a dimmed subtree. Ancestry is why this is an element walk rather than
/// a `find.descendant`: the question is not "does a dimmed Opacity exist" but
/// "is this mark underneath one".
List<String> _marksInsideDim(WidgetTester tester, ThemeData theme) {
  final marks = ChartPalette.ofTheme(theme).kinds.toSet();
  final offenders = <String>[];
  void visit(Element el, bool dimmed) {
    final widget = el.widget;
    final inDim =
        dimmed || (widget is Opacity && widget.opacity < 1);
    if (inDim && widget is Container) {
      for (final decoration in [widget.decoration, widget.foregroundDecoration]) {
        for (final colour in _paintedColors(decoration)) {
          if (marks.contains(colour)) {
            offenders.add('${widget.runtimeType} paints $colour');
          }
        }
      }
    }
    el.visitChildren((child) => visit(child, inDim));
  }

  visit(tester.element(find.byType(PlanCalendar)), false);
  return offenders;
}

Future<Set<double>> _renderedDims(WidgetTester tester) async {
  // April 2024 starts on a Monday, so the Monday-first grid pads with March 31
  // and a run of May days — all adjacent-month cells, one of them carrying a
  // workout so the `InkWell` branch is exercised too.
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PlanCalendar(
        startDate: DateTime(2024, 4, 1),
        endDate: DateTime(2024, 6, 30),
        workouts: [
          PlanWorkoutRow(
            id: 'wo1',
            weekId: 'wk1',
            scheduledDate: DateTime(2024, 5, 2),
            kind: 'tempo',
            targetDistanceM: 10000,
            manuallyCompleted: false,
          ),
        ],
      ),
    ),
  ));
  await tester.pump();
  return tester
      .widgetList<Opacity>(find.byType(Opacity))
      .map((o) => o.opacity)
      .where((o) => o < 1)
      .toSet();
}

void main() {
  testWidgets('the calendar dims by exactly the shared token', (tester) async {
    expect(await _renderedDims(tester), {AppTheme.dimmedSubtreeOpacity},
        reason: 'a per-site opacity literal has come back; both dimmed '
            'surfaces share one bounded token.');
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    test('$name: every text pair clears AA at the shared dim', () {
      final failing = _dimmedPairs(theme, AppTheme.dimmedSubtreeOpacity)
          .where((p) => p.$2 < 4.5)
          .map((p) => '${p.$1}=${p.$2.toStringAsFixed(3)}')
          .toList();
      expect(failing, isEmpty,
          reason: 'an Opacity around text is a contrast multiplier on it, so '
              'the dim is bounded by 1.4.3: $failing');
    });

    test('$name: neither value it replaced did', () {
      for (final was in [0.55, 0.65]) {
        expect(_dimmedPairs(theme, was).where((p) => p.$2 < 4.5), isNotEmpty,
            reason: 'if $was now passes, the tokens moved and the bound below '
                'should be re-derived rather than inherited.');
      }
    });

    test('$name: the shared dim is no stronger than 1.4.3 allows', () {
      // The bound is derived, not asserted: step down in hundredths until the
      // worst pair drops under 4.5. The token deliberately sits a little above
      // it rather than on it — §510's 4.470:1 subtitle shipped precisely
      // because a value on the edge looks like one inside it.
      var bound = 1.0;
      for (var o = 0.99; o > 0.30; o -= 0.01) {
        final worst = _dimmedPairs(theme, o).map((p) => p.$2).reduce(math.min);
        if (worst < 4.5) break;
        bound = o;
      }
      expect(AppTheme.dimmedSubtreeOpacity, greaterThanOrEqualTo(bound - 1e-9),
          reason: 'the dim is stronger than 1.4.3 allows; the bound in this '
              'theme is ${bound.toStringAsFixed(2)}');
    });

    // Derived, not assumed: a `ChartPalette` mark is built to 3:1 and no more,
    // so dimming it must break the floor somewhere. If this ever stops being
    // true the exclusion below is no longer needed and should be revisited
    // rather than kept out of habit.
    test('$name: a kind mark has no headroom left to be dimmed', () {
      final marks = ChartPalette.ofTheme(theme).kinds;
      final page = theme.scaffoldBackgroundColor;
      Color dim(Color c) =>
          Color.alphaBlend(c.withValues(alpha: AppTheme.dimmedSubtreeOpacity),
              page);

      final broken = <String>[];
      _cellFills(theme).forEach((where, fill) {
        final undimmed =
            marks.map((m) => _contrast(m, fill)).reduce(math.min);
        expect(undimmed, greaterThanOrEqualTo(3.0),
            reason: '§505 promises every kind mark 3:1 on $where; worst is '
                '${undimmed.toStringAsFixed(3)}');
        final dimmed =
            marks.map((m) => _contrast(dim(m), dim(fill))).reduce(math.min);
        if (dimmed < 3.0) broken.add('$where=${dimmed.toStringAsFixed(3)}');
      });

      expect(broken, isNotEmpty,
          reason: 'dimming a kind mark at ${AppTheme.dimmedSubtreeOpacity} no '
              'longer breaks 1.4.11 on any cell fill, so the exclusion the '
              'next test enforces may be re-derived rather than assumed.');
    });
  }

  // The structural half of the rule above, and the regression it guards: the
  // workout branch of a calendar cell paints the kind mark, so it must not be
  // wrapped in the dim. Re-adding an `Opacity` there fails here.
  testWidgets('no dimmed subtree paints a ChartPalette mark', (tester) async {
    await _renderedDims(tester);
    expect(_marksInsideDim(tester, AppTheme.light), isEmpty,
        reason: 'a kind mark is built to 1.4.11\'s 3:1 with no headroom, so '
            'dimming it drops the mark under the floor — the out-of-month cue '
            'and the kind mark cannot share a subtree.');
  });
}
