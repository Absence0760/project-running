// Source-scan guard for issue #666 V11's remainder: a numeric `fontSize:` is a
// re-implementation of a step the theme already declares.
//
// §482 put a `textTheme` on `AppTheme` for exactly this reason. Every step it
// resolves to is enumerated and pinned by `packages/ui_kit/test/
// type_scale_test.dart` — 11 (`labelSmall`, the declared micro-label floor),
// 12, 14, 16, 22, 24 and up — so a literal is only ever one of three things: a
// step spelled out by hand, a value BETWEEN two steps (13 was the commonest,
// eight sites, and it is not a step at all), or a dimension that is not type.
//
// The first two are what this guard is for. The third is real and is why the
// classifier exists rather than a ban: `IdentityAvatar.fontSize` sizes the
// initial inside a circle whose diameter the caller chose, so it is a GRAPHIC
// argument — the widget's own default is `size * 0.42` and §497 wrapped it in
// `BoxFit.scaleDown`. Text inside a load-bearing graphic is not on the scale.
//
// The exemptions below are all surfaces the theme deliberately does not reach:
// the three `RepaintBoundary` share rasterisers and the period share card
// (which paint a fixed dark canvas to a PNG, hardcoded hexes and all), the map
// overlay chips / pins / cartographic markers §482 named, the run screen's two
// load-bearing graphics, and `ErrorWidget.builder`, which has no `Theme`
// ancestor at all. Each is count-pinned on §480's model, so a NEW literal in an
// exempted file still fails and a migrated file forces its entry's removal.
//
// When this test fails: name the step (`theme.textTheme.<step>`, or
// `.copyWith(...)` on it when only weight / colour / spacing differ), or drop
// the argument entirely where the ambient `DefaultTextStyle` already is that
// step. Do NOT invent a step per call site — if a surface genuinely needs a
// size the scale does not carry, fix the scale or add a named variant.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _roots = ['lib', '../../packages/ui_kit/lib'];

/// Constructors whose `fontSize:` is a GRAPHIC dimension rather than a step on
/// the type scale. Matched on any segment so a named factory still resolves.
const _graphicHosts = {'IdentityAvatar'};

/// file -> exact expected count of numeric `fontSize:` literals. Every entry
/// states why the theme does not reach the surface.
const _allowlist = <String, int>{
  // `ErrorWidget.builder` is installed before any `MaterialApp`, so there is no
  // `Theme` to read a step from — the same reason the icon beside it takes
  // `AppSemanticColors.dark` statically.
  'lib/main.dart': 1,
  // Fixed dark canvases rasterised to a PNG through a `RepaintBoundary`. Their
  // hexes are theme-free by design (§482), and so are their sizes.
  'lib/widgets/finisher_certificate_card.dart': 9,
  'lib/widgets/route_share_card.dart': 5,
  'lib/widgets/run_share_card.dart': 7,
  'lib/screens/period_summary_screen.dart': 6,
  // Map overlay chips / pins / cartographic markers: drawn over basemap
  // tiles, not over a theme surface, so they carry bespoke values per §482.
  // `run_detail`'s is the map-match pill (black scrim + white type),
  // `routes_heatmap`'s the cluster bubble, `live_run_map`'s the lap and
  // course-marker pins, `route_builder`'s the draggable waypoint pin.
  'lib/screens/run_detail_screen.dart': 2,
  'lib/screens/routes_heatmap_screen.dart': 1,
  'lib/widgets/live_run_map.dart': 2,
  'lib/screens/route_builder_screen.dart': 1,
  // Text inside a graphic whose size is load-bearing, both settled by §497:
  // the Start circle's label (inside `BoxFit.scaleDown`) and the 200 px
  // countdown numeral. No step exists at either size, and should not.
  'lib/screens/run_screen.dart': 2,
  // The file that DEFINES the scale: `textTheme.labelSmall`'s 11, the
  // navigation-bar label style's 12, and the chip label's 14 — in both
  // brightnesses. The chip's is the only one that restates a step rather than
  // declaring a new one, and it has to: `RawChip` reads
  // `chipTheme.labelStyle ?? chipDefaults.labelStyle`, so the override that
  // carries the selected/unselected colour displaces M3's `labelLarge` whole.
  // The step is named in `packages/ui_kit/test/type_scale_test.dart`.
  '../../packages/ui_kit/lib/src/theme/app_theme.dart': 6,
  // `fontSize ?? size * 0.42` — the 0.42 is a ratio of the circle's diameter,
  // not a size. This is the derivation the graphic exemption points at.
  '../../packages/ui_kit/lib/src/widgets/identity_avatar.dart': 1,
};

final _fontSizeArg = RegExp(r'\bfontSize\s*:');

/// A bare numeric literal. The lookbehind is what keeps `FontWeight.w600` and
/// `bodySmall2` out of it, and it is why `fontSize: kMapAttributionFontSize`
/// and `fontSize: t.textTheme.labelSmall?.fontSize` are spared without an
/// entry: a named reference to the scale is the durable form, not a violation.
final _numericLiteral = RegExp(r'(?<![\w.])\d+(?:\.\d+)?');

/// The argument expression that follows the `fontSize:` ending at [after] — up
/// to the depth-0 comma or the bracket that closes the argument list. Needed
/// because the literal may sit inside a ternary rather than immediately after
/// the colon (`fontSize: widget.isDragging ? 14 : 11`).
String argumentAt(String src, int after) {
  var depth = 0;
  for (var i = after; i < src.length; i++) {
    final c = src[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return src.substring(after, i);
      depth--;
    } else if (c == ',' && depth == 0) {
      return src.substring(after, i);
    }
  }
  return src.substring(after);
}

/// Whether the `fontSize:` ending at [after] states a numeric size that the
/// type scale should have supplied.
bool statesLiteralSize(String src, int after) {
  if (!_numericLiteral.hasMatch(argumentAt(src, after))) return false;
  for (final parts in enclosingHosts(src, after)) {
    if (parts.any(_graphicHosts.contains)) return false;
    // Anything else — `TextStyle(`, a `TextTheme` accessor's `copyWith` — is
    // the scale's own territory, and the INNERMOST host is what decides, so
    // stop rather than keep walking out to a graphic that merely contains it.
    if (parts.last.isNotEmpty) return true;
  }
  return true;
}

const _fixtures = <(String, bool)>[
  // --- must flag ---
  ('style: const TextStyle(fontSize: 13)', true),
  ('style: t.textTheme.bodySmall?.copyWith(fontSize: 11)', true),
  ('style: TextStyle(\n'
      '  fontSize: 16,\n'
      '  fontWeight: FontWeight.w600,\n'
      ')', true),
  ('style: TextStyle(fontSize:\n    12,\n  color: fg)', true),
  // A ternary of literals is two baked sizes, not an expression off the scale.
  ('style: TextStyle(fontSize: widget.isDragging ? 14 : 11)', true),
  // The graphic host must not spare a `TextStyle` NESTED inside it.
  ('IdentityAvatar(\n'
      "  seed: 'x',\n"
      "  child: Text('a', style: TextStyle(fontSize: 12)),\n"
      ')', true),
  // Why the depth walk exists: an `IdentityAvatar(...)` that has already
  // CLOSED is a sibling, not an encloser, so it cannot lend its exemption.
  ('Row(children: [\n'
      "  IdentityAvatar(seed: 'a', size: 24, fontSize: 10),\n"
      "  Text('b', style: TextStyle(fontSize: 12)),\n"
      '])', true),

  // --- must spare ---
  ('IdentityAvatar(seed: c.id, name: c.name, size: 56, fontSize: 24)', false),
  ('IdentityAvatar(\n'
      '  seed: p.authorId,\n'
      '  size: 32,\n'
      '  fontSize: 14)', false),
  // A named constant and a read off the scale are both the durable form.
  ('style: TextStyle(fontSize: kMapAttributionFontSize)', false),
  ('style: TextStyle(fontSize: t.textTheme.labelSmall?.fontSize)', false),
  ('style: TextStyle(fontSize: fontSize ?? size * ratio)', false),
  // A different argument that merely starts with the same word.
  ('style: t.textTheme.bodySmall!.apply(fontSizeDelta: 2)', false),
  // The mirror of the depth trap: a closed `TextStyle` does not condemn a
  // later graphic argument.
  ('Row(children: [\n'
      "  Text('b', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),\n"
      "  IdentityAvatar(seed: 'a', size: 24, fontSize: 10),\n"
      '])', false),
  // The one that pins the depth bookkeeping for THIS matcher: a `fontSize:`
  // sits adjacent to its own host, so the walk only has work to do when an
  // earlier argument of that host carries a closed call. Drop the bookkeeping
  // and `diameter(` reads as the encloser, which flags a graphic argument.
  ('IdentityAvatar(seed: seedOf(id), size: diameter(56), fontSize: 24)', false),
];

void main() {
  test('the classifier decides every fixture the way the rule says', () {
    final wrong = <String>[];
    for (final (source, shouldFlag) in _fixtures) {
      final m = _fontSizeArg.allMatches(source).toList();
      if (shouldFlag) {
        expect(m, isNotEmpty, reason: 'fixture carries no fontSize: $source');
      }
      final got = m.any((x) => statesLiteralSize(source, x.end));
      if (got != shouldFlag) {
        wrong.add('expected flag=$shouldFlag, got $got for:\n$source');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n---\n'));
  });

  test('a fontSize in a comment or a string is not a use', () {
    const cases = [
      '// style: TextStyle(fontSize: 13),\n',
      '/// the sub-11 fontSize: 9 overrides were raised onto the token\n',
      "const k = 'fontSize: 12';\n",
    ];
    for (final source in cases) {
      expect(_fontSizeArg.hasMatch(blankNonCode(source)), isFalse,
          reason: 'still matched after blanking: $source');
    }
  });

  test('every scanned root exists', () {
    for (final root in _roots) {
      expect(rootExists(root), isTrue,
          reason: '$root is scanned but missing — if the package moved, move '
              'this entry with it so the scan stays whole.');
    }
  });

  test('no numeric fontSize literal outside the recorded exemptions', () {
    final violations = <String>[];
    final seen = <String, int>{};
    for (final root in _roots) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _fontSizeArg.allMatches(src)) {
          if (!statesLiteralSize(src, m.end)) continue;
          final line = src.substring(0, m.start).split('\n').length;
          final allowed = _allowlist[file.path];
          if (allowed == null) {
            violations.add('${file.path}:$line states a numeric font size — '
                'name the step instead (`theme.textTheme.<step>`, or drop the '
                'argument where the ambient DefaultTextStyle already is it).');
          } else {
            seen[file.path] = (seen[file.path] ?? 0) + 1;
          }
        }
      }
    }
    for (final entry in seen.entries) {
      final allowed = _allowlist[entry.key]!;
      if (entry.value != allowed) {
        violations.add('${entry.key}: ${entry.value} numeric font size(s), '
            'allowlist expects $allowed. The exemption is per surface, not per '
            'file forever — a new literal here needs its own justification.');
      }
    }
    for (final entry in _allowlist.entries) {
      if (!seen.containsKey(entry.key)) {
        violations.add('${entry.key}: allowlist expects ${entry.value} '
            'literal(s) but found none — migrated? Remove the entry.');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
