// Source-scan guard for issue #666 S11. Eleven linear progress bars had
// eleven specs — five heights (2 / 4 / 6 / 8 / 10), four radii (none / 3 / 4 /
// 999) and four track colours, three of which cannot carry the state they were
// asked to. `packages/ui_kit`'s `ProgressBar` is now the single spec, so a bare
// `LinearProgressIndicator` in an app screen is the defect: it re-opens the
// choice.
//
// `CircularProgressIndicator` is deliberately out of scope — it is a spinner,
// not a value bar, and has no track/fill state to get wrong.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Blanks comments and string literals to spaces, preserving offsets, so a
/// line number survives and a mention inside a doc comment is not a hit.
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

List<String> _scan(String source, String path) {
  final hits = <String>[];
  final blanked = _blank(source);
  for (final match in RegExp(r'\bLinearProgressIndicator\b').allMatches(blanked)) {
    final line = '\n'.allMatches(blanked.substring(0, match.start)).length + 1;
    hits.add('$path:$line');
  }
  return hits;
}

void main() {
  test('no app screen builds a bare LinearProgressIndicator', () {
    final files = <File>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
    }
    // Assert the population, not only the property: an empty walk would pass.
    expect(files.length, greaterThan(100));
    final offenders = <String>[];
    for (final file in files) {
      offenders.addAll(_scan(file.readAsStringSync(), file.path));
    }
    expect(offenders, isEmpty,
        reason: 'use ui_kit ProgressBar — it owns the height, the radius, the '
            'track and the hairline that makes the bar visible against the '
            'page. Offenders: ${offenders.join(', ')}');
  });

  group('the matcher', () {
    test('flags a real construction', () {
      expect(_scan('Widget b() => LinearProgressIndicator(value: 1);', 'x.dart'),
          ['x.dart:1']);
    });

    test('flags one wrapped in a ClipRRect, which is the shipped shape', () {
      final hits = _scan(
        'ClipRRect(\n  child: LinearProgressIndicator(minHeight: 6),\n)',
        'x.dart',
      );
      expect(hits, ['x.dart:2']);
    });

    test('spares a mention inside a line comment', () {
      expect(_scan('// LinearProgressIndicator is banned here\n', 'x.dart'),
          isEmpty);
    });

    test('spares a mention inside a doc block', () {
      expect(
          _scan('/*\n LinearProgressIndicator\n*/\nProgressBar(value: 1);', 'x.dart'),
          isEmpty);
    });

    test('spares a mention inside a string literal', () {
      expect(_scan("final s = 'LinearProgressIndicator';", 'x.dart'), isEmpty);
    });

    test('spares CircularProgressIndicator', () {
      expect(_scan('CircularProgressIndicator();', 'x.dart'), isEmpty);
    });

    test('spares ProgressBar itself', () {
      expect(_scan('ProgressBar(value: 0.5);', 'x.dart'), isEmpty);
    });
  });
}
