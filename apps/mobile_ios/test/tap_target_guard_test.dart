import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tap-target guard — pins a >= 48dp hit area (WCAG 2.5.8 / Material touch
/// target) on every IconButton under lib/.
///
/// Two layers:
///  1. Anchored pins on the screens fixed first (#255), so the explicit
///     48dp constraints there can't be quietly dropped.
///  2. A lib/-wide source scan (#664) that fails on any IconButton which
///     (a) carries `VisualDensity.compact`, (b) declares an explicit
///     constraint floor/cap below 48dp, or (c) is boxed by a SizedBox
///     smaller than 48dp.
///
/// Why (a) is a hard ban and not "compact needs a 48dp constraint": compact
/// density subtracts 8dp per axis AFTER explicit constraints are resolved —
/// measured empirically, an IconButton with `visualDensity: compact` AND
/// `BoxConstraints(minWidth: 48, minHeight: 48)` still hit-tests as 40x40.
/// The old "keep compact, add the constraint" idiom was a placebo. The
/// working idiom is: no compact on IconButtons; shrink the *icon*
/// (`size:`/`iconSize:`) for visual tightness and keep the 48dp box.
///
/// Scope is IconButtons only: labeled buttons (Text/Filled/Outlined/
/// Segmented) keep a >= 40dp padded target plus a wide label surface even
/// under compact density, which clears WCAG 2.5.8's 24px floor — the 48dp
/// floor pinned here is the icon-button spec, where the glyph is the whole
/// target.
///
/// Source-level (like architecture_guards_test.dart) because many of these
/// buttons are private widgets or live inside map screens whose
/// `pumpAndSettle` hangs on tile animations.

const _min48 = 'BoxConstraints(minWidth:48,minHeight:48';

/// Read a source file with all whitespace stripped, so the assertions don't
/// care whether a constraint was written inline or across several lines.
String _read(String rel) =>
    File('lib/$rel').readAsStringSync().replaceAll(RegExp(r'\s+'), '');

/// Assert a 48x48 constraint appears in the window of source following [anchor].
void _expectMin48After(String content, String anchor, {int window = 300}) {
  final i = content.indexOf(anchor);
  expect(i, greaterThanOrEqualTo(0), reason: 'anchor "$anchor" not found');
  final slice = content.substring(i, (i + window).clamp(0, content.length));
  expect(slice.contains(_min48), isTrue,
      reason: 'no >=48dp tap-target constraint near "$anchor"');
}

/// The balanced-paren argument span starting at the `(` at [open], skipping
/// quoted strings and line comments so a paren inside a string or comment
/// can't derail the depth count. Returns the span including both parens.
String _argSpan(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == "'" || c == '"') {
      final quote = c;
      i++;
      while (i < source.length) {
        if (source[i] == r'\') {
          i++;
        } else if (source[i] == quote) {
          break;
        }
        i++;
      }
    } else if (c == '/' &&
        i + 1 < source.length &&
        source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}

int _lineOf(String source, int index) =>
    '\n'.allMatches(source.substring(0, index)).length + 1;

List<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Explicit dimension floors/caps declared inside a widget's argument span
/// that would squeeze its box below 48dp.
final _sub48Patterns = <RegExp>[
  RegExp(r'minWidth:\s*(\d+(?:\.\d+)?)'),
  RegExp(r'minHeight:\s*(\d+(?:\.\d+)?)'),
  RegExp(r'tightFor\(\s*width:\s*(\d+(?:\.\d+)?)'),
  RegExp(r'tightFor\([^)]*height:\s*(\d+(?:\.\d+)?)'),
];

List<String> _sub48DimensionFindings(String span) {
  final findings = <String>[];
  for (final p in _sub48Patterns) {
    for (final m in p.allMatches(span)) {
      final v = double.tryParse(m.group(1)!);
      if (v != null && v < 48) findings.add(m.group(0)!);
    }
  }
  return findings;
}

void main() {
  group('anchored pins — the first fixed screens keep their 48dp floors', () {
    test('routes_screen cloud-sync button', () {
      _expectMin48After(
          _read('screens/routes_screen.dart'), 'l10n.routesSyncFromCloud');
    });

    test('route_detail report-review flag button', () {
      _expectMin48After(_read('screens/route_detail_screen.dart'),
          'l10n.routeDetailReportReview');
    });

    test('routes_heatmap pin button', () {
      _expectMin48After(
          _read('screens/routes_heatmap_screen.dart'), 'trailing:IconButton(');
    });

    test('runs_screen nav chevrons (both)', () {
      final c = _read('screens/runs_screen.dart');
      _expectMin48After(c, 'Icons.chevron_left');
      _expectMin48After(c, 'Icons.chevron_right');
    });
  });

  group('lib/-wide: every IconButton keeps a >=48dp tap target', () {
    test('no IconButton pairs with VisualDensity.compact', () {
      // Reason: compact subtracts 8dp/axis after constraint resolution, so
      // it shrinks the tap target to ~40dp even past an explicit 48dp floor
      // (verified by hit-testing). Shrink the icon, never the box.
      final offenders = <String>[];
      for (final f in _libDartFiles()) {
        final src = f.readAsStringSync();
        for (final m in RegExp(r'\bIconButton\(').allMatches(src)) {
          final span = _argSpan(src, m.end - 1);
          if (span.contains('VisualDensity.compact')) {
            offenders.add('${f.path}:${_lineOf(src, m.start)}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'IconButton + VisualDensity.compact yields a ~40dp tap '
              'target (below the 48dp floor, issue #664). Drop the density '
              'and set constraints: BoxConstraints(minWidth: 48, '
              'minHeight: 48) — shrink the icon via size:/iconSize: '
              'instead. Offenders: $offenders');
    });

    test('no IconButton declares a sub-48dp constraint floor', () {
      final offenders = <String>[];
      for (final f in _libDartFiles()) {
        final src = f.readAsStringSync();
        for (final m in RegExp(r'\bIconButton\(').allMatches(src)) {
          final span = _argSpan(src, m.end - 1);
          for (final hit in _sub48DimensionFindings(span)) {
            offenders.add('${f.path}:${_lineOf(src, m.start)} ($hit)');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'IconButton with an explicit dimension below 48dp '
              '(issue #664). Raise the floor to 48. Offenders: $offenders');
    });

    test('no IconButton is boxed by a sub-48dp SizedBox', () {
      // Catches the SizedBox(width: 28, height: 28, child: IconButton(...))
      // pattern, which hard-caps the tap target regardless of the button's
      // own constraints.
      final offenders = <String>[];
      final dim = RegExp(r'\b(?:width|height|dimension):\s*(\d+(?:\.\d+)?)');
      for (final f in _libDartFiles()) {
        final src = f.readAsStringSync();
        for (final m in RegExp(r'\bSizedBox(?:\.square)?\(').allMatches(src)) {
          final span = _argSpan(src, m.end - 1);
          if (!span.contains('IconButton(')) continue;
          // Only the SizedBox's own arguments, not nested widgets': cut the
          // span at the child: argument before reading dimensions.
          final childAt = span.indexOf('child:');
          final own = childAt >= 0 ? span.substring(0, childAt) : span;
          for (final d in dim.allMatches(own)) {
            final v = double.tryParse(d.group(1)!);
            if (v != null && v < 48) {
              offenders.add('${f.path}:${_lineOf(src, m.start)} '
                  '(${d.group(0)})');
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'A SizedBox smaller than 48dp caps the IconButton inside '
              'it below the tap-target floor (issue #664). Size the box '
              '>=48 or drop the wrapper. Offenders: $offenders');
    });
  });
}
