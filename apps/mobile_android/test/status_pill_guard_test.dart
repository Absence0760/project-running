// Source-scan guard for issue #666 S18. Twenty-four status pills had been
// built by hand with nine paddings and four spellings of the label size, two
// of which (`labelMedium` and `bodySmall`) are the same 12sp and so looked
// identical while tracking different tokens. `ui_kit`'s `StatusPill` is now
// the one, and a new hand-built one re-opens the drift.
//
// A "hand-built pill" is a `BoxDecoration` with a stadium radius whose own
// widget also holds a `Text` — a rounded box carrying a label. A stadium
// radius on a `ClipRRect`, an `InkWell`, a gradient legend bar or a container
// that merely *wraps* a labelled child is none of those and is not flagged.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two survivors, each with the reason it is not a `StatusPill`. Count-
/// pinned on § 480's model: the number may only shrink, and an entry that
/// matches nothing fails rather than rotting.
const Map<String, ({int count, String why})> _allowed = {
  'lib/screens/profile_screen.dart': (
    count: 1,
    why: 'an unread COUNT badge, which is Material `Badge`\'s role — a numeral '
        'in a disc, not a status word in a stadium',
  ),
  'lib/screens/run_detail_screen.dart': (
    count: 1,
    why: 'the map-matching pill floats over the MAP, so its ground is a black '
        'scrim rather than the theme (§ 526), and it carries a trailing '
        'action rather than only a label',
  ),
};

String _blank(String src) {
  final out = src.split('');
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      var j = src.indexOf('\n', i);
      if (j < 0) j = src.length;
      for (var k = i; k < j; k++) {
        out[k] = ' ';
      }
      i = j;
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      var j = src.indexOf('*/', i + 2);
      j = j < 0 ? src.length : j + 2;
      for (var k = i; k < j; k++) {
        if (out[k] != '\n') out[k] = ' ';
      }
      i = j;
    } else if (c == '\'' || c == '"') {
      var j = i + 1;
      while (j < src.length) {
        if (src[j] == r'\') {
          j += 2;
          continue;
        }
        if (src[j] == c) {
          j++;
          break;
        }
        if (src[j] == '\n') break;
        j++;
      }
      for (var k = i + 1; k < j - 1 && k < src.length; k++) {
        if (out[k] != '\n') out[k] = ' ';
      }
      i = j;
    } else {
      i++;
    }
  }
  return out.join();
}

const _open = '([{';
const _close = ')]}';

int _matchForward(String s, int i) {
  var depth = 0;
  for (var j = i; j < s.length; j++) {
    if (_open.contains(s[j])) depth++;
    if (_close.contains(s[j])) {
      depth--;
      if (depth == 0) return j;
    }
  }
  return -1;
}

/// The identifier and offset of the innermost still-open call around [i].
(String, int)? _enclosingCall(String s, int i) {
  var depth = 0;
  for (var j = i - 1; j >= 0; j--) {
    final c = s[j];
    if (_close.contains(c)) {
      depth++;
    } else if (_open.contains(c)) {
      if (depth == 0) {
        var k = j - 1;
        while (k >= 0 && (RegExp(r'[A-Za-z0-9_.<>]').hasMatch(s[k]))) {
          k--;
        }
        return (s.substring(k + 1, j), j);
      }
      depth--;
    }
  }
  return null;
}

List<String> scanPills(String source, String path) {
  final hits = <String>[];
  final blanked = _blank(source);
  for (final match
      in RegExp(r'BorderRadius\.circular\(999\)').allMatches(blanked)) {
    final deco = _enclosingCall(blanked, match.start);
    if (deco == null || deco.$1 != 'BoxDecoration') continue;
    final host = _enclosingCall(blanked, deco.$2);
    if (host == null) continue;
    final end = _matchForward(blanked, host.$2);
    if (end < 0) continue;
    final body = blanked.substring(host.$2, end);
    if (!RegExp(r'\bText\(').hasMatch(body)) continue;
    final line = '\n'.allMatches(blanked.substring(0, match.start)).length + 1;
    hits.add('$path:$line');
  }
  return hits;
}

void main() {
  test('every status pill is ui_kit StatusPill', () {
    final files = <File>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
    }
    // Assert the population, not only the property.
    expect(files.length, greaterThan(100));

    final byFile = <String, List<String>>{};
    for (final file in files) {
      final hits = scanPills(file.readAsStringSync(), file.path);
      if (hits.isNotEmpty) byFile[file.path] = hits;
    }

    final unexpected = <String>[];
    byFile.forEach((path, hits) {
      final entry = _allowed[path];
      if (entry == null) {
        unexpected.addAll(hits);
      } else if (hits.length != entry.count) {
        unexpected.add('$path has ${hits.length} pills, allowlist says '
            '${entry.count} (${entry.why})');
      }
    });
    expect(unexpected, isEmpty,
        reason: 'use ui_kit StatusPill — it owns the padding, the type step '
            'and the leading-glyph size, so a call site cannot invent a tenth '
            'padding. Offenders: ${unexpected.join(', ')}');

    // An allowlist entry that matches nothing has rotted; delete it.
    for (final path in _allowed.keys) {
      expect(byFile[path], isNotNull,
          reason: '$path no longer has a hand-built pill — drop its '
              'allowlist entry');
    }
  });

  group('the matcher', () {
    test('flags a rounded box that carries its own label', () {
      const src = '''
Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(999),
  ),
  child: Text(label),
)''';
      expect(scanPills(src, 'x.dart'), ['x.dart:5']);
    });

    test('flags one whose label sits inside a Row beside an icon', () {
      const src = '''
Container(
  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999)),
  child: Row(children: [Icon(a), Text(b)]),
)''';
      expect(scanPills(src, 'x.dart'), ['x.dart:2']);
    });

    test('spares a stadium ClipRRect, which clips rather than decorates', () {
      const src = '''
ClipRRect(
  borderRadius: BorderRadius.circular(999),
  child: Text(label),
)''';
      expect(scanPills(src, 'x.dart'), isEmpty);
    });

    test('spares a stadium InkWell ripple', () {
      const src = 'InkWell(borderRadius: BorderRadius.circular(999), '
          'child: Text(a));';
      expect(scanPills(src, 'x.dart'), isEmpty);
    });

    test('spares a rounded box with no label in it', () {
      const src = '''
Container(
  height: 8,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(999),
    gradient: LinearGradient(colors: c),
  ),
)''';
      expect(scanPills(src, 'x.dart'), isEmpty);
    });

    test('spares StatusPill itself, which takes a String not a Text', () {
      const src = "StatusPill(label: l, foreground: f, fill: b);";
      expect(scanPills(src, 'x.dart'), isEmpty);
    });

    test('spares a mention inside a comment', () {
      const src = '// BoxDecoration(borderRadius: BorderRadius.circular(999)) '
          'plus Text()\n';
      expect(scanPills(src, 'x.dart'), isEmpty);
    });

    test('spares a non-stadium radius', () {
      const src = '''
Container(
  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
  child: Text(b),
)''';
      expect(scanPills(src, 'x.dart'), isEmpty);
    });
  });
}
