// Source-scan guard for issue #666 V13: the same icon, for the same role, drawn
// two different ways.
//
// 36 stems shipped in two or three variants — `flag` / `flag_outlined` /
// `flag_rounded`, `emoji_events` beside `emoji_events_outlined`, `place` beside
// `place_outlined`. A reader has no way to tell a filled glyph from an outlined
// one apart from "a different screen drew it", which is the definition of drift.
//
// The rule this pins is ONE VARIANT PER STEM, not one family app-wide, and the
// difference matters. V13's prescribed fix was "pick one family (the app leans
// outlined)" — the app does not: filled leads outlined 697 to 138, with 9
// rounded, so a single-family sweep would have rewritten 147 call sites in the
// direction of the minority and flattened outlined choices that are deliberate
// (empty-state illustrations, the settings rows). One-variant-per-stem is the
// invariant that actually removes the defect: the same role renders the same
// glyph. 66 sites moved, each to its own stem's dominant variant, with ties
// broken toward filled on that 697:138 lean.
//
// A future selected/unselected pair is the one legitimate reason to draw a stem
// both ways — M3's `NavigationDestination(icon:, selectedIcon:)` idiom. There
// are none today (checked: zero `selectedIcon:` in `lib/`), so the exemption is
// deliberately NOT pre-built. Add the stem to `_selectionPairs` with the widget
// that renders it when the first one lands.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _roots = ['lib', '../../packages/ui_kit/lib'];

/// Stems allowed to appear in two variants because a widget draws one for the
/// unselected state and the other for the selected one. Empty by construction —
/// see the header.
const _selectionPairs = <String>{};

String _stem(String name) =>
    name.replaceAll(RegExp(r'_(outlined|rounded|sharp)$'), '');

void main() {
  test('every icon stem is drawn with one variant', () {
    final variants = <String, Set<String>>{};
    final where = <String, Set<String>>{};

    for (final root in _roots.where(rootExists)) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in RegExp(r'Icons\.([a-z0-9_]+)').allMatches(src)) {
          final name = m.group(1)!;
          final stem = _stem(name);
          variants.putIfAbsent(stem, () => <String>{}).add(name);
          where.putIfAbsent(stem, () => <String>{}).add(file.path);
        }
      }
    }

    // Population: a scan that matched nothing would satisfy the check below
    // while proving nothing at all (decisions §534).
    expect(
      variants.length,
      greaterThan(150),
      reason: 'the scan found only ${variants.length} icon stems — it is '
          'probably broken rather than the app having shrunk',
    );

    final offenders = <String>[];
    variants.forEach((stem, names) {
      if (names.length < 2 || _selectionPairs.contains(stem)) return;
      final files = where[stem]!.toList()..sort();
      offenders.add('$stem -> ${(names.toList()..sort()).join(', ')} '
          '(${files.length} file(s))');
    });
    offenders.sort();

    expect(
      offenders,
      isEmpty,
      reason: 'these icons are drawn with more than one variant, so the same '
          'role renders as a different glyph depending on the screen. Pick the '
          'stem\'s dominant variant (ties go to filled). A genuine '
          'selected/unselected pair belongs in _selectionPairs with the widget '
          'that renders it.',
    );
  });
}
