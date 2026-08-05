// Source-scan guard for issue #666 S7-followup: `colorScheme.outline` is
// §487's 3:1 BOUNDARY token — correct for a hairline, a border, a divider or
// an icon tint, wrong for type. Measured against the real tokens it reads
// 4.058:1 on the light card, 3.486:1 on light `surfaceContainerHighest` and
// 2.952:1 on dark `tertiaryContainer` — short of WCAG 1.4.3's 4.5:1 for the
// 11-14 sp body and label type these sites carry. It clears AA on the dark
// card (5.117:1), which is the point: `outline` cannot be RELIED on as text,
// while `onSurfaceVariant` can (8.459:1 light card, 9.474:1 dark card, and
// 5.465:1 on its worst real background). Both halves are computed in
// `packages/ui_kit/test/outline_token_contrast_test.dart`.
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
// When this test fails: move the text site to `colorScheme.onSurfaceVariant`.
// Only a genuinely mark-only derived colour earns an allowlist entry, and it
// must state where every use of the value lands.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
};

enum _Use { text, mark, derived }

/// file -> exact expected count of `derived` occurrences. Each entry must name
/// where the value lands.
const _derivedAllowlist = <String, int>{
  // `_SetPip` builds a (colour, icon) pair and the colour reaches nothing but
  // `Icon(color:)` — the pip has no label of its own.
  'lib/widgets/gym_execution_band.dart': 1,
};

final _token = RegExp(r'colorScheme\.outline\b');

/// The verdict for the occurrence at [at], read off the innermost enclosing
/// constructor. Walks backwards tracking bracket depth so only brackets still
/// OPEN at [at] count as enclosing — that is the whole boundary between this
/// and a backwards regex, and fixtures pin it from both sides.
_Use classify(String src, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = src[i];
    if (c == ')' || c == ']' || c == '}') {
      depth++;
    } else if (c == '(' || c == '[' || c == '{') {
      if (depth > 0) {
        depth--;
        continue;
      }
      var j = i - 1;
      while (j >= 0 && _isSpace(src[j])) {
        j--;
      }
      var k = j;
      while (k >= 0 && _isNamePart(src[k])) {
        k--;
      }
      final parts = src
          .substring(k + 1, j + 1)
          .replaceAll(RegExp(r'[?!]'), '')
          .split('.');
      // The trailing segment decides type (`…bodySmall?.copyWith`); a mark
      // may be reached through a named factory, so any segment counts
      // (`Border.all`, `BoxDecoration.lerp`).
      if (_textHosts.contains(parts.last)) return _Use.text;
      if (parts.any(_markHosts.contains)) return _Use.mark;
    }
  }
  return _Use.derived;
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

bool _isNamePart(String c) =>
    RegExp(r'[A-Za-z0-9_$.?!]').hasMatch(c);

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

/// Comments and string literals blanked to spaces, so offsets and therefore
/// reported line numbers survive. A prose mention of the token in a doc
/// comment is not a use of it — `chart_card_header.dart` explains in its own
/// header why it does not use `outline`.
String blankNonCode(String src) {
  final out = List<String>.from(src.split(''));
  void blank(int from, int to) {
    for (var i = from; i < to && i < out.length; i++) {
      if (out[i] != '\n') out[i] = ' ';
    }
  }

  var i = 0;
  while (i < src.length) {
    if (src.startsWith('//', i)) {
      final end = src.indexOf('\n', i);
      blank(i, end < 0 ? src.length : end);
      i = end < 0 ? src.length : end;
    } else if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      blank(i, end < 0 ? src.length : end + 2);
      i = end < 0 ? src.length : end + 2;
    } else if (src[i] == "'" || src[i] == '"') {
      final q = src[i];
      final triple = src.startsWith(q * 3, i);
      final delim = triple ? q * 3 : q;
      final raw = i > 0 && src[i - 1] == 'r';
      var j = i + delim.length;
      while (j < src.length) {
        if (!raw && src[j] == r'\') {
          j += 2;
          continue;
        }
        if (src.startsWith(delim, j)) break;
        if (!triple && src[j] == '\n') break;
        j++;
      }
      blank(i + delim.length, j);
      i = j + delim.length;
    } else {
      i++;
    }
  }
  return out.join();
}

List<File> _dartFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

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
    for (final source in cases) {
      expect(_token.hasMatch(blankNonCode(source)), isFalse,
          reason: 'still matched after blanking: $source');
    }
    // …and a real use on the line after a comment survives, at its own line.
    const mixed = '// colorScheme.outline is the boundary token\n'
        'style: TextStyle(color: t.colorScheme.outline)';
    final blanked = blankNonCode(mixed);
    final hits = _token.allMatches(blanked).toList();
    expect(hits, hasLength(1));
    expect(blanked.substring(0, hits.single.start).split('\n').length, 2);
  });

  test('every scanned root exists', () {
    for (final root in _roots) {
      expect(Directory(root).existsSync(), isTrue,
          reason: '$root is scanned but missing — if the package moved, move '
              'this entry with it so the scan stays whole.');
    }
  });

  test('colorScheme.outline never paints type', () {
    final violations = <String>[];
    final derivedSeen = <String, int>{};
    for (final root in _roots) {
      for (final file in _dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _token.allMatches(src)) {
          final use = classify(src, m.start);
          if (use == _Use.mark) continue;
          final line = src.substring(0, m.start).split('\n').length;
          if (use == _Use.text) {
            violations.add('${file.path}:$line paints type in `outline` '
                '(4.058:1 on the light card) — use `onSurfaceVariant`.');
          } else {
            derivedSeen[file.path] = (derivedSeen[file.path] ?? 0) + 1;
          }
        }
      }
    }
    for (final entry in derivedSeen.entries) {
      final allowed = _derivedAllowlist[entry.key] ?? 0;
      if (entry.value != allowed) {
        violations.add('${entry.key}: ${entry.value} derived `outline` '
            'colour(s), allowlist expects $allowed. A colour held in a local '
            'or returned from a helper cannot be classified from syntax; if '
            'no use of it lands in a TextStyle, raise the count and say so.');
      }
    }
    for (final entry in _derivedAllowlist.entries) {
      if (!derivedSeen.containsKey(entry.key)) {
        violations.add('${entry.key}: allowlist expects ${entry.value} '
            'derived occurrence(s) but found none — migrated? Remove it.');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
