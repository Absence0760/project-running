// Source-scan guard for issue #666. `SegmentedButton` divides the width it is
// given equally between its segments and then truncates the labels inside
// them — no ellipsis, no fade, no overflow banner. Measured against real
// Roboto across the seven ARB locales at 320 / 360 / 411 dp and 1.0x / 2.0x,
// ten of the app's eleven segmented controls lost characters; two of them at
// 1.0x, with no text scaling involved at all. Given room instead of a bound it
// takes its intrinsic width and bursts the container (decisions § 500).
//
// The replacement is ui_kit's `ChoiceChipRow`. The ban is allowlist-free on
// purpose: the one control that measured clean did so only for its two current
// labels in seven current locales, which is not a property, it is a
// coincidence.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Blanks comments and string literals to spaces, preserving offsets.
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
  for (final match
      in RegExp(r'\b(SegmentedButton|ButtonSegment)\b').allMatches(blanked)) {
    final line = '\n'.allMatches(blanked.substring(0, match.start)).length + 1;
    hits.add('$path:$line');
  }
  return hits;
}

void main() {
  test('no screen builds a SegmentedButton', () {
    final files = <File>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
    }
    // Assert the population, not only the property.
    expect(files.length, greaterThan(100));
    final offenders = <String>[];
    for (final file in files) {
      offenders.addAll(_scan(file.readAsStringSync(), file.path));
    }
    expect(offenders, isEmpty,
        reason: 'use ui_kit ChoiceChipRow — a chip is sized by its own label '
            'and the run reflows, so no label is ever truncated. '
            'Offenders: ${offenders.join(', ')}');
  });

  group('the matcher', () {
    test('flags the control', () {
      expect(_scan('SegmentedButton<int>(segments: []);', 'x.dart'),
          ['x.dart:1']);
    });

    test('flags a lone ButtonSegment, which cannot exist without one', () {
      expect(_scan('final s = ButtonSegment(value: 1);', 'x.dart'),
          ['x.dart:1']);
    });

    test('spares a mention inside a line comment', () {
      expect(_scan('// SegmentedButton is banned\n', 'x.dart'), isEmpty);
    });

    test('spares a mention inside a doc block', () {
      expect(_scan('/*\n ButtonSegment\n*/\nChoiceChipRow();', 'x.dart'),
          isEmpty);
    });

    test('spares a mention inside a string literal', () {
      expect(_scan("final s = 'SegmentedButton';", 'x.dart'), isEmpty);
    });

    test('spares the replacement', () {
      expect(_scan('ChoiceChipRow<int>(options: [ChoiceChipOption()]);', 'x.dart'),
          isEmpty);
    });

    test('spares a longer identifier that merely contains the name', () {
      expect(_scan('MySegmentedButtonShim();', 'x.dart'), isEmpty);
    });
  });
}
