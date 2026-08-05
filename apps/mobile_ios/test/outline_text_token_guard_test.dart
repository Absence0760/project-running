// Source-scan guard for issue #666 S7-followup, widened in round 12: NO colour
// source that lacks a 4.5:1 guarantee may paint type. Three families are
// scanned, and each has a correct non-text use, so the rule is positional
// rather than a ban:
//
//  * §487's 3:1 BOUNDARY tokens — `colorScheme.outline` (4.058:1 on the light
//    card, 3.486:1 on light `surfaceContainerHighest`, 2.952:1 on dark
//    `tertiaryContainer`), `outlineVariant`, and `dividerColor` (3.531:1 on the
//    light card, 3.029:1 on the light completed-day fill). Correct for a
//    hairline, a border, a divider or an icon tint; short of WCAG 1.4.3's
//    4.5:1 for the 11-14 sp type these sites carry. `outline` clears AA on the
//    dark card (5.117:1), which is the point: it cannot be RELIED on as text,
//    while `onSurfaceVariant` can (8.459:1 light card, 9.474:1 dark card,
//    5.465:1 on its worst real background). Both halves are computed in
//    `packages/ui_kit/test/outline_token_contrast_test.dart`.
//  * §505's CHART PALETTE scales — `series` / `zones` / `ramp` / `kinds`. Every
//    entry is measured to 1.4.11's 3:1 against its surface and NONE of them is
//    built to 4.5:1; the round-12 `kinds` scale is the reason this family is
//    here, because its predecessor was a label colour.
//  * RAW `Color(0x…)` LITERALS, which carry no measurement at all. A literal in
//    a rasterised share card or over a map basemap is legitimate — neither
//    follows the device theme — so those are count-pinned per file with the
//    ratio that justifies them, on §480's model.
//
// A fourth rule has no constructor to read: a `Color`-returning HELPER holding
// raw literals. That is the exact shape of round 12's bug — a private
// `static Color _kindColor(ThemeData, WorkoutKind)` duplicated across two
// widgets, returning three unmeasured hexes into a `TextStyle` — and it is
// invisible to the classifier because a `switch` arm has no enclosing
// constructor. So a `Color` declaration whose body holds a literal must be
// named here, which forces a new palette into a measured home rather than into
// a widget's private helper.
//
// A blanket ban on `outline` would be wrong — the boundary use is what the
// token is for — so this guard classifies each occurrence by the constructor
// that encloses it, and the classifier itself is pinned in BOTH directions by
// the fixture table below. The load-bearing part is the paren-depth walk: a
// `Text(...)` closed earlier in the same argument list must not make a later
// `Icon(color: outline)` look like text, and a `Text` nested inside a
// `Container` must not be spared by its host.
//
// A third verdict is deliberate. A value assigned to a local, returned from a
// helper, or produced by a switch arm has no enclosing constructor to read, so
// it cannot be classified from syntax — and several of those did feed a
// `TextStyle`. Those are `derived` and fail unless the file carries an exact
// occurrence count here, on §480's model, so the allowlist can only shrink.
//
// When this test fails: move the text site to `colorScheme.onSurfaceVariant`
// (or `onSurface` where the type is the surface's headline). Only a genuinely
// mark-only derived colour earns an allowlist entry, and it must state where
// every use of the value lands.
//
// The scan itself — comment/string blanking, the file walk, and the backwards
// bracket walk that finds the enclosing constructor — lives in
// `test/source_scan.dart`, shared with `font_size_literal_guard_test.dart` and
// `thinned_token_register_test.dart`. That bracket bookkeeping is the load-
// bearing part of all three, so there is one copy of it in the tree.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

/// Roots scanned. `ui_kit` is shared (no twin), and both twins scan it: the
/// widgets in it paint text on the same tokens the screens do, and §505 moved
/// shared colour there, out of reach of a guard that only walked `lib`.
const _roots = ['lib', '../../packages/ui_kit/lib'];

/// Constructors whose `color` is TYPE. `copyWith` / `apply` / `merge` are the
/// `TextTheme` accessors every screen reaches for.
const _textHosts = {'TextStyle', 'copyWith', 'apply', 'merge'};

/// Constructors whose `color` is a MARK, a BOUNDARY or a FILL — 1.4.11's 3:1,
/// which `outline` clears on every surface the app paints it on. Icons sit
/// here whether or not they carry meaning alone: 1.4.11 sets one floor for
/// both, and an icon that is the only carrier of its meaning owes a label
/// under 1.1.1, which is a different guard.
const _markHosts = {
  'Icon', 'ImageIcon', 'IconTheme', 'IconThemeData', 'IconButton',
  'BorderSide', 'Border', 'Divider', 'VerticalDivider', 'OutlineInputBorder',
  'UnderlineInputBorder', 'RoundedRectangleBorder', 'StadiumBorder',
  'CircleBorder', 'BoxDecoration', 'ShapeDecoration', 'Container',
  'DecoratedBox', 'ColoredBox', 'CircleAvatar', 'Chip', 'Card', 'Material',
  'LinearGradient', 'RadialGradient', 'Paint', 'CircularProgressIndicator',
  'LinearProgressIndicator', 'Checkbox', 'Switch', 'Radio', 'Slider',
  // A `Canvas.draw*` colour is a painted mark by construction, and the
  // idiomatic `Paint()..color = …` cascade puts `Paint` out of the walk's
  // reach — the paren has already closed, so the draw call is the encloser.
  // `drawParagraph` is deliberately absent: a paragraph's colour always
  // reaches the canvas through a `TextStyle`, so the inner host decides it and
  // listing the draw op here would only make it possible to spare one.
  'drawLine', 'drawPath', 'drawCircle', 'drawRect', 'drawRRect', 'drawOval',
  'drawArc', 'drawPoints', 'drawVertices', 'drawShadow', 'drawDRRect',
};

enum _Use { text, mark, derived }

/// The colour sources scanned, each with the remedy its violation message
/// carries. `derived` occurrences are counted per family, because what earns an
/// exemption differs: a boundary token held in a local is one claim, a raw hex
/// in a share-card rasteriser is another.
enum _Family { boundary, palette, literal }

final _patterns = <_Family, RegExp>{
  _Family.boundary: RegExp(
      r'colorScheme\.outlineVariant|colorScheme\.outline\b|dividerColor\b'),
  // A chart scale is read either straight off the class or through a local the
  // consumer names `palette`; both forms appear in the tree.
  _Family.palette: RegExp(
      r'ChartPalette\s*\.\s*(?:of|ofTheme)\s*\([^)]*\)\s*\.\s*\w+'
      r'|\.\s*(?:series|zones|ramp|kinds)\s*\['
      r'|palette\s*\.\s*(?:series|zones|ramp|kinds|bar)\b'),
  _Family.literal: RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)'),
};

const _remedies = <_Family, String>{
  _Family.boundary: 'a §487 boundary token is a 3:1 floor (`outline` is '
      '4.058:1 on the light card, `dividerColor` 3.029:1 on the light '
      'completed-day fill) — use `onSurfaceVariant`',
  _Family.palette: 'a §505 chart scale is measured to 1.4.11\'s 3:1, not to '
      '4.5:1 — the mark keeps the hue, the label takes a text token',
  _Family.literal: 'a raw hex carries no measurement — put it in a per-'
      'brightness palette and read a text token here',
};

/// family -> file -> exact expected count of `derived` occurrences. Each entry
/// must name where the value lands. Raw literals are NOT counted here: 141 of
/// them are palette definitions, and the shape that actually hides a palette —
/// a `Color`-returning helper — is pinned by [_colorHelpers] instead.
const _derivedAllowlist = <_Family, Map<String, int>>{
  _Family.boundary: {
    // The two line tokens are DEFINED here, as `parchmentLine` / `duskLine`
    // reads that land in `dividerColor` and `dividerTheme`.
    '../../packages/ui_kit/lib/src/theme/app_theme.dart': 2,
    // A local held for a chart axis + gridline, both `Paint`.
    'lib/screens/dashboard_screen.dart': 1,
    // `_SetPip` builds a (colour, icon) pair and the colour reaches nothing but
    // `Icon(color:)` — the pip has no label of its own.
    'lib/widgets/gym_execution_band.dart': 1,
  },
  _Family.palette: {
    // Each of these holds the scale (or one entry of it) in a local and paints
    // bars, strokes, dots or a cell edge with it — no `TextStyle` in any.
    'lib/screens/dashboard_screen.dart': 1,
    'lib/screens/run_detail_screen.dart': 1,
    'lib/widgets/intensity_card.dart': 1,
    'lib/widgets/mileage_trend_card.dart': 1,
    'lib/widgets/this_week_strip.dart': 1,
    'lib/widgets/training_load_chart.dart': 1,
    // The workout-kind mark, resolved once for both plan surfaces.
    'lib/workout_kind_color.dart': 1,
  },
};

/// file -> exact expected count of raw literals in TEXT position, with the
/// measured ratio that justifies each. Every entry paints on a surface the
/// device theme does not control, which is the only reason a fixed hex can be
/// measured at all.
const _textLiteralAllowlist = <String, int>{
  // Rasterised share-card PNGs on a fixed #0B0A1F panel: #9CA3AF reads
  // 7.677:1 there, and the card does not follow the device theme by design.
  'lib/widgets/run_share_card.dart': 4,
  'lib/widgets/route_share_card.dart': 3,
  // The period share card inside the screen that builds it — same fixed panel.
  'lib/screens/period_summary_screen.dart': 3,
  // Map-pin labels drawn on an 85%-white chip over basemap tiles, not on a
  // theme surface: #1E293B is 14.629:1 on white and 10.364:1 at the worst
  // backing (a black tile showing through the chip).
  'lib/widgets/live_run_map.dart': 2,
  // The map cluster-count pin: #0F172A on the 95%-opaque coral disc, 8.578:1
  // opaque and 7.747:1 with a black tile behind it.
  'lib/screens/routes_heatmap_screen.dart': 1,
};

/// `Color` declarations permitted to hold raw literals, with where the value
/// lands. Anything not listed must take its hues from a measured palette.
const _colorHelpers = <String, int>{
  // Course start/finish checkpoint hues + a `#rrggbb` string parser; both feed
  // map pins and a `BoxDecoration`, never a `TextStyle`.
  'lib/screens/roadbook_screen.dart': 2,
  // Heat-density cell fill, drawn over map tiles.
  'lib/screens/run_heatmap_screen.dart': 1,
  // Badge tier hue — reaches the tier ring and the trophy glyph.
  'lib/widgets/badge_grid.dart': 1,
  // Course-marker pin fill parsed out of the marker kind's `#rrggbb`.
  'lib/widgets/live_run_map.dart': 1,
  'lib/widgets/route_markers_panel.dart': 1,
  // Route-condition severity dot.
  'lib/widgets/route_conditions.dart': 1,
};

/// A `foregroundColor:` argument is type wherever it appears, and the
/// classifier cannot see it: its enclosing constructor is
/// `TextButton.styleFrom(`, which also takes a `backgroundColor`, so the
/// constructor name cannot decide. The PARAMETER name can, so it is matched
/// directly. Two sites painted a button label in an unmeasured `#8B5CF6`
/// (3.828:1 on the light card) before round 12.
final _foregroundParam = RegExp(
  r'foregroundColor\s*:\s*(?:const\s+)?'
  r'(?:[\w.]*colorScheme\.outlineVariant|[\w.]*colorScheme\.outline\b'
  r'|[\w.]*dividerColor\b|Color\(0x[0-9A-Fa-f]{6,8}\))',
);

/// The three boundary tokens §487 sets at 3:1, thinned by an alpha. There is
/// no allowlist because there is no headroom: the strongest multiplier found
/// in the codebase, 0.6, already composites `outline` to 2.134:1 on the light
/// card, so any thinning of a token whose whole guarantee is a 3:1 floor
/// forfeits it. This is §505's "an alpha multiplier is not a contrast
/// argument" made mechanical for the one token family where it is absolute.
final _thinnedBoundary = RegExp(
  r'(?:colorScheme\.outlineVariant|colorScheme\.outline|dividerColor)'
  r'\s*\.\s*with(?:Values|Opacity)\s*\(',
);

const _thinningFixtures = <(String, bool)>[
  // must flag
  ('color: t.colorScheme.outline.withValues(alpha: 0.6)', true),
  ('color: t.colorScheme.outline.withOpacity(0.18)', true),
  ('color: t.colorScheme.outlineVariant.withValues(alpha: 0.5)', true),
  ('color: t.dividerColor.withValues(alpha: 0.4)', true),
  ('color: t.colorScheme.outline\n    .withValues(alpha: 0.25),', true),
  // must spare: a token with its own foreground floor may be tinted into a
  // FILL, and the bare boundary token is the correct use.
  ('color: t.colorScheme.primary.withValues(alpha: 0.08)', false),
  ('color: t.colorScheme.onSurfaceVariant.withValues(alpha: 0.12)', false),
  ('color: t.colorScheme.outline', false),
  ('color: t.dividerColor', false),
];

/// The verdict for the occurrence at [at], read off the innermost enclosing
/// constructor `enclosingHosts` reports. Only brackets still OPEN at [at] count
/// as enclosing — that is the whole boundary between this and a backwards
/// regex, and the fixtures pin it from both sides.
_Use classify(String src, int at) {
  for (final parts in enclosingHosts(src, at)) {
    // The trailing segment decides type (`…bodySmall?.copyWith`); a mark may
    // be reached through a named factory, so any segment counts
    // (`Border.all`, `BoxDecoration.lerp`, `canvas.drawLine`).
    if (_textHosts.contains(parts.last)) return _Use.text;
    if (parts.any(_markHosts.contains)) return _Use.mark;
  }
  return _Use.derived;
}

/// Fixtures. `_Use.derived` cases are the ones the classifier cannot decide
/// from syntax and must therefore refuse.
const _fixtures = <(String, _Use)>[
  // --- must flag: type ---
  ("style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)",
      _Use.text),
  ("style: TextStyle(color: t.colorScheme.outline)", _Use.text),
  ("style: t.textTheme.labelSmall\n"
      "    ?.copyWith(\n"
      "      color: t.colorScheme.outline,\n"
      "      fontWeight: FontWeight.w600,\n"
      "    )", _Use.text),
  ("style: t.textTheme.bodyMedium!.apply(color: t.colorScheme.outline)",
      _Use.text),
  ("style: base.merge(TextStyle(color: t.colorScheme.outline))", _Use.text),
  // A text style nested inside a fill host: the innermost host decides, so
  // the Container must not spare it.
  ("Container(\n"
      "  color: t.colorScheme.surfaceContainerHighest,\n"
      "  child: Text('x',\n"
      "      style: t.textTheme.bodySmall?.copyWith(\n"
      "        color: t.colorScheme.outline,\n"
      "      )),\n"
      ")", _Use.text),

  // --- must spare: marks, boundaries, fills ---
  ("Icon(Icons.chevron_right, color: t.colorScheme.outline)", _Use.mark),
  ("Icon(icon, size: 13, color: t.colorScheme.outline)", _Use.mark),
  ("IconButton(color: t.colorScheme.outline, icon: const Icon(Icons.add),\n"
      "    onPressed: null)", _Use.mark),
  ("BorderSide(color: t.colorScheme.outline)", _Use.mark),
  ("Border.all(color: t.colorScheme.outline)", _Use.mark),
  ("Divider(color: t.colorScheme.outline)", _Use.mark),
  ("BoxDecoration(color: t.colorScheme.outline)", _Use.mark),
  ("Container(color: t.colorScheme.outline)", _Use.mark),
  ("CircleAvatar(backgroundColor: t.colorScheme.outline)", _Use.mark),
  ("OutlineInputBorder(\n"
      "  borderSide: BorderSide(color: t.colorScheme.outline),\n"
      ")", _Use.mark),
  // The `Paint()..color = …` cascade: `Paint(` has closed by the time the walk
  // starts, so the draw call is what must cast the verdict.
  ("canvas.drawLine(a, b, Paint()\n"
      "  ..color = t.colorScheme.outline\n"
      "  ..strokeWidth = 1)", _Use.mark),
  // A paragraph's colour always reaches the canvas through a `TextStyle`, so
  // the inner host decides and `drawParagraph` never needs to be consulted —
  // which is why it is absent from the mark set rather than listed there.
  ("canvas.drawParagraph(build(TextStyle(color: t.colorScheme.outline)), o)",
      _Use.text),
  // The reason the depth walk exists: a CLOSED text style earlier in the
  // same argument list is not an encloser. A backwards regex flags this.
  ("Row(children: [\n"
      "  Text('a', style: t.textTheme.bodySmall?.copyWith(color: fg)),\n"
      "  Icon(Icons.star, color: t.colorScheme.outline),\n"
      "])", _Use.mark),
  // Same trap one level deeper: a closed `TextStyle(` then a border.
  ("DecoratedBox(\n"
      "  decoration: BoxDecoration(\n"
      "    border: Border.all(color: t.colorScheme.outline),\n"
      "  ),\n"
      "  child: Text('a', style: TextStyle(color: fg)),\n"
      ")", _Use.mark),

  // --- must refuse to decide: no enclosing constructor ---
  ("final c = t.colorScheme.outline;", _Use.derived),
  ("return t.colorScheme.outline;", _Use.derived),
  ("final fg = on ? t.colorScheme.primary : t.colorScheme.outline;",
      _Use.derived),
  // The two that catch the depth walk being removed: a host call that has
  // already CLOSED before the occurrence is a sibling, not an encloser, so
  // neither of these may borrow its verdict. Drop the depth bookkeeping and
  // the first reads `mark` and the second `text`.
  ("Icon(Icons.done, color: t.colorScheme.primary);\n"
      "final c = t.colorScheme.outline;", _Use.derived),
  ("Text('a', style: t.textTheme.bodySmall?.copyWith(color: fg));\n"
      "final c = t.colorScheme.outline;", _Use.derived),
  ("final (c, i) = !on\n"
      "    ? (t.colorScheme.outline, Icons.radio_button_unchecked)\n"
      "    : (semantic.success, Icons.check_circle);", _Use.derived),
];

void main() {
  test('the classifier decides every fixture the way the rule says', () {
    final wrong = <String>[];
    for (final (source, expected) in _fixtures) {
      final at = source.indexOf('colorScheme.outline');
      expect(at, greaterThanOrEqualTo(0),
          reason: 'fixture carries no occurrence: $source');
      final got = classify(source, at);
      if (got != expected) {
        wrong.add('expected $expected, got $got for:\n$source');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n---\n'));
  });

  test('a mention in a comment or a string is not a use', () {
    const cases = [
      '/// reads 4.058:1, so colorScheme.outline is not a text colour\n',
      '// color: theme.colorScheme.outline,\n',
      '/* style: TextStyle(color: theme.colorScheme.outline) */\n',
      "const k = 'colorScheme.outline';\n",
      'const k = """colorScheme.outline""";\n',
    ];
    final token = _patterns[_Family.boundary]!;
    for (final source in cases) {
      expect(token.hasMatch(blankNonCode(source)), isFalse,
          reason: 'still matched after blanking: $source');
    }
    // …and a real use on the line after a comment survives, at its own line.
    const mixed = '// colorScheme.outline is the boundary token\n'
        'style: TextStyle(color: t.colorScheme.outline)';
    final blanked = blankNonCode(mixed);
    final hits = token.allMatches(blanked).toList();
    expect(hits, hasLength(1));
    expect(blanked.substring(0, hits.single.start).split('\n').length, 2);
  });

  test('the thinning matcher decides every fixture the way the rule says', () {
    final wrong = <String>[];
    for (final (source, shouldFlag) in _thinningFixtures) {
      if (_thinnedBoundary.hasMatch(source) != shouldFlag) {
        wrong.add('expected flag=$shouldFlag for: $source');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('no boundary token is thinned by an alpha', () {
    final violations = <String>[];
    for (final root in _roots) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _thinnedBoundary.allMatches(src)) {
          final line = src.substring(0, m.start).split('\n').length;
          violations.add('${file.path}:$line thins a 3:1 boundary token — at '
              'the strongest multiplier in the tree (0.6) `outline` reads '
              '2.134:1 on the light card, so the floor is gone. Use the token '
              'at full strength, or a token that guards the level you want.');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('every scanned root exists', () {
    for (final root in _roots) {
      expect(rootExists(root), isTrue,
          reason: '$root is scanned but missing — if the package moved, move '
              'this entry with it so the scan stays whole.');
    }
  });

  for (final family in _Family.values) {
    test('no ${family.name} colour source paints type', () {
      final violations = <String>[];
      final derivedSeen = <String, int>{};
      final textSeen = <String, int>{};
      for (final root in _roots) {
        for (final file in dartFiles(root)) {
          final src = blankNonCode(file.readAsStringSync());
          for (final m in _patterns[family]!.allMatches(src)) {
            final use = classify(src, m.start);
            if (use == _Use.mark) continue;
            final line = src.substring(0, m.start).split('\n').length;
            if (use == _Use.text) {
              if (family == _Family.literal) {
                textSeen[file.path] = (textSeen[file.path] ?? 0) + 1;
                continue;
              }
              violations.add('${file.path}:$line paints type in a '
                  '${family.name} colour — ${_remedies[family]}.');
            } else if (family != _Family.literal) {
              derivedSeen[file.path] = (derivedSeen[file.path] ?? 0) + 1;
            }
          }
        }
      }
      final allowed = _derivedAllowlist[family] ?? const <String, int>{};
      violations.addAll(_countDrift(derivedSeen, allowed,
          'derived ${family.name} colour(s). A colour held in a local or '
          'returned from a helper cannot be classified from syntax; if no use '
          'of it lands in a TextStyle, raise the count and say so'));
      if (family == _Family.literal) {
        violations.addAll(_countDrift(textSeen, _textLiteralAllowlist,
            'raw literal(s) in TEXT position. A fixed hex can only be '
            'measured on a surface the device theme does not control (a '
            'rasterised share card, a map basemap); anywhere else, '
            '${_remedies[_Family.literal]}'));
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  }

  test('the foregroundColor matcher decides every fixture the way the rule '
      'says', () {
    const fixtures = <(String, bool)>[
      ('foregroundColor: const Color(0xFF8B5CF6),', true),
      ('foregroundColor: theme.colorScheme.outline,', true),
      ('foregroundColor: t.dividerColor,', true),
      // must spare: a token with its own text floor, and a FILL argument in the
      // same constructor — the parameter name is the whole signal.
      ('foregroundColor: theme.colorScheme.primary,', false),
      ('foregroundColor: theme.colorScheme.onSurfaceVariant,', false),
      ('backgroundColor: const Color(0xFF8B5CF6),', false),
      ('side: const BorderSide(color: Color(0xFF8B5CF6)),', false),
    ];
    final wrong = <String>[];
    for (final (source, shouldFlag) in fixtures) {
      if (_foregroundParam.hasMatch(source) != shouldFlag) {
        wrong.add('expected flag=$shouldFlag for: $source');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('no button foreground reads an unmeasured colour', () {
    final violations = <String>[];
    for (final root in _roots) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _foregroundParam.allMatches(src)) {
          final line = src.substring(0, m.start).split('\n').length;
          violations.add('${file.path}:$line paints a button label in an '
              'unmeasured colour. `foregroundColor` is type wherever it '
              'appears; the hue belongs on the icon or the outline.');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  // The round-12 shape: a private `Color` helper full of raw hexes, invisible to
  // the classifier because a `switch` arm has no enclosing constructor.
  test('no unlisted Color helper holds a raw hex', () {
    final decl = RegExp(
      r'(?:^|[\s;}])(?:static\s+)?Color\??\s+(?:get\s+)?(_?\w+)\s*'
      r'(?:\([^{;=]*\))?\s*(=>|\{)',
      multiLine: true,
    );
    final literal = _patterns[_Family.literal]!;
    final seen = <String, int>{};
    final violations = <String>[];
    for (final root in _roots) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in decl.allMatches(src)) {
          final body = m.group(2) == '=>'
              ? src.substring(m.end, _statementEnd(src, m.end))
              : src.substring(m.end, _blockEnd(src, m.end));
          if (!literal.hasMatch(body)) continue;
          seen[file.path] = (seen[file.path] ?? 0) + 1;
        }
      }
    }
    violations.addAll(_countDrift(seen, _colorHelpers,
        '`Color` helper(s) holding a raw hex. A palette in a private helper is '
        'measured by nothing; move the hues into a per-brightness palette and '
        'read them here'));
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

/// Shared count-pinning: an exact per-file count in both directions, so an
/// allowlist can only ever shrink.
List<String> _countDrift(
  Map<String, int> seen,
  Map<String, int> allowed,
  String what,
) {
  final out = <String>[];
  for (final entry in seen.entries) {
    final expected = allowed[entry.key] ?? 0;
    if (entry.value != expected) {
      out.add('${entry.key}: ${entry.value} $what, allowlist expects '
          '$expected.');
    }
  }
  for (final entry in allowed.entries) {
    if (!seen.containsKey(entry.key)) {
      out.add('${entry.key}: allowlist expects ${entry.value} but found none — '
          'migrated? Remove it.');
    }
  }
  return out;
}

int _statementEnd(String src, int from) {
  final end = src.indexOf(';', from);
  return end < 0 ? src.length : end;
}

int _blockEnd(String src, int from) {
  var depth = 1;
  for (var i = from; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return src.length;
}
