// Source-scan guard for issue #666 S7: the dashboard's data-visualisation
// surfaces read ONE header and ONE colour system. Five of them carried four
// colour systems and three header typographies between them, and a sixth had
// no header at all.
//
// Two rules, both about tokens a chart may not borrow:
//
//  * `colorScheme.primary` is a brand / interaction token whose hue is not
//    stable across brightnesses — dusk in light, coral in dark — so a mark
//    painted in it means "data" in one theme and echoes an affordance in the
//    other. §503 recorded this firing on web, where the split bar's two halves
//    landed 1.032:1 apart in dark because `--color-primary` flips to the same
//    coral the warm series already used. Chart marks come from `ChartPalette`.
//  * `colorScheme.outline` is §487's 3:1 boundary token. It reads 4.058:1 on
//    the light card, so as the 11-12 sp type these cards carry it is under WCAG
//    1.4.3's 4.5:1. Text on a chart card takes `onSurfaceVariant`.
//
// Both are count-pinned per surface, so an allowlisted occurrence that is
// migrated forces its entry down and a NEW occurrence in an already-listed file
// still fails. The counts may only shrink.
//
// When this test fails: route the colour through `ChartPalette` (marks) or
// `onSurfaceVariant` (text) rather than raising a count.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The surfaces in scope, and for `dashboard_screen.dart` the region of it that
/// is a chart — the file is a whole screen, so only the heatmap counts.
const _surfaces = <String, String?>{
  'lib/widgets/this_week_strip.dart': null,
  'lib/widgets/mileage_trend_card.dart': null,
  'lib/widgets/intensity_card.dart': null,
  'lib/widgets/training_load_chart.dart': null,
  'lib/screens/dashboard_screen.dart': 'class _RunHeatmap',
};

/// surface -> token -> exact expected occurrences. Every entry is a documented
/// non-mark, non-text use.
const _allowed = <String, Map<String, int>>{
  // "Today" is a state marker, not a datum: it is the one ring on the strip
  // that must NOT read as a bar, which is exactly why it keeps the accent.
  'lib/widgets/this_week_strip.dart': {'colorScheme.primary': 1},
};

String _region(String path, String? from) {
  final source = File(path).readAsStringSync();
  if (from == null) return source;
  final at = source.indexOf(from);
  expect(at, greaterThanOrEqualTo(0),
      reason: '$path no longer contains "$from" — move the region marker with '
          'the code rather than dropping the guard');
  return source.substring(at);
}

void main() {
  test('every chart surface exists at its listed path', () {
    for (final path in _surfaces.keys) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path is guarded but missing — if it moved, move the entry');
    }
  });

  test('every chart surface wears the shared header', () {
    for (final entry in _surfaces.entries) {
      expect(_region(entry.key, entry.value), contains('ChartCardHeader'),
          reason: '${entry.key} builds its own chart header');
    }
  });

  test('every chart surface takes its marks from ChartPalette', () {
    for (final entry in _surfaces.entries) {
      expect(_region(entry.key, entry.value), contains('ChartPalette'),
          reason: '${entry.key} does not read the shared chart palette');
    }
  });

  for (final token in ['colorScheme.primary', 'colorScheme.outline']) {
    test('no unallowlisted $token on a chart surface', () {
      for (final entry in _surfaces.entries) {
        final found = token.allMatches(_region(entry.key, entry.value)).length;
        final expected = _allowed[entry.key]?[token] ?? 0;
        expect(found, expected,
            reason: '${entry.key} has $found "$token" where $expected are '
                'allowlisted — route marks through ChartPalette and text '
                'through onSurfaceVariant instead of raising the count');
      }
    });
  }
}
