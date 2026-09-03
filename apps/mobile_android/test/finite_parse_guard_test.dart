// A `double.tryParse` / `num.tryParse` result must be tested for finiteness
// before it reaches anything that keeps it.
//
// `double.tryParse('NaN')` returns NaN and `double.tryParse('1e400')` returns
// Infinity. Both are NON-NULL, so the `?? 0` and `!= null` guards these calls
// already carry do not see them — the mirror image of the throwing family's
// problem, and the reason a non-finite coordinate reached a `Waypoint` on all
// four import formats (decisions § 954). Downstream, `jsonEncode` REFUSES a
// non-finite double, `toInt()` throws on one, and `LatLng` carries no
// assertion at all, so the value surfaces far from where it was parsed.
//
// `int.tryParse` is deliberately NOT scanned: it answers null for both "NaN"
// and "Infinity" (measured), so it cannot produce one.
//
// A site that genuinely wants an unchecked double opts out with a
// `// unchecked-parse:` marker on the line or in the comment block above it,
// naming what makes it safe. The marker is local rather than a file-level
// allowlist, matching `calendar_day_arithmetic_guard_test.dart`: several of
// these files carry both shapes, and a file-keyed list would go on covering
// the next offender added to it.
//
// decisions § 1011.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib';

const _marker = 'unchecked-parse:';

final _looseParse = RegExp(r'\b(double|num)\.tryParse\s*\(');

/// Block openers that are control flow rather than a function body. Their `{`
/// is also preceded by a `)`, so the body finder has to tell them apart.
const _controlKeywords = {'if', 'for', 'while', 'switch', 'catch'};

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

/// The source range of the FUNCTION body enclosing [at], or the whole file
/// when the call sits at top level.
///
/// Walks out through enclosing brace blocks and stops at the first whose `{`
/// is preceded by a parameter list that is not an `if` / `for` / `while` /
/// `switch` / `catch` head. Stopping at the innermost block would reject the
/// common shape where the parse and its test are siblings in a function but
/// the parse happens to sit inside an `if`; not stopping at all would accept a
/// class body where some unrelated method mentions `isFinite`.
(int, int) _enclosingFunctionBody(String src, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = src[i];
    if (c == '}') {
      depth++;
    } else if (c == '{') {
      if (depth > 0) {
        depth--;
        continue;
      }
      if (_isFunctionBodyBrace(src, i)) return (i, _matchingClose(src, i));
    }
  }
  return (0, src.length);
}

/// Whether the `{` at [open] opens a function body rather than a control
/// block, a class body, a map literal or a collection `for`.
bool _isFunctionBodyBrace(String src, int open) {
  var j = open - 1;
  while (j >= 0 && _isSpace(src[j])) {
    j--;
  }
  if (j < 0) return false;
  // `async {` / `sync* {` — a function body with a modifier between the
  // parameter list and the brace.
  final tail = src.substring((j - 6).clamp(0, j + 1), j + 1);
  if (tail.endsWith('async') || tail.endsWith('sync*') || tail.endsWith('=>')) {
    return true;
  }
  if (src[j] != ')') return false;
  // Walk back over the parameter list to the token that introduced it.
  var depth = 0;
  var k = j;
  for (; k >= 0; k--) {
    if (src[k] == ')') {
      depth++;
    } else if (src[k] == '(') {
      depth--;
      if (depth == 0) break;
    }
  }
  if (k < 0) return false;
  var m = k - 1;
  while (m >= 0 && _isSpace(src[m])) {
    m--;
  }
  var n = m;
  while (n >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(src[n])) {
    n--;
  }
  return !_controlKeywords.contains(src.substring(n + 1, m + 1));
}

int _matchingClose(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') {
      depth++;
    } else if (src[i] == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return src.length;
}

/// The identifier that introduces the function body starting at [open], or ''
/// when it has none (a closure, a top-level expression).
String _functionNameAt(String src, int open) {
  var j = open - 1;
  while (j >= 0 && (_isSpace(src[j]) || src[j] == '{')) {
    j--;
  }
  // Skip an `async` / `sync*` / `=>` modifier back to the parameter list.
  var depth = 0;
  for (; j >= 0; j--) {
    if (src[j] == ')') {
      depth++;
    } else if (src[j] == '(') {
      depth--;
      if (depth == 0) break;
    }
  }
  if (j < 0) return '';
  var m = j - 1;
  while (m >= 0 && _isSpace(src[m])) {
    m--;
  }
  var n = m;
  while (n >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(src[n])) {
    n--;
  }
  return src.substring(n + 1, m + 1);
}

/// The names of functions in [code] whose own body tests finiteness.
///
/// A parse guarded by calling one of these is guarded — `isUsableLatitude`
/// and the GPX importer's `_isUsableLat` are the shape, and demanding the
/// literal token at every call site would push authors to inline a predicate
/// that deserves a name and a comment.
Set<String> _finiteGuardHelpers(String code) {
  final names = <String>{};
  for (final m in RegExp('isFinite').allMatches(code)) {
    final (start, _) = _enclosingFunctionBody(code, m.start);
    final name = _functionNameAt(code, start);
    if (name.isNotEmpty) names.add(name);
  }
  // An expression-bodied declaration has no brace body for the walk above to
  // land on, and the shortest guard predicates are exactly that shape.
  for (final m in _arrowDecl.allMatches(code)) {
    if (m.group(2)!.contains('isFinite')) names.add(m.group(1)!);
  }
  return names;
}

final _arrowDecl = RegExp(r'([A-Za-z0-9_$]+)\s*\([^()]*\)\s*=>([^;]*);');

bool _markedAt(List<String> lines, int line) {
  if (lines[line - 1].contains(_marker)) return true;
  for (var i = line - 2; i >= 0; i--) {
    final t = lines[i].trim();
    if (!t.startsWith('//')) return false;
    if (t.contains(_marker)) return true;
  }
  return false;
}

void main() {
  test('every loose numeric parse is tested for finiteness', () {
    expect(rootExists(_root), isTrue, reason: 'scan root $_root has moved');

    final offenders = <String>[];
    for (final file in dartFiles(_root)) {
      final raw = file.readAsStringSync();
      final rel = file.path.replaceFirst(RegExp(r'^.*?(?=lib/)'), '');
      final code = blankNonCode(raw);
      final rawLines = raw.split('\n');
      final helpers = _finiteGuardHelpers(code);
      for (final match in _looseParse.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        if (_markedAt(rawLines, line)) continue;
        final (start, end) = _enclosingFunctionBody(code, match.start);
        final body = code.substring(start, end);
        if (body.contains('isFinite')) continue;
        if (helpers.any(body.contains)) continue;
        offenders.add('$rel:$line  ${match.group(1)}.tryParse');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'tryParse answers NaN for "NaN" and Infinity for "1e400", both '
          'non-null — test the result with isFinite before anything keeps it. '
          'If the site really wants an unchecked double, mark it '
          '`// $_marker <why>`:\n${offenders.join('\n')}',
    );
  });

  test('the guard still sees the shape it exists to catch', () {
    // A scan that silently matches nothing passes the test above for the wrong
    // reason (§ 510 found exactly that in `status_color`).
    const sample = '''
      final a = double.tryParse(x);
      final b = num.tryParse(y);
      final c = int.tryParse(z);
    ''';
    expect(_looseParse.allMatches(sample).length, 2);
  });

  test('the body finder stops at the function, not at the block or the class',
      () {
    const src = '''
class A {
  double? bad(String s) {
    if (s.isNotEmpty) {
      final v = double.tryParse(s);
      return v;
    }
    return null;
  }

  double? good(String s) {
    final v = double.tryParse(s);
    return (v != null && v.isFinite) ? v : null;
  }
}
''';
    final matches = _looseParse.allMatches(src).toList();
    expect(matches.length, 2);
    // The first sits inside an `if` block, so an innermost-block rule would
    // look in the wrong place; the enclosing FUNCTION has no isFinite.
    final (s0, e0) = _enclosingFunctionBody(src, matches[0].start);
    expect(src.substring(s0, e0).contains('isFinite'), isFalse);
    // The second's function does — and the class body around it is not what
    // answered, or the first would have passed on its sibling's guard.
    final (s1, e1) = _enclosingFunctionBody(src, matches[1].start);
    expect(src.substring(s1, e1).contains('isFinite'), isTrue);
    expect(src.substring(s1, e1).contains('bad'), isFalse);
  });
}
