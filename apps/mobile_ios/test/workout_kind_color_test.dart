// Issue #666 round 12: the workout-kind palette used to be three raw hexes
// duplicated across `plan_calendar` and `current_week_strip`, and it coloured
// the kind LABEL as well as the cell edge — so it owed WCAG 1.4.3's 4.5:1 and
// delivered 1.973 (tempo), 2.373 (interval) and 1.589 (marathon pace) against
// the light completed-day fill, with `dividerColor` painting REST at 3.029 and
// `primary` painting LONG RUN. None of those hues is on § 480's ban list, which
// is why no guard fired.
//
// The floors below are COMPUTED here rather than quoted, on both cell fills, in
// both themes: the mark owes 1.4.11's 3:1, the label owes 1.4.3's 4.5:1 and now
// reads the `onSurface` token instead of a data hue.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/training.dart';
import '../lib/workout_kind_color.dart';

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

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    // The two fills a day cell paints under the edge mark and the kind label.
    final fills = <(String, Color)>[
      ('surfaceContainerHigh', theme.colorScheme.surfaceContainerHigh),
      ('tertiaryContainer', theme.colorScheme.tertiaryContainer),
      ('card', theme.cardTheme.color!),
    ];

    group('$name workout-kind marks', () {
      test('every kind resolves to a mark clearing 3:1 on every cell fill', () {
        for (final k in WorkoutKind.values) {
          final mark = workoutKindMarkColor(theme, k);
          for (final (where, fill) in fills) {
            expect(_contrast(mark, fill), greaterThanOrEqualTo(3.0),
                reason: '${k.name} mark is ${_contrast(mark, fill)} on the '
                    '$name $where');
          }
        }
      });

      test('the kind label token clears 4.5:1 on every cell fill', () {
        for (final (where, fill) in fills) {
          final ratio = _contrast(theme.colorScheme.onSurface, fill);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'onSurface is $ratio on the $name $where');
        }
      });

      // The label may not borrow a mark hue back: that is the exact regression
      // this round closed, and the marks are built to a 3:1 floor, not 4.5:1.
      test('no kind mark would clear the text floor on both fills', () {
        for (final k in WorkoutKind.values) {
          final mark = workoutKindMarkColor(theme, k);
          final worst = fills
              .map((f) => _contrast(mark, f.$2))
              .reduce((a, b) => a < b ? a : b);
          if (worst >= 4.5) continue;
          expect(mark, isNot(theme.colorScheme.onSurface));
        }
      });
    });
  }

  test('every kind maps into the scale, and the nine collapse to six', () {
    final indices = {
      for (final k in WorkoutKind.values) k: workoutKindMarkIndex(k),
    };
    for (final entry in indices.entries) {
      expect(entry.value, inInclusiveRange(0, ChartPalette.light.kinds.length - 1),
          reason: '${entry.key.name} maps outside the scale');
    }
    expect(indices.values.toSet(), hasLength(ChartPalette.light.kinds.length));
  });

  // Kinds that share a mark must be the ones whose LABELS differ, because the
  // word is the only channel that names the kind once hue is shared.
  test('kinds sharing a mark are distinct workout kinds', () {
    final byIndex = <int, List<WorkoutKind>>{};
    for (final k in WorkoutKind.values) {
      (byIndex[workoutKindMarkIndex(k)] ??= []).add(k);
    }
    expect(byIndex[0], containsAll([WorkoutKind.easy, WorkoutKind.recovery]));
    expect(byIndex[1], containsAll([WorkoutKind.long, WorkoutKind.race]));
    expect(byIndex[4], containsAll([WorkoutKind.interval, WorkoutKind.walkRun]));
  });

  test('the mark resolves per brightness', () {
    for (final k in WorkoutKind.values) {
      expect(workoutKindMarkColor(AppTheme.light, k),
          isNot(workoutKindMarkColor(AppTheme.dark, k)));
    }
  });
}
